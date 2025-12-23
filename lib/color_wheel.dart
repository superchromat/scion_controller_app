import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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

  ColorWheelPainter(
    this.selected,
    this.otherPrimary1,
    this.otherPrimary2,
    this.wheelIndex, {
    this.sliderValue = 0.0,
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

  void _drawDangerZone(Canvas canvas, Offset center, double radius) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    const double threshold = 15.0;
    const double wheelScale = 2.0;
    final step = 3.0; // Pixel step for fill

    // First pass: fill danger zone with white
    final dangerPath = Path();

    for (double x = -radius; x <= radius; x += step) {
      for (double y = -radius; y <= radius; y += step) {
        final dist = sqrt(x * x + y * y);
        if (dist > radius) continue;

        final a = (x / radius) * wheelScale;
        final b = (-y / radius) * wheelScale;
        final kappa = _conditionNumberAt(a, b);

        if (kappa >= threshold) {
          dangerPath.addRect(Rect.fromCenter(
            center: Offset(center.dx + x, center.dy + y),
            width: step + 0.5,
            height: step + 0.5,
          ));
        }
      }
    }

    // Draw white background for danger zone
    canvas.drawPath(
      dangerPath,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );

    // Draw red hatch pattern over danger zone
    canvas.clipPath(dangerPath);

    final hatchPaint = Paint()
      ..color = const Color(0xFFE53935).withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Diagonal lines from bottom-left to top-right
    const hatchSpacing = 6.0;
    for (double offset = -radius * 2; offset < radius * 2; offset += hatchSpacing) {
      canvas.drawLine(
        Offset(center.dx + offset - radius, center.dy + radius),
        Offset(center.dx + offset + radius, center.dy - radius),
        hatchPaint,
      );
    }

    canvas.restore();
  }

  double _conditionNumberAt(double a, double b) {
    // Get RGB for this wheel position
    final rgb = wheelCoordsToRgb(a, b, sliderValue);
    final testPrimary = rgb;

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
        old.otherPrimary2 != otherPrimary2 ||
        old.sliderValue != sliderValue;
  }
}
