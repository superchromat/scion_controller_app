import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'video_format_selection.dart' show computeRequiredAdcBias;

// Cached wheel image
ui.Image? _cachedWheelImage;
int _cachedWheelSize = 0;
double _cachedWheelSlider = 0.0;

/// Call this to invalidate the wheel cache (e.g., on hot reload)
void invalidateWheelCache() {
  _cachedWheelImage = null;
  _cachedWheelSize = 0;
}

// Orthonormal basis for the plane perpendicular to (1,1,1)
// u = (1, -1, 0) / sqrt(2)  -- red-cyan axis (positive = more red, less green)
// v = (1, 1, -2) / sqrt(6)  -- yellow-blue axis (positive = more yellow, less blue)
const double _sqrt2 = 1.4142135623730951;
const double _sqrt3 = 1.7320508075688772;
const double _sqrt6 = 2.449489742783178;

// u basis vector components
const double _ux = 1.0 / _sqrt2;
const double _uy = -1.0 / _sqrt2;
const double _uz = 0.0;

// v basis vector components
const double _vx = 1.0 / _sqrt6;
const double _vy = 1.0 / _sqrt6;
const double _vz = -2.0 / _sqrt6;

// w basis vector (along gray axis) components
const double _wx = 1.0 / _sqrt3;
const double _wy = 1.0 / _sqrt3;
const double _wz = 1.0 / _sqrt3;

/// Convert RGB to wheel coordinates (a, b) and slider value s
/// RGB = (1,1,1) + a*u + b*v + s*w
List<double> rgbToWheelCoords(List<double> rgb) {
  final dr = rgb[0] - 1.0;
  final dg = rgb[1] - 1.0;
  final db = rgb[2] - 1.0;

  // Project onto each basis vector
  final a = dr * _ux + dg * _uy + db * _uz;
  final b = dr * _vx + dg * _vy + db * _vz;
  final s = dr * _wx + dg * _wy + db * _wz;

  return [a, b, s];
}

/// Convert wheel coordinates (a, b) and slider value s to RGB
/// RGB = (1,1,1) + a*u + b*v + s*w
List<double> wheelCoordsToRgb(double a, double b, double s) {
  final r = 1.0 + a * _ux + b * _vx + s * _wx;
  final g = 1.0 + a * _uy + b * _vy + s * _wy;
  final bl = 1.0 + a * _uz + b * _vz + s * _wz;
  return [r, g, bl];
}

/// Convert wheel drag position to RGB values
/// The wheel represents the chromaticity plane (perpendicular to gray axis)
/// The slider value controls position along the gray axis
List<double> wheelPositionToRgb(Offset pos, double size, double sliderValue) {
  final center = Offset(size / 2, size / 2);
  var offset = pos - center;
  final radius = size / 2;

  // Clamp to wheel boundary
  final dist = offset.distance;
  if (dist > radius) {
    offset = offset * (radius / dist);
  }

  // Scale factor: at wheel edge, we want a reasonable range
  // Let's say wheel edge = magnitude 2.0 in the (a,b) plane
  const double wheelScale = 2.0;

  final a = (offset.dx / radius) * wheelScale;
  final b = (-offset.dy / radius) * wheelScale;  // Flip Y so up = positive

  return wheelCoordsToRgb(a, b, sliderValue);
}

/// Generate opponent color wheel
/// Center = gray (exact shade depends on slider)
/// Moving right = more red, less green (positive a)
/// Moving up = more yellow, less blue (positive b)
ui.Image _generateOpponentWheel(int size, double sliderValue) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = size / 2.0;
  final radius = center - 0.5;

  const double wheelScale = 2.0;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - center + 0.5;
      final dy = y - center + 0.5;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist <= radius + 1.0) {
        // Convert screen position to (a, b) coordinates
        final a = (dx / radius) * wheelScale;
        final b = (-dy / radius) * wheelScale;  // Flip Y

        // Get RGB from wheel coords
        final rgb = wheelCoordsToRgb(a, b, sliderValue);

        // Clamp for display
        final r = rgb[0].clamp(0.0, 1.0);
        final g = rgb[1].clamp(0.0, 1.0);
        final bl = rgb[2].clamp(0.0, 1.0);

        // Anti-aliasing at edge
        final alpha = (radius + 1.0 - dist).clamp(0.0, 1.0);

        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromRGBO(
            (r * 255).round().clamp(0, 255),
            (g * 255).round().clamp(0, 255),
            (bl * 255).round().clamp(0, 255),
            alpha,
          ),
        );
      }
    }
  }

  return recorder.endRecording().toImageSync(size, size);
}

