library niks_bitmap;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bitmap/bitmap.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:niks/niks.dart';

import 'filters/filter.dart';

export 'filters/filter.dart';

const String bitmapIdentity = "Bitmap";
const String widthKey = "width";
const String heightKey = "height";
const String xKey = "x";
const String yKey = "y";
const String filtersKey = "filters";

class BitmapLayer implements NiksLayer {
  BitmapLayer.fromLTWH(
      this.bitmap, double left, double top, double width, double height)
      : _size = Size(width, height),
        _coordinates = Offset(left, top),
        _filters = HashMap(),
        super();

  BitmapLayer.fromSnapshot(BitmapLayerSnapshot snapshot)
      : this.fromSnapshotWithBitmapAndImage(Bitmap.blank(1, 1), null, snapshot);

  BitmapLayer.fromSnapshotWithBitmapAndImage(
      this.bitmap, this.resolvedImage, BitmapLayerSnapshot snapshot)
      : uuid = snapshot.uuid,
        _size = Size(snapshot.width, snapshot.height),
        _coordinates = Offset(snapshot.x, snapshot.y),
        _filters = snapshot.filters.map<String, BitmapLayerFilter>(
            (String filterKey, BitmapLayerFilterSnapshot filterSnapshot) {
          return MapEntry<String, BitmapLayerFilter>(
              filterKey, filterSnapshot.createFilter());
        }),
        super();

  @override
  bool locked;

  @override
  String uuid;

  @override
  Size get size => _size;

  @override
  Offset get coordinates => _coordinates;

  Map<String, BitmapLayerFilter> get filters => _filters;

  Size _size;
  Offset _coordinates;
  Bitmap bitmap;

  ui.Image resolvedImage;

  bool _pendingRepaint = true;

  Map<String, BitmapLayerFilter> _filters;

  bool get _hasPendingLayerRecomputation {
    if (_filters == null || _filters.isEmpty) {
      return false;
    }
    return !_filters.values
        .every((BitmapLayerFilter filter) => !filter.shouldRecompute);
  }

  @override
  BitmapLayerSnapshot createSnapshot() {
    return BitmapLayerSnapshot(this);
  }

  @override
  BitmapLayerInstallation install() {
    return BitmapLayerInstallation();
  }

  @override
  void paint(Canvas canvas, Offset offset, NiksState state) {
    if (resolvedImage == null || _hasPendingLayerRecomputation) {
      scheduleImageConversion(state);
    }
    if (resolvedImage == null) {
      return;
    }

    canvas.drawImageRect(
      resolvedImage,
      Rect.fromLTWH(0, 0, bitmap.width.toDouble(), bitmap.height.toDouble()),
      Rect.fromLTWH(coordinates.dx, coordinates.dy, size.width, size.height),
      ui.Paint(),
    );
    _pendingRepaint = false;
  }

  @override
  String get layerIdentity => bitmapIdentity;

  @override
  bool shouldRepaint() => _pendingRepaint || _hasPendingLayerRecomputation;

  void addFilter(String filterKey, BitmapLayerFilter filter) {
    _filters.putIfAbsent(filterKey, () => filter);
  }

  void removeFilter(String filterKey) {
    _filters.remove(filterKey);
  }

  DateTime lastPainted = DateTime.now();

  Future<void> scheduleImageConversion(NiksState state) async {
    _calmFiltersDown();
    final now = DateTime.now();
    final Uint8List converted = await computeBitmap();
    final _resolvedImage = await loadImage(converted);
    if (lastPainted.isAfter(now)) {
      return;
    }
    lastPainted = now;
    resolvedImage = _resolvedImage;
    _pendingRepaint = true;
    state.markNeedsPaint();
  }

  Future<Uint8List> computeBitmap([Bitmap bitmap]) async {
    bitmap = bitmap ?? this.bitmap;
    return await compute(applyFiltersIsolate, [
      bitmap.content,
      bitmap.width,
      bitmap.height,
      bitmap.size,
      _filters.values
          .map<Map<String, dynamic>>(
              (bitmapFilter) => bitmapFilter.createSnapshot().dehydrate())
          .toList()
    ]);
  }

