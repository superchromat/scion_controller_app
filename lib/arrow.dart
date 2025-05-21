import 'dart:math';
import 'package:flutter/material.dart';

class Arrow {
  final Offset from, to;
  Arrow(this.from, this.to);
}

class ArrowsPainter extends CustomPainter {
  final List<Arrow> arrows;
  ArrowsPainter(this.arrows);

  Color? col = Colors.grey[400];

  @override
  void paint(Canvas canvas, Size size) {
    final shaftPaint = Paint()
      ..color = col!
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    final headFillPaint = Paint()
      ..color = col!
      ..style = PaintingStyle.fill;
    final headStrokePaint = Paint()
      ..color = col!
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final a in arrows) {
      // compute arrow‐head
      final angle = (a.to - a.from).direction.sign * pi/2 ;
      const headLen = 12.0, headAngle = pi / 6;
      final p1 = a.to -
          Offset(
            headLen * cos(angle - headAngle),
            headLen * sin(angle - headAngle),
          );
      final p2 = a.to -
          Offset(
            headLen * cos(angle + headAngle),
            headLen * sin(angle + headAngle),
          );
      final baseCenter = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);

      // draw spline shaft with vertical start/end tangents
      final dy = baseCenter.dy - a.from.dy;
      final ctrlOffset = dy * 0.5;
      final c1 = Offset(a.from.dx, a.from.dy + ctrlOffset);
      final c2 = Offset(baseCenter.dx, baseCenter.dy - ctrlOffset);

      final shaftPath = Path()
        ..moveTo(a.from.dx, a.from.dy)
        ..cubicTo(
          c1.dx, c1.dy,
          c2.dx, c2.dy,
          baseCenter.dx, baseCenter.dy,
        );
      canvas.drawPath(shaftPath, shaftPaint);

      // draw arrow‐head
      final headPath = Path()
        ..moveTo(a.to.dx, a.to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(headPath, headFillPaint);
      canvas.drawPath(headPath, headStrokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant ArrowsPainter old) => old.arrows != arrows;
}