/// Initialize the color wheel (no-op, kept for API compatibility)
Future<void> loadWheelAsset() async {
  // Wheel is generated on-demand, no assets needed
}

class ColorWheelPainter extends CustomPainter {
  final List<double> selected;
  final List<double> otherPrimary1;
  final List<double> otherPrimary2;
  final int wheelIndex;
  final double sliderValue;
  final bool isCompact;  // For smaller wheels: thinner lines, coarser sampling

  ColorWheelPainter(
    this.selected,
    this.otherPrimary1,
    this.otherPrimary2,
    this.wheelIndex, {
    this.sliderValue = 0.0,
    this.isCompact = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw color wheel
    _drawCachedWheel(canvas, center, radius);

    // Always show danger zone
    _drawDangerZone(canvas, center, radius);

    // sRGB gamut boundary
    _drawGamutBoundary(canvas, center, radius);

    // Selection indicator
    _drawSelectionIndicator(canvas, center, radius);
  }

  void _drawSelectionIndicator(Canvas canvas, Offset center, double radius) {
    final r = selected[0], g = selected[1], b = selected[2];

    // Convert RGB to wheel coordinates
    final coords = rgbToWheelCoords(selected);
    final a = coords[0];
    final bCoord = coords[1];
    // Note: coords[2] is the slider component, which we ignore for positioning

    // Convert (a, b) to screen position
    const double wheelScale = 2.0;
    final screenX = (a / wheelScale) * radius;
    final screenY = (-bCoord / wheelScale) * radius;  // Flip Y back

    final selPos = center + Offset(screenX, screenY);

    // Use the actual selected color for the indicator (clamped for display)
    final selColor = Color.fromRGBO(
      (r.clamp(0, 1) * 255).round(),
      (g.clamp(0, 1) * 255).round(),
      (b.clamp(0, 1) * 255).round(),
      1,
    );

    canvas.drawCircle(selPos, 8, Paint()..color = selColor);
    canvas.drawCircle(selPos, 8, Paint()..color = Colors.grey[600]!..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  void _drawCachedWheel(Canvas canvas, Offset center, double radius) {
    final size = (radius * 2).round();

    // Check if we have a valid cached image with matching slider value
    if (_cachedWheelImage != null &&
        _cachedWheelSize == size &&
        (_cachedWheelSlider - sliderValue).abs() < 0.01) {
      final src = Rect.fromLTWH(0, 0, _cachedWheelImage!.width.toDouble(), _cachedWheelImage!.height.toDouble());
      final dst = Rect.fromCircle(center: center, radius: radius);
      canvas.drawImageRect(_cachedWheelImage!, src, dst, Paint()..filterQuality = FilterQuality.high);
      return;
    }

    // Generate new wheel
    _cachedWheelImage = _generateOpponentWheel(size, sliderValue);
    _cachedWheelSize = size;
    _cachedWheelSlider = sliderValue;

    if (_cachedWheelImage != null) {
      final src = Rect.fromLTWH(0, 0, _cachedWheelImage!.width.toDouble(), _cachedWheelImage!.height.toDouble());
      final dst = Rect.fromCircle(center: center, radius: radius);
      canvas.drawImageRect(_cachedWheelImage!, src, dst, Paint()..filterQuality = FilterQuality.high);
    }
  }

  void _drawGamutBoundary(Canvas canvas, Offset center, double radius) {
    // Draw approximate sRGB gamut boundary
    // This is the region where all RGB values are in [0, 1]
    // For a given slider value, this forms a hexagonal region

    const double wheelScale = 2.0;
    final path = Path();

    // Sample points around the wheel and find where gamut clips
    bool firstPoint = true;
    for (double angle = 0; angle < 2 * pi; angle += 0.05) {
      // Binary search for gamut boundary at this angle
      double lo = 0, hi = 1.0;
      for (int i = 0; i < 10; i++) {
        final mid = (lo + hi) / 2;
        final a = cos(angle) * mid * wheelScale;
        final b = sin(angle) * mid * wheelScale;
        final rgb = wheelCoordsToRgb(a, b, sliderValue);
        final inGamut = rgb[0] >= 0 && rgb[0] <= 1 &&
                        rgb[1] >= 0 && rgb[1] <= 1 &&
                        rgb[2] >= 0 && rgb[2] <= 1;
        if (inGamut) {
          lo = mid;
        } else {
          hi = mid;
        }
      }

      final boundaryDist = lo;
      final screenX = cos(angle) * boundaryDist * radius;
      final screenY = -sin(angle) * boundaryDist * radius;

      if (firstPoint) {
        path.moveTo(center.dx + screenX, center.dy + screenY);
        firstPoint = false;
      } else {
        path.lineTo(center.dx + screenX, center.dy + screenY);
      }
    }
    path.close();

    // Draw the boundary
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFD54F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  /// Create polynomial evaluator for condition number.
  _KappaPolynomial _computeKappaPolynomial() {
    return _KappaPolynomial(
      fixed1: otherPrimary1,
      fixed2: otherPrimary2,
      wheelIndex: wheelIndex,
      sliderValue: sliderValue,
    );
  }

  /// Compute ADC bias for a given wheel position (a, b).
  /// Returns the max required ADC bias for the matrix formed by placing
  /// the wheel position's RGB in the appropriate column.
  double _computeBiasAtPosition(double a, double b) {
    final rgb = wheelCoordsToRgb(a, b, sliderValue);

    // Build matrix with this primary in the correct column
    List<List<double>> matrix;
    switch (wheelIndex) {
      case 0:
        matrix = [
          [rgb[0], otherPrimary1[0], otherPrimary2[0]],
          [rgb[1], otherPrimary1[1], otherPrimary2[1]],
          [rgb[2], otherPrimary1[2], otherPrimary2[2]],
        ];
        break;
      case 1:
        matrix = [
          [otherPrimary1[0], rgb[0], otherPrimary2[0]],
          [otherPrimary1[1], rgb[1], otherPrimary2[1]],
          [otherPrimary1[2], rgb[2], otherPrimary2[2]],
        ];
        break;
      default: // case 2
        matrix = [
          [otherPrimary1[0], otherPrimary2[0], rgb[0]],
          [otherPrimary1[1], otherPrimary2[1], rgb[1]],
          [otherPrimary1[2], otherPrimary2[2], rgb[2]],
        ];
    }

    return computeRequiredAdcBias(matrix);
  }

  void _drawDangerZone(Canvas canvas, Offset center, double radius) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    const double kappaThreshold = 15.0;
    const double kappaThresholdSq = kappaThreshold * kappaThreshold;
    const double biasThreshold = 1.5;
    const double wheelScale = 2.0;

    final poly = _computeKappaPolynomial();

    // Build grid of continuous danger values for smooth interpolation
    // dangerValue > 1.0 means dangerous; we use max(kappa/threshold, bias/biasThreshold)
    final double step = isCompact ? 2.0 : 1.5;
    final int n = (radius * 2 / step).ceil() + 2;
    final dangerValues = List.generate(n, (_) => List.filled(n, 0.0));

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        final x = -radius - step + i * step;
        final y = -radius - step + j * step;
        final a = (x / radius) * wheelScale;
        final b = (-y / radius) * wheelScale;

        // Compute normalized danger scores (>1 means dangerous)
        final kappaSq = poly.evaluateKappaSq(a, b);
        final kappaScore = sqrt(kappaSq) / kappaThreshold;

        // Only compute bias if kappa isn't already very high (optimization)
        double biasScore = 0.0;
        if (kappaScore < 2.0) {
          biasScore = _computeBiasAtPosition(a, b) / biasThreshold;
        }

        // Use max for combined danger (either condition triggers danger zone)
        dangerValues[i][j] = max(kappaScore, biasScore);
      }
    }

    // Build fill path using the danger grid
    final fillPath = Path();
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        if (dangerValues[i][j] >= 1.0) {
          final x = -radius - step + i * step;
          final y = -radius - step + j * step;
          if (x * x + y * y <= radius * radius * 1.1) {
            fillPath.addRect(Rect.fromCenter(
              center: Offset(center.dx + x, center.dy + y),
              width: step + 0.5,
              height: step + 0.5,
            ));
          }
        }
      }
    }