  void _calmFiltersDown() {
    for (BitmapLayerFilter filter in _filters.values) {
      filter.shouldRecompute = false;
    }
  }
}

class BitmapLayerSnapshot implements NiksLayerSnapshot<BitmapLayer> {
  BitmapLayerSnapshot(BitmapLayer layer)
      : uuid = layer.uuid,
        width = layer.size.width,
        height = layer.size.height,
        x = layer.coordinates.dx,
        y = layer.coordinates.dy,
        filters = layer._filters.map<String, BitmapLayerFilterSnapshot>(
            (String filterKey, BitmapLayerFilter filter) {
          return MapEntry<String, BitmapLayerFilterSnapshot>(
              filterKey, filter.createSnapshot());
        });

  BitmapLayerSnapshot.hydrate(Map<String, dynamic> dehydratedLayer)
      : uuid = dehydratedLayer[UUIDKey],
        width = dehydratedLayer[widthKey],
        height = dehydratedLayer[heightKey],
        x = dehydratedLayer[xKey],
        y = dehydratedLayer[yKey],
        filters = (dehydratedLayer[filtersKey])
            .map<String, BitmapLayerFilterSnapshot>(
                (String filterKey, dynamic dehydratedFilter) {
          return MapEntry<String, BitmapLayerFilterSnapshot>(
              filterKey, hydrateFilter(dehydratedFilter));
        });

  @override
  String get layerIdentity => bitmapIdentity;

  @override
  final String uuid;

  final double width;
  final double height;
  final double x;
  final double y;

  final Map<String, BitmapLayerFilterSnapshot> filters;

  @override
  BitmapLayer createLayer(BitmapLayer previousLayer) {
    if (previousLayer == null || previousLayer.bitmap == null) {
      return BitmapLayer.fromSnapshot(this);
    }

    return BitmapLayer.fromSnapshotWithBitmapAndImage(
        previousLayer.bitmap, previousLayer.resolvedImage, this);
  }

  @override
  Map<String, dynamic> dehydrate() {
    final Map<String, dynamic> returnMap = {};

    returnMap[layerIdentityKey] = layerIdentity;
    returnMap[UUIDKey] = uuid;
    returnMap[widthKey] = width;
    returnMap[heightKey] = height;
    returnMap[xKey] = x;
    returnMap[yKey] = y;

    returnMap[filtersKey] = filters.map<String, Map<String, dynamic>>(
        (String filterKey, BitmapLayerFilterSnapshot filterSnapshot) {
      return MapEntry<String, Map<String, dynamic>>(
          filterKey, filterSnapshot.dehydrate());
    });

    return returnMap;
  }
}

class BitmapLayerInstallation
    extends NiksLayerInstallation<BitmapLayer, BitmapLayerSnapshot> {
  @override
  bool checkIdentity(String identity) {
    return identity == this.identity;
  }

  @override
  NiksLayerSnapshot<BitmapLayer> hydrate(Map<String, dynamic> dehydratedLayer) {
    return BitmapLayerSnapshot.hydrate(dehydratedLayer);
  }

  @override
  String get identity => bitmapIdentity;
}

Future<ui.Image> loadImage(Uint8List img) async {
  final Completer<ui.Image> imageCompleter = Completer();
  ui.decodeImageFromList(img, (ui.Image img) {
    imageCompleter.complete(img);
  });
  return imageCompleter.future;
}

/* A method to be run on a isolate that will apply all transformations */
Future<Uint8List> applyFiltersIsolate(List operationData) async {
  final Uint8List byteData = operationData[0];
  final int width = operationData[1];
  final int height = operationData[2];
  final int pixelLength = operationData[3];
  final List<Map<String, dynamic>> filters = operationData[4];
  for (int i = 0; i < filters.length; i++) {
    FilterApplier(filters[i])..apply(byteData, width, height, pixelLength);
  }
  return Bitmap.fromHeadless(width, height, byteData).buildHeaded();
}

class FilterApplier {
  FilterApplier(this.dehydratedFilter);

  Map<String, dynamic> dehydratedFilter;

  void apply(Uint8List bitmap, int width, int height, int pixelLength) {
    hydrateFilter(dehydratedFilter)
        .createFilter()
        .apply(bitmap, width, height, pixelLength);
  }
}
