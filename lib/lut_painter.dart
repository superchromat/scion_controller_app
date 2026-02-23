import 'dart:math';
import 'package:flutter/material.dart';
import 'monotonic_spline.dart';

Color getChannelColor(String channel) {
  switch (channel) {
    case 'R':
      return Colors.red;
    case 'G':
      return Colors.green;
    case 'B':
      return Colors.blue;
    default:
      return Colors.white;
  }
}

enum GradeHandle {
  shadowCenter,
  shadowBlendLeft,
  shadowBlendRight,
  midCenter,
  midBlendLeft,
  midBlendRight,
}

class LUTPainter extends CustomPainter {
  final Map<String, List<Offset>> controlPoints;
  final Map<String, MonotonicSpline?> splines;
  final String selectedChannel;
  final int? highlightedIndex;
  final double insetPadding;
  final List<GradeBand> gradeBands;
  final GradeHandle? activeHandle;

  LUTPainter({
    required this.controlPoints,
    required this.splines,
    required this.selectedChannel,
    required this.highlightedIndex,
    required this.insetPadding,
    required this.gradeBands,
    required this.activeHandle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintGridMinor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.25;

    final paintGridMajor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.5;

    final paintOther = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintSelected = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final paintPoint = Paint()
      ..color = const Color(0xFF3678F4)
      ..style = PaintingStyle.fill;

    final paintSelectedPoint = Paint()
      ..color = const Color(0xFF3BDEFF)
      ..style = PaintingStyle.fill;

    final w = size.width - 2 * insetPadding;
    final h = size.height - 2 * insetPadding;

    canvas.translate(insetPadding, insetPadding);

    // Draw grid
    for (double i = 0; i <= 1; i += 0.05) {
      canvas.drawLine(Offset(i * w, 0), Offset(i * w, h), paintGridMinor);
      canvas.drawLine(Offset(0, i * h), Offset(w, i * h), paintGridMinor);
    }
    for (double i = 0; i <= 1; i += 0.2) {
      canvas.drawLine(Offset(i * w, 0), Offset(i * w, h), paintGridMajor);
      canvas.drawLine(Offset(0, i * h), Offset(w, i * h), paintGridMajor);
    }

    // Draw all unselected curves first
    for (var c in ['B', 'G', 'R', 'Y']) {
      if (c == selectedChannel) continue; // skip selected
      final spline = splines[c];
      if (spline == null) continue;

      final path = Path();
      for (int i = 0; i <= 100; i++) {
        final t = i / 100;
        final x = t;
        final y = spline.evaluate(x).clamp(0.0, 1.0);
        final pos = Offset(x * w, (1.0 - y) * h);

        if (i == 0) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      paintOther.color = getChannelColor(c).withOpacity(0.5);
      canvas.drawPath(path, paintOther);
    }

    // Draw selected curve last (thick and bright)
    final selectedSpline = splines[selectedChannel];
    if (selectedSpline != null) {
      final path = Path();
      for (int i = 0; i <= 100; i++) {
        final t = i / 100;
        final x = t;
        final y = selectedSpline.evaluate(x).clamp(0.0, 1.0);
        final pos = Offset(x * w, (1.0 - y) * h);

        if (i == 0) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      paintSelected.color = getChannelColor(selectedChannel);
      canvas.drawPath(path, paintSelected);
    }

    // Draw control points
    final points = controlPoints[selectedChannel]!;
    for (int i = 0; i < points.length; i++) {
      final pos = Offset(points[i].dx * w, (1 - points[i].dy) * h);
      final selected = (i == highlightedIndex);

      canvas.drawCircle(pos, 5, selected ? paintSelectedPoint : paintPoint);
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    // Draw grade bands overlay (vertical lines + handles) behind curves
    canvas.save();
    // push lines slightly behind curves
    canvas.translate(0, 0);
    final linePaint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final dashPaint = Paint()
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
      final handlePaint = Paint()..style = PaintingStyle.fill;

    for (int idx = 0; idx < gradeBands.length; idx++) {
      final band = gradeBands[idx];
      final centerX = band.center.clamp(0.0, 1.0) * w;
      final offset = band.blend.clamp(0.0, 1.0) * w;
      final leftX = (band.center - band.blend).clamp(0.0, 1.0) * w;
      final rightX = (band.center + band.blend).clamp(0.0, 1.0) * w;
      final color = band.color.withOpacity(0.8);

      // Center line
      linePaint.color = color;
      canvas.drawLine(Offset(centerX, 0), Offset(centerX, h), linePaint);

      // Dashed lines
      dashPaint.color = color.withOpacity(0.65);
      _drawDashedLine(canvas, Offset(leftX, 0), Offset(leftX, h), dashPaint);
      _drawDashedLine(canvas, Offset(rightX, 0), Offset(rightX, h), dashPaint);

      // Handles (uniform size) below plot; draw downward so they don't intrude
      handlePaint.color = color;
      _drawFlagHandle(
        canvas,
        Offset(centerX, h + 12), // top of stem below plot
        9,
        10,
        handlePaint,
        active: activeHandle ==
            (idx == 0 ? GradeHandle.shadowCenter : GradeHandle.midCenter),
      );
      _drawFlagHandle(
        canvas,
        Offset(leftX, h + 12),
        9,
        10,
        handlePaint,
        active: activeHandle ==
            (idx == 0
                ? GradeHandle.shadowBlendLeft
                : GradeHandle.midBlendLeft),
      );
      _drawFlagHandle(
        canvas,
        Offset(rightX, h + 12),
        9,
        10,
        handlePaint,
        active: activeHandle ==
            (idx == 0
                ? GradeHandle.shadowBlendRight
                : GradeHandle.midBlendRight),
      );
    }
    canvas.restore();

  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class GradeBand {
  final double center;
  final double blend;
  final Color color;

  GradeBand({
    required this.center,
    required this.blend,
    required this.color,
  });
}

void _drawFlagHandle(Canvas canvas, Offset baseTop, double triHeight,
    double stemHeight, Paint paint,
    {bool active = false}) {
  // baseTop is the tip of the triangle (top). Triangle points up, square sits below it.
  final width = triHeight * 0.9;
  final triBaseY = baseTop.dy + triHeight;
  final rect = Rect.fromLTWH(
    baseTop.dx - width / 2,
    triBaseY,
    width,
    stemHeight,
  );
  final path = Path()
    ..moveTo(baseTop.dx, baseTop.dy)
    ..lineTo(baseTop.dx - width / 2, triBaseY)
    ..lineTo(baseTop.dx + width / 2, triBaseY)
    ..close();

  final fill = active ? paint.color.withOpacity(1.0) : paint.color;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = Colors.black.withOpacity(0.35);

  canvas.drawRect(rect, paint..color = fill);
  canvas.drawPath(path, paint..color = fill);
  canvas.drawRect(rect, stroke);
  canvas.drawPath(path, stroke);
}

void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
  const dash = 6.0;
  const gap = 4.0;
  final startY = min(a.dy, b.dy);
  final endY = max(a.dy, b.dy);
  double y = startY;
  while (y < endY) {
    final next = (y + dash).clamp(startY, endY);
    canvas.drawLine(Offset(a.dx, y), Offset(a.dx, next), paint);
    y += dash + gap;
  }
}