    // Draw white background with slight blur effect
    canvas.drawPath(fillPath, Paint()..color = Colors.white.withValues(alpha: 0.7));

    // Hatch pattern
    canvas.save();
    canvas.clipPath(fillPath);
    final hatchPaint = Paint()
      ..color = const Color(0xFFE53935).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (double offset = -radius * 2; offset < radius * 2; offset += 6.0) {
      canvas.drawLine(
        Offset(center.dx + offset - radius, center.dy + radius),
        Offset(center.dx + offset + radius, center.dy - radius),
        hatchPaint,
      );
    }
    canvas.restore();

    // Draw smooth boundary using marching squares with linear interpolation
    const double threshold = 1.0;
    final boundaryPath = Path();

    for (int i = 0; i < n - 1; i++) {
      for (int j = 0; j < n - 1; j++) {
        final v00 = dangerValues[i][j];
        final v10 = dangerValues[i + 1][j];
        final v01 = dangerValues[i][j + 1];
        final v11 = dangerValues[i + 1][j + 1];

        final x0 = center.dx - radius - step + i * step;
        final y0 = center.dy - radius - step + j * step;

        final b00 = v00 >= threshold ? 1 : 0;
        final b10 = v10 >= threshold ? 2 : 0;
        final b01 = v01 >= threshold ? 4 : 0;
        final b11 = v11 >= threshold ? 8 : 0;
        final caseIndex = b00 | b10 | b01 | b11;

        if (caseIndex == 0 || caseIndex == 15) continue;

        // Linear interpolation for smooth boundary
        double lerp(double va, double vb) {
          if ((vb - va).abs() < 1e-10) return 0.5;
          return (threshold - va) / (vb - va);
        }

        final bottom = Offset(x0 + lerp(v00, v10) * step, y0);
        final top = Offset(x0 + lerp(v01, v11) * step, y0 + step);
        final left = Offset(x0, y0 + lerp(v00, v01) * step);
        final right = Offset(x0 + step, y0 + lerp(v10, v11) * step);

        void addSeg(Offset a, Offset b) {
          boundaryPath.moveTo(a.dx, a.dy);
          boundaryPath.lineTo(b.dx, b.dy);
        }

        switch (caseIndex) {
          case 1: addSeg(bottom, left); break;
          case 2: addSeg(bottom, right); break;
          case 3: addSeg(left, right); break;
          case 4: addSeg(left, top); break;
          case 5: addSeg(bottom, top); break;
          case 6: addSeg(bottom, left); addSeg(top, right); break;
          case 7: addSeg(top, right); break;
          case 8: addSeg(top, right); break;
          case 9: addSeg(bottom, right); addSeg(left, top); break;
          case 10: addSeg(bottom, top); break;
          case 11: addSeg(left, top); break;
          case 12: addSeg(left, right); break;
          case 13: addSeg(bottom, right); break;
          case 14: addSeg(bottom, left); break;
        }
      }
    }

