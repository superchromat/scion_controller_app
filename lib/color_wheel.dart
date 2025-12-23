import 'dart:math';
import 'package:flutter/material.dart';

/// Convert wheel drag position to RGB values
List<double> wheelPositionToRgb(Offset pos, double size) {
  final center = Offset(size / 2, size / 2);
  final offset = pos - center;
  final radius = size / 2;

  final angle = atan2(offset.dy, offset.dx);
  final dist = (offset.distance / radius).clamp(0.0, 1.0);
  final scaledDist = dist * 2.0;

  final hue = (angle * 180 / pi + 360) % 360;
  final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

  final r = 1.0 + (hueColor.r - 1.0) * scaledDist;
  final g = 1.0 + (hueColor.g - 1.0) * scaledDist;
  final b = 1.0 + (hueColor.b - 1.0) * scaledDist;

  return [r, g, b];
}

class ColorWheelPainter extends CustomPainter {
  final List<double> selected;
  final List<double> otherPrimary1;
  final List<double> otherPrimary2;
  final int wheelIndex;

  ColorWheelPainter(this.selected, this.otherPrimary1, this.otherPrimary2, this.wheelIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final srgbRadius = radius * 0.5;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Sweep gradient for hues
    final hueColors = [
      const Color(0xFFFF0000),
      const Color(0xFFFFFF00),
      const Color(0xFF00FF00),
      const Color(0xFF00FFFF),
      const Color(0xFF0000FF),
      const Color(0xFFFF00FF),
      const Color(0xFFFF0000),
    ];

    final huePaint = Paint()
      ..shader = SweepGradient(colors: hueColors).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, satPaint);

    // Condition number heatmap
    _drawHeatmap(canvas, center, radius, srgbRadius);

    // sRGB boundary (R=1 circle) - white solid
    canvas.drawCircle(
      center,
      srgbRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // sRGB boundary - yellow dashed overlay
    final dashPath = Path()..addOval(Rect.fromCircle(center: center, radius: srgbRadius));
    final dashedPaint = Paint()
      ..color = const Color(0xFFFFD54F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Create dashed effect
    const dashLength = 4.0;
    const gapLength = 4.0;
    final pathMetrics = dashPath.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final nextDistance = distance + dashLength;
        final extractPath = metric.extractPath(distance, nextDistance.clamp(0, metric.length));
        canvas.drawPath(extractPath, dashedPaint);
        distance = nextDistance + gapLength;
      }
    }

