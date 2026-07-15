import 'dart:math';
import 'package:flutter/material.dart';
import 'monotonic_spline.dart';

// Posterize column geometry, as fractions of the plot's inner width. The curve
// is drawn in [kPosterPlotFrac] of the width when the column is shown; the
// editor's hit-testing must use the same fraction so clicks land on points.
const double kPosterColFrac = 0.07;
const double kPosterGapFrac = 0.03;
const double kPosterPlotFrac = 1.0 - kPosterColFrac - kPosterGapFrac;

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

  // Posterize column: when [posterMode] is on, the plot narrows and a strip on
  // the right shows the posterize regions divided by the control points' output
  // (Y) values. [posterThresholds] are the interior divider levels (0..1, any
  // order); [posterColors]/[posterTypes] are per band, bottom→top.
  final bool posterMode;
  final List<double> posterThresholds;
  final List<int> posterColors;
  final List<int> posterTypes;
  final int? posterSelected;

  LUTPainter({
    required this.controlPoints,
    required this.splines,
    required this.selectedChannel,
    required this.highlightedIndex,
    required this.insetPadding,
    required this.gradeBands,
    required this.activeHandle,
    this.posterMode = false,
    this.posterThresholds = const [],
    this.posterColors = const [],
    this.posterTypes = const [],
    this.posterSelected,
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

    final fullW = size.width - 2 * insetPadding;
    final h = size.height - 2 * insetPadding;
    // `w` is the plot width — narrowed to make room for the posterize column so
    // all existing plot drawing below just uses the reduced width.
    final w = posterMode ? fullW * kPosterPlotFrac : fullW;

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

    // Grade bands overlay (behind curves)
    if (gradeBands.isNotEmpty) {
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
        final leftX = (band.center - band.blend).clamp(0.0, 1.0) * w;
        final rightX = (band.center + band.blend).clamp(0.0, 1.0) * w;
        final isShadowBand = idx == 0;
        final bandActive = activeHandle != null &&
            ((isShadowBand &&
                    (activeHandle == GradeHandle.shadowCenter ||
                        activeHandle == GradeHandle.shadowBlendLeft ||
                        activeHandle == GradeHandle.shadowBlendRight)) ||
                (!isShadowBand &&
                    (activeHandle == GradeHandle.midCenter ||
                        activeHandle == GradeHandle.midBlendLeft ||
                        activeHandle == GradeHandle.midBlendRight)));
        final opacity = bandActive ? 0.95 : 0.5;
        final color = band.color.withOpacity(opacity);

        // Center line
        linePaint
          ..strokeCap = StrokeCap.round
          ..color = color;
        canvas.drawLine(Offset(centerX, 0), Offset(centerX, h), linePaint);

        // Dotted side lines. If they fall outside 0..1, skip drawing.
        dashPaint
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.fill
          ..color = color;
        final showLeft = band.center - band.blend >= 0.0;
        final showRight = band.center + band.blend <= 1.0;

        if (showLeft) {
          _drawDottedLine(canvas, Offset(leftX, 0), Offset(leftX, h), dashPaint);
        }
        if (showRight) {
          _drawDottedLine(canvas, Offset(rightX, 0), Offset(rightX, h), dashPaint);
        }

        // Handles (below plot)
        handlePaint.color = color;
        _drawFlagHandle(
          canvas,
          Offset(centerX, h), // tip sits on plot bottom line
          9,
          10,
          handlePaint,
          level: band.center,
          active: activeHandle ==
              (idx == 0 ? GradeHandle.shadowCenter : GradeHandle.midCenter),
        );
        if (showLeft) {
          _drawFlagHandle(
            canvas,
            Offset(leftX, h),
            9,
            10,
            handlePaint,
            level: band.center,
            active: activeHandle ==
                (idx == 0
                    ? GradeHandle.shadowBlendLeft
                    : GradeHandle.midBlendLeft),
          );
        }
        if (showRight) {
          _drawFlagHandle(
            canvas,
            Offset(rightX, h),
            9,
            10,
            handlePaint,
            level: band.center,
            active: activeHandle ==
                (idx == 0
                    ? GradeHandle.shadowBlendRight
                    : GradeHandle.midBlendRight),
          );
        }
      }
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

    // ── posterize column ────────────────────────────────────────────────────
    if (posterMode) {
      final colX = w + fullW * kPosterGapFrac;
      final colW = fullW * kPosterColFrac;
      final divs = [...posterThresholds]..sort();
      final bounds = <double>[0.0, ...divs, 1.0];
      final nBands = bounds.length - 1;

      // Fill each region (band), bottom → top.
      for (int b = 0; b < nBands; b++) {
        final top = (1 - bounds[b + 1]) * h, bot = (1 - bounds[b]) * h;
        final rect = Rect.fromLTRB(colX, top, colX + colW, bot);
        final col = (b < posterColors.length) ? posterColors[b] : 0xFFFFFF;
        final type = (b < posterTypes.length) ? posterTypes[b] : 7;
        if (type == 0) {
          // "original" — dark checker so it reads as pass-through
          canvas.drawRect(rect, Paint()..color = const Color(0xFF202024));
          final ck = Paint()..color = const Color(0xFF34343A);
          const cs = 6.0;
          for (double y = top; y < bot; y += cs) {
            for (double x = colX; x < colX + colW; x += cs) {
              if (((x ~/ cs) + (y ~/ cs)).isOdd) {
                canvas.drawRect(
                    Rect.fromLTWH(x, y, cs, (y + cs).clamp(top, bot) - y), ck);
              }
            }
          }
        } else {
          canvas.drawRect(rect, Paint()..color = Color(0xFF000000 | col));
          if (type >= 1 && type <= 4) {
            // zebra hint — diagonal ticks
            canvas.save();
            canvas.clipRect(rect);
            final zp = Paint()..color = Colors.black.withOpacity(0.4)..strokeWidth = 3;
            for (double x = colX - h; x < colX + colW + h; x += 9) {
              canvas.drawLine(Offset(x, bot), Offset(x + (bot - top), top), zp);
            }
            canvas.restore();
          }
        }
        if (posterSelected == b) {
          canvas.drawRect(
              rect.deflate(1),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.white);
        }
      }

      // Column outline.
      canvas.drawRect(
          Rect.fromLTWH(colX, 0, colW, h),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x55FFFFFF));

      // Solid divider lines across the column + dotted connectors from each
      // interior control point to its divider.
      final solid = Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 1.2;
      final dot = Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.fill;
      for (final y in divs) {
        final ly = (1 - y) * h;
        canvas.drawLine(Offset(colX, ly), Offset(colX + colW, ly), solid);
      }
      for (final p in controlPoints[selectedChannel]!) {
        if (p.dx < 0 || p.dy <= 0 || p.dy >= 1) continue; // placeholders + ends
        final ly = (1 - p.dy) * h;
        _drawDottedHLine(canvas, p.dx * w, colX, ly, dot);
      }
    }
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

void _drawFlagHandle(Canvas canvas, Offset tip, double triHeight,
    double stemHeight, Paint paint,
    {bool active = false, double level = 0.5}) {
  // Closed 5-sided polygon (triangle on top, square below), all rounded.
  final width = triHeight * 1.0;
  final triBaseY = tip.dy + triHeight;
  final squareHeight = stemHeight;
  final overlap = 2.0; // bring square into triangle a bit
  final squareTop = triBaseY - overlap;
  final squareBot = squareTop + squareHeight;
  final leftX = tip.dx - width / 2;
  final rightX = tip.dx + width / 2;

  final path = Path()
    ..moveTo(tip.dx, tip.dy)
    ..lineTo(leftX, triBaseY)
    ..lineTo(leftX, squareBot)
    ..lineTo(rightX, squareBot)
    ..lineTo(rightX, triBaseY)
    ..close();

  final fill = active ? paint.color.withOpacity(1.0) : paint.color;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round
    ..color = fill.withOpacity(0.2);

  // Outer rounded shape (square portion) with small radius
  // Inner square shaded by level (0=dark,1=light)
  final luma = level.clamp(0.0, 1.0);
  final innerColor =
      Color.lerp(const Color(0xFF000000), const Color(0xFFFFFFFF), luma)!;
  final innerSize = min(width * 0.72, squareHeight * 0.9);
  final innerRect = RRect.fromRectAndRadius(
    Rect.fromLTWH(
      tip.dx - innerSize / 2,
      squareTop + (squareHeight - innerSize) * 0.7,
      innerSize,
      innerSize,
    ),
    const Radius.circular(0.3),
  );

  // Single closed path draw to avoid gaps
  final fillPaint = Paint()
    ..color = fill
    ..style = PaintingStyle.fill;
  canvas.drawPath(path, fillPaint);
  canvas.drawRRect(innerRect, Paint()..color = innerColor);
  canvas.drawPath(path, stroke);
}

void _drawDottedHLine(Canvas canvas, double x0, double x1, double y, Paint paint) {
  const double dotW = 1.4, dotH = 0.9, gap = 3.0;
  final lo = min(x0, x1), hi = max(x0, x1);
  for (double x = lo; x <= hi; x += dotW + gap) {
    canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: dotW, height: dotH), paint);
  }
}

void _drawDottedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
  const double dotH = 1.4;
  const double dotW = 0.9;
  const double gap = 3.0;
  final startY = min(a.dy, b.dy);
  final endY = max(a.dy, b.dy);
  double y = startY;
  while (y <= endY) {
    final rect = Rect.fromCenter(
      center: Offset(a.dx, y),
      width: dotW,
      height: dotH,
    );
    canvas.drawRect(rect, paint);
    y += dotH + gap;
  }
}