    // Draw boundary with rounded joins for smoother appearance
    canvas.drawPath(
      boundaryPath,
      Paint()
        ..color = const Color(0xFFD32F2F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isCompact ? 1.5 : 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ColorWheelPainter old) {
    return old.selected != selected ||
        old.otherPrimary1 != otherPrimary1 ||
        old.otherPrimary2 != otherPrimary2 ||
        old.sliderValue != sliderValue ||
        old.isCompact != isCompact;
  }
}

/// Efficient computation of κ² for the color matrix.
///
/// The matrix M = [p0, p1, p2] where one column (wheelIndex) is the moving primary
/// computed from wheel coordinates, and the other two are fixed.
///
/// κ² = ||M||_F² × ||adj(M)||_F² / det(M)²
class _KappaPolynomial {
  final List<double> fixed1;  // First fixed primary
  final List<double> fixed2;  // Second fixed primary
  final int wheelIndex;       // Which column is moving (0, 1, or 2)
  final double sliderValue;

  // Precomputed values
  final double fixed1Sq;
  final double fixed2Sq;
  final List<double> fixed1CrossFixed2;
  final double fixed1CrossFixed2Sq;

  _KappaPolynomial({
    required this.fixed1,
    required this.fixed2,
    required this.wheelIndex,
    required this.sliderValue,
  }) : fixed1Sq = fixed1[0] * fixed1[0] + fixed1[1] * fixed1[1] + fixed1[2] * fixed1[2],
       fixed2Sq = fixed2[0] * fixed2[0] + fixed2[1] * fixed2[1] + fixed2[2] * fixed2[2],
       fixed1CrossFixed2 = [
         fixed1[1] * fixed2[2] - fixed1[2] * fixed2[1],
         fixed1[2] * fixed2[0] - fixed1[0] * fixed2[2],
         fixed1[0] * fixed2[1] - fixed1[1] * fixed2[0],
       ],
       fixed1CrossFixed2Sq = _computeCrossProductNormSq(fixed1, fixed2);

