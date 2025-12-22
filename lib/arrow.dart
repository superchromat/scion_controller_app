import 'dart:math';
import 'package:flutter/material.dart';

class Arrow {
  final Offset from, to;
  Arrow(this.from, this.to);
}

class ArrowsPainter extends CustomPainter {
  final List<Arrow> arrows;
  ArrowsPainter(this.arrows);

  static const baseColor = Color(0xFF909090);
  static const shadowColor = Color(0xFF404040);
  static const highlightColor = Color(0xFFB8B8B8);

  @override
  void paint(Canvas canvas, Size size) {
    for (final a in arrows) {
      // compute arrow‐head
      final angle = (a.to - a.from).direction.sign * pi / 2;
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

      // Shadow (offset down-right)
      final shadowShaftPath = Path()
        ..moveTo(a.from.dx + 2, a.from.dy + 2)
        ..cubicTo(
          c1.dx + 2, c1.dy + 2,
          c2.dx + 2, c2.dy + 2,
          baseCenter.dx + 2, baseCenter.dy + 2,
        );
      final shadowPaint = Paint()
        ..color = shadowColor.withValues(alpha: 0.5)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(shadowShaftPath, shadowPaint);

      // Main shaft
      final shaftPaint = Paint()
        ..color = baseColor
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(shaftPath, shaftPaint);

      // Highlight (thin line on top-left edge)
      final highlightShaftPath = Path()
        ..moveTo(a.from.dx - 1, a.from.dy - 1)
        ..cubicTo(
          c1.dx - 1, c1.dy - 1,
          c2.dx - 1, c2.dy - 1,
          baseCenter.dx - 1, baseCenter.dy - 1,
        );
      final highlightPaint = Paint()
        ..color = highlightColor.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(highlightShaftPath, highlightPaint);

      // Arrow head
      final headPath = Path()
        ..moveTo(a.to.dx, a.to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();

      // Head shadow
      final headShadowPath = Path()
        ..moveTo(a.to.dx + 2, a.to.dy + 2)
        ..lineTo(p1.dx + 2, p1.dy + 2)
        ..lineTo(p2.dx + 2, p2.dy + 2)
        ..close();
      final headShadowPaint = Paint()
        ..color = shadowColor.withValues(alpha: 0.4)
        ..style = PaintingStyle.fill;
      canvas.drawPath(headShadowPath, headShadowPaint);

      // Head fill
      final headFillPaint = Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill;
      canvas.drawPath(headPath, headFillPaint);

      // Head highlight edge
      final headHighlightPaint = Paint()
        ..color = highlightColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a.to, p1, headHighlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ArrowsPainter old) => old.arrows != arrows;
}

