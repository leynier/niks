import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../niks.dart';

class NiksRenderWidget extends LeafRenderObjectWidget {
  NiksRenderWidget(this.skin);

  final Niks skin;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderConstrainedBox(
      child: NiksRenderBox(skin),
      additionalConstraints: BoxConstraints.tight(skin.options.size),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConstrainedBox renderObject,
  ) {
    renderObject
      ..child = NiksRenderBox(skin)
      ..additionalConstraints = BoxConstraints.tight(skin.options.size);
  }
}

class NiksRenderBox extends RenderBox {
  NiksRenderBox(this.skin);

  Niks skin;

  @override
  bool get sizedByParent => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _bindNiksListener();
  }

  @override
  void detach() {
    _unbindNiksListener();
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    skin.state.paint(canvas, offset);
    canvas.restore();
  }

  void _bindNiksListener() {
    skin.state.addListener(markNeedsPaint);
  }

  void _unbindNiksListener() {
    skin.state.removeListener(markNeedsPaint);
  }
}
