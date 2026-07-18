import 'dart:math';
import 'package:flutter/material.dart';

class Arrow {
  final Offset from, to;
  // When > 0, both bezier control points are lifted this many pixels above
  // the from/to Y coordinates, forcing a symmetric upward arch regardless of
  // the vertical distance between endpoints.
  final double arcUp;
  Arrow(this.from, this.to, {this.arcUp = 0});
}

class ArrowsPainter extends CustomPainter {
  final List<Arrow> arrows;
  ArrowsPainter(this.arrows);

  static const baseColor = Color(0xFF909090);
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
      final Offset c1, c2;
      if (a.arcUp > 0) {
        // Symmetric upward arch: lift both control points equally above endpoints.
        // Bezier peak ≈ 0.75 × arcUp, so multiply by 4/3 to hit the target height.
        final lift = a.arcUp * 4 / 3;
        c1 = Offset(a.from.dx, a.from.dy - lift);
        c2 = Offset(baseCenter.dx, baseCenter.dy - lift);
      } else {
        final dy = baseCenter.dy - a.from.dy;
        final ctrlOffset = dy * 0.5;
        c1 = Offset(a.from.dx, a.from.dy + ctrlOffset);
        c2 = Offset(baseCenter.dx, baseCenter.dy - ctrlOffset);
      }

      final shaftPath = Path()
        ..moveTo(a.from.dx, a.from.dy)
        ..cubicTo(
          c1.dx, c1.dy,
          c2.dx, c2.dy,
          baseCenter.dx, baseCenter.dy,
        );

      final headPath = Path()
        ..moveTo(a.to.dx, a.to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();

      // 1. Soft drop shadow for the whole cable (shaft + head), blurred and
      //    offset down so the wire reads as lifted off the panel.
      canvas.save();
      canvas.translate(1.4, 2.4);
      final shadowStroke = Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
      canvas.drawPath(shaftPath, shadowStroke);
      canvas.drawPath(
        headPath,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.30)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4),
      );
      canvas.restore();

      // 2. Cable core.
      canvas.drawPath(
        shaftPath,
        Paint()
          ..color = baseColor
          ..strokeWidth = 4.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );

      // 3. Top highlight — a thinner, brighter stroke nudged up-left so the
      //    cable reads as a rounded tube catching light.
      canvas.save();
      canvas.translate(-0.6, -1.1);
      canvas.drawPath(
        shaftPath,
        Paint()
          ..color = highlightColor.withValues(alpha: 0.5)
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();

      // 4. Arrow head — filled, with a round-join outline to soften its corners.
      canvas.drawPath(
        headPath,
        Paint()
          ..color = baseColor
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        headPath,
        Paint()
          ..color = baseColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      // Leading-edge highlight on the head.
      canvas.drawLine(
        a.to,
        p1,
        Paint()
          ..color = highlightColor.withValues(alpha: 0.7)
          ..strokeWidth = 1.2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ArrowsPainter old) => old.arrows != arrows;
}

