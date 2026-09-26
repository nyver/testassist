import 'package:flutter/material.dart';

/// Which part of the selection a drag started on.
enum _Handle { topLeft, topRight, bottomLeft, bottomRight, move }

/// An image with a draggable crop rectangle.
///
/// The rectangle is reported as fractions of the image width and height, so it
/// is independent of how the image is scaled on screen. Dragging a corner
/// resizes it, dragging inside moves it.
class CropOverlay extends StatefulWidget {
  const CropOverlay({
    super.key,
    required this.image,
    required this.imageAspectRatio,
    required this.onChanged,
    this.initial = const Rect.fromLTRB(0, 0, 1, 1),
  });

  final ImageProvider image;

  /// Width divided by height of the image.
  final double imageAspectRatio;

  /// Called on every change with the selection as fractions of the image.
  final ValueChanged<Rect> onChanged;
  final Rect initial;

  @override
  State<CropOverlay> createState() => CropOverlayState();
}

class CropOverlayState extends State<CropOverlay> {
  /// The smallest selection, as a fraction of each side.
  static const _minFraction = 0.08;

  /// How close a touch must be to a corner to grab it.
  static const _grabRadius = 36.0;

  late Rect _rect = widget.initial;
  _Handle? _active;

  /// The current selection, as fractions of the image.
  Rect get selection => _rect;

  /// Selects the whole image again.
  void reset() {
    setState(() => _rect = const Rect.fromLTRB(0, 0, 1, 1));
    widget.onChanged(_rect);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: widget.imageAspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _start(d.localPosition, size),
              onPanUpdate: (d) => _update(d.delta, size),
              onPanEnd: (_) => _active = null,
              onPanCancel: () => _active = null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(image: widget.image, fit: BoxFit.fill),
                  CustomPaint(
                    painter: _CropPainter(
                      rect: _rect,
                      scrim: Colors.black54,
                      line: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Rect _pixels(Size size) => Rect.fromLTRB(
    _rect.left * size.width,
    _rect.top * size.height,
    _rect.right * size.width,
    _rect.bottom * size.height,
  );

  void _start(Offset position, Size size) {
    final r = _pixels(size);
    final corners = {
      _Handle.topLeft: r.topLeft,
      _Handle.topRight: r.topRight,
      _Handle.bottomLeft: r.bottomLeft,
      _Handle.bottomRight: r.bottomRight,
    };
    _Handle? nearest;
    var best = _grabRadius;
    corners.forEach((handle, point) {
      final distance = (point - position).distance;
      if (distance <= best) {
        best = distance;
        nearest = handle;
      }
    });
    _active = nearest ?? (r.contains(position) ? _Handle.move : null);
  }

  void _update(Offset delta, Size size) {
    final handle = _active;
    if (handle == null) return;
    final dx = delta.dx / size.width;
    final dy = delta.dy / size.height;
    var r = _rect;

    switch (handle) {
      case _Handle.move:
        final w = r.width;
        final h = r.height;
        final left = (r.left + dx).clamp(0.0, 1.0 - w);
        final top = (r.top + dy).clamp(0.0, 1.0 - h);
        r = Rect.fromLTWH(left, top, w, h);
      case _Handle.topLeft:
        r = Rect.fromLTRB(
          (r.left + dx).clamp(0.0, r.right - _minFraction),
          (r.top + dy).clamp(0.0, r.bottom - _minFraction),
          r.right,
          r.bottom,
        );
      case _Handle.topRight:
        r = Rect.fromLTRB(
          r.left,
          (r.top + dy).clamp(0.0, r.bottom - _minFraction),
          (r.right + dx).clamp(r.left + _minFraction, 1.0),
          r.bottom,
        );
      case _Handle.bottomLeft:
        r = Rect.fromLTRB(
          (r.left + dx).clamp(0.0, r.right - _minFraction),
          r.top,
          r.right,
          (r.bottom + dy).clamp(r.top + _minFraction, 1.0),
        );
      case _Handle.bottomRight:
        r = Rect.fromLTRB(
          r.left,
          r.top,
          (r.right + dx).clamp(r.left + _minFraction, 1.0),
          (r.bottom + dy).clamp(r.top + _minFraction, 1.0),
        );
    }
    setState(() => _rect = r);
    widget.onChanged(r);
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({required this.rect, required this.scrim, required this.line});

  final Rect rect;
  final Color scrim;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = Rect.fromLTRB(
      rect.left * size.width,
      rect.top * size.height,
      rect.right * size.width,
      rect.bottom * size.height,
    );

    // Dim everything outside the selection.
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addRect(selection)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = scrim);

    canvas.drawRect(
      selection,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    final handle = Paint()..color = line;
    for (final corner in [
      selection.topLeft,
      selection.topRight,
      selection.bottomLeft,
      selection.bottomRight,
    ]) {
      canvas.drawCircle(corner, 9, handle);
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.rect != rect || old.scrim != scrim || old.line != line;
}