    // Selection indicator
    _drawSelectionIndicator(canvas, center, radius);
  }

  void _drawSelectionIndicator(Canvas canvas, Offset center, double radius) {
    final r = selected[0], g = selected[1], b = selected[2];
    final dr = r - 1.0, dg = g - 1.0, db = b - 1.0;
    final distFromWhite = sqrt(dr * dr + dg * dg + db * db);

    Offset selPos;
    if (distFromWhite < 0.001) {
      selPos = center;
    } else {
      final len = distFromWhite;
      final ndr = dr / len, ndg = dg / len, ndb = db / len;

      double bestHue = 0;
      double bestDot = -2;
      for (double h = 0; h < 360; h += 2) {
        final hc = HSVColor.fromAHSV(1, h, 1, 1).toColor();
        final hdr = hc.r - 1.0, hdg = hc.g - 1.0, hdb = hc.b - 1.0;
        final hlen = sqrt(hdr * hdr + hdg * hdg + hdb * hdb);
        if (hlen < 0.001) continue;
        final dot = ndr * (hdr / hlen) + ndg * (hdg / hlen) + ndb * (hdb / hlen);
        if (dot > bestDot) {
          bestDot = dot;
          bestHue = h;
        }
      }

      final angle = bestHue * pi / 180;
      final hueColor = HSVColor.fromAHSV(1, bestHue, 1, 1).toColor();
      final hdr = hueColor.r - 1.0, hdg = hueColor.g - 1.0, hdb = hueColor.b - 1.0;
      final hueDist = sqrt(hdr * hdr + hdg * hdg + hdb * hdb);
      final wheelDist = hueDist > 0.001 ? (distFromWhite / hueDist / 2.0) * radius : 0.0;
      selPos = center + Offset(cos(angle) * wheelDist, sin(angle) * wheelDist);
    }

    final selColor = Color.fromRGBO(
      (r.clamp(0, 1) * 255).round(),
      (g.clamp(0, 1) * 255).round(),
      (b.clamp(0, 1) * 255).round(),
      1,
    );
    canvas.drawCircle(selPos, 8, Paint()..color = selColor);
    canvas.drawCircle(selPos, 8, Paint()..color = Colors.grey[600]!..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  void _drawHeatmap(Canvas canvas, Offset center, double radius, double srgbRadius) {
    // Scale step with radius - smaller wheels need finer steps
    final step = (radius / 75.0) * 2.0; // 2.0 for 150px wheel, ~1.2 for 90px

    for (double x = -radius; x <= radius; x += step) {
      for (double y = -radius; y <= radius; y += step) {
        final dist = sqrt(x * x + y * y);
        if (dist > radius + step) continue;
        final clampedDist = dist.clamp(0.0, radius);

        final angle = atan2(y, x);
        final normalizedRadius = clampedDist / radius;
        final kappa = _conditionNumberAt(angle, normalizedRadius);

        final logKappa = log(kappa.clamp(1, 10000)) / ln10;
        final opacity = ((logKappa - 0.5) / 2.5).clamp(0.0, 0.6);

        if (opacity > 0.01) {
          canvas.drawRect(
            Rect.fromLTWH(center.dx + x - step/2, center.dy + y - step/2, step, step),
            Paint()..color = Colors.black.withValues(alpha: opacity),
          );
        }
      }
    }
  }

  double _conditionNumberAt(double angle, double normalizedRadius) {
    final scaledDist = normalizedRadius * 2.0;
    final hue = (angle * 180 / pi + 360) % 360;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    final r = 1.0 + (hueColor.r - 1.0) * scaledDist;
    final g = 1.0 + (hueColor.g - 1.0) * scaledDist;
    final b = 1.0 + (hueColor.b - 1.0) * scaledDist;

    final testPrimary = [r, g, b];

    List<List<double>> matrix;
    if (wheelIndex == 0) {
      matrix = [
        [testPrimary[0], otherPrimary1[0], otherPrimary2[0]],
        [testPrimary[1], otherPrimary1[1], otherPrimary2[1]],
        [testPrimary[2], otherPrimary1[2], otherPrimary2[2]],
      ];
    } else if (wheelIndex == 1) {
      matrix = [
        [otherPrimary1[0], testPrimary[0], otherPrimary2[0]],
        [otherPrimary1[1], testPrimary[1], otherPrimary2[1]],
        [otherPrimary1[2], testPrimary[2], otherPrimary2[2]],
      ];
    } else {
      matrix = [
        [otherPrimary1[0], otherPrimary2[0], testPrimary[0]],
        [otherPrimary1[1], otherPrimary2[1], testPrimary[1]],
        [otherPrimary1[2], otherPrimary2[2], testPrimary[2]],
      ];
    }

    return _computeConditionNumber(matrix);
  }

  double _computeConditionNumber(List<List<double>> m) {
    double frobM = 0;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        frobM += m[i][j] * m[i][j];
      }
    }
    frobM = sqrt(frobM);

    final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    if (det.abs() < 1e-10) return double.infinity;

    final adj = [
      [m[1][1]*m[2][2] - m[1][2]*m[2][1], m[0][2]*m[2][1] - m[0][1]*m[2][2], m[0][1]*m[1][2] - m[0][2]*m[1][1]],
      [m[1][2]*m[2][0] - m[1][0]*m[2][2], m[0][0]*m[2][2] - m[0][2]*m[2][0], m[0][2]*m[1][0] - m[0][0]*m[1][2]],
      [m[1][0]*m[2][1] - m[1][1]*m[2][0], m[0][1]*m[2][0] - m[0][0]*m[2][1], m[0][0]*m[1][1] - m[0][1]*m[1][0]],
    ];

    double frobAdj = 0;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        frobAdj += adj[i][j] * adj[i][j];
      }
    }
    final frobInv = sqrt(frobAdj) / det.abs();

    return frobM * frobInv;
  }

  @override
  bool shouldRepaint(covariant ColorWheelPainter old) {
    return old.selected != selected ||
        old.otherPrimary1 != otherPrimary1 ||
        old.otherPrimary2 != otherPrimary2;
  }
}