  static double _computeCrossProductNormSq(List<double> a, List<double> b) {
    final cx = a[1] * b[2] - a[2] * b[1];
    final cy = a[2] * b[0] - a[0] * b[2];
    final cz = a[0] * b[1] - a[1] * b[0];
    return cx * cx + cy * cy + cz * cz;
  }

  static List<double> _cross(List<double> a, List<double> b) {
    return [
      a[1] * b[2] - a[2] * b[1],
      a[2] * b[0] - a[0] * b[2],
      a[0] * b[1] - a[1] * b[0],
    ];
  }

  static double _dot(List<double> a, List<double> b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  }

  static double _normSq(List<double> a) {
    return a[0] * a[0] + a[1] * a[1] + a[2] * a[2];
  }

  /// Evaluate κ² at wheel coordinates (a, b)
  double evaluateKappaSq(double a, double b) {
    // Compute moving primary from wheel coordinates
    final p = wheelCoordsToRgb(a, b, sliderValue);

    // Build the three primaries in correct order
    List<double> p0, p1, p2;
    if (wheelIndex == 0) {
      p0 = p; p1 = fixed1; p2 = fixed2;
    } else if (wheelIndex == 1) {
      p0 = fixed1; p1 = p; p2 = fixed2;
    } else {
      p0 = fixed1; p1 = fixed2; p2 = p;
    }

    // ||M||_F² = |p0|² + |p1|² + |p2|²
    final mFrobSq = _normSq(p0) + _normSq(p1) + _normSq(p2);

    // det(M) = p0 · (p1 × p2)
    final p1CrossP2 = _cross(p1, p2);
    final det = _dot(p0, p1CrossP2);
    if (det.abs() < 1e-10) return double.infinity;

    // ||adj(M)||_F² = |p1 × p2|² + |p2 × p0|² + |p0 × p1|²
    final p2CrossP0 = _cross(p2, p0);
    final p0CrossP1 = _cross(p0, p1);
    final adjFrobSq = _normSq(p1CrossP2) + _normSq(p2CrossP0) + _normSq(p0CrossP1);

    // κ² = ||M||_F² × ||adj(M)||_F² / det²
    return mFrobSq * adjFrobSq / (det * det);
  }
}
