import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'lighting_settings.dart';

/// Represents a color in RGB space, allowing values outside [0,1] for extended gamut.
class ExtendedRGB {
  final double r;
  final double g;
  final double b;

  const ExtendedRGB(this.r, this.g, this.b);

  /// Identity primaries
  static const red = ExtendedRGB(1, 0, 0);
  static const green = ExtendedRGB(0, 1, 0);
  static const blue = ExtendedRGB(0, 0, 1);
  static const white = ExtendedRGB(1, 1, 1);

  /// Convert to a displayable Flutter Color, clamping to sRGB
  Color toColor() {
    return Color.fromRGBO(
      (r.clamp(0, 1) * 255).round(),
      (g.clamp(0, 1) * 255).round(),
      (b.clamp(0, 1) * 255).round(),
      1,
    );
  }

  /// Check if this color is within sRGB gamut
  bool get isInGamut => r >= 0 && r <= 1 && g >= 0 && g <= 1 && b >= 0 && b <= 1;

  /// Magnitude (distance from origin)
  double get magnitude => sqrt(r * r + g * g + b * b);

  /// Normalized direction
  ExtendedRGB get normalized {
    final m = magnitude;
    if (m < 1e-10) return white;
    return ExtendedRGB(r / m, g / m, b / m);
  }

  List<double> toList() => [r, g, b];

  @override
  String toString() => 'RGB(${r.toStringAsFixed(3)}, ${g.toStringAsFixed(3)}, ${b.toStringAsFixed(3)})';
}

/// A color wheel widget that allows selecting colors including extended gamut.
/// The center is white [1,1,1], and the edge shows saturated hues.
/// Beyond the normal edge, the wheel extends into "super-saturated" territory.
class ColorWheel extends StatefulWidget {
  final ExtendedRGB value;
  final ValueChanged<ExtendedRGB>? onChanged;
  final double size;
  final String? label;
  final double maxExtension; // How far beyond sRGB to allow (1.0 = sRGB only, 2.0 = 2x)

  const ColorWheel({
    super.key,
    required this.value,
    this.onChanged,
    this.size = 150,
    this.label,
    this.maxExtension = 2.5,
  });

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  @override
  Widget build(BuildContext context) {
    final lighting = context.watch<LightingSettings>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
        ],
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) => _handleDrag(details.localPosition),
          onPanStart: (details) => _handleDrag(details.localPosition),
          onPanUpdate: (details) => _handleDrag(details.localPosition),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _ColorWheelPainter(
                value: widget.value,
                maxExtension: widget.maxExtension,
                lighting: lighting,
              ),
              size: Size(widget.size, widget.size),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // RGB value display
        _buildValueDisplay(),
      ],
    );
  }

  Widget _buildValueDisplay() {
    final v = widget.value;
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      color: Colors.grey[400],
    );

    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('R:', style: textStyle.copyWith(color: Colors.red[300])),
            SizedBox(
              width: 50,
              child: Text(
                v.r.toStringAsFixed(3),
                style: textStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('G:', style: textStyle.copyWith(color: Colors.green[300])),
            SizedBox(
              width: 50,
              child: Text(
                v.g.toStringAsFixed(3),
                style: textStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('B:', style: textStyle.copyWith(color: Colors.blue[300])),
            SizedBox(
              width: 50,
              child: Text(
                v.b.toStringAsFixed(3),
                style: textStyle,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleDrag(Offset localPosition) {
    print('ColorWheel drag: $localPosition');
    if (widget.onChanged == null) return;

    final center = Offset(widget.size / 2, widget.size / 2);
    final offset = localPosition - center;
    final radius = widget.size / 2;

    // Convert to polar coordinates
    final angle = atan2(offset.dy, offset.dx);
    final distance = offset.distance / radius; // 0 at center, 1 at sRGB edge

    // Clamp distance to max extension
    final clampedDistance = distance.clamp(0.0, widget.maxExtension);

    // Convert polar to RGB
    // Center is white [1,1,1]
    // Edge at distance=1 is the saturated hue
    // Beyond edge, we extrapolate linearly
    final rgb = _polarToRGB(angle, clampedDistance);

    widget.onChanged!(rgb);
  }

  /// Convert polar coordinates (angle, distance) to RGB.
  /// At distance=0, color is white [1,1,1].
  /// At distance=1, color is the saturated hue on the sRGB boundary.
  /// Beyond distance=1, we extrapolate linearly (extended gamut).
  ExtendedRGB _polarToRGB(double angle, double distance) {
    if (distance < 1e-10) {
      return ExtendedRGB.white;
    }

    // Get the hue color at the edge (fully saturated)
    // Angle 0 = red, 2pi/3 = green, 4pi/3 = blue
    final hue = (angle + pi) / (2 * pi); // Normalize to [0,1]
    final hueColor = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor();

    // The direction from white to this hue
    final hueR = hueColor.r;
    final hueG = hueColor.g;
    final hueB = hueColor.b;

    // Interpolate from white toward hue, and beyond
    // At distance=0: white [1,1,1]
    // At distance=1: hue color
    // Beyond: extrapolate linearly
    final r = 1.0 + (hueR - 1.0) * distance;
    final g = 1.0 + (hueG - 1.0) * distance;
    final b = 1.0 + (hueB - 1.0) * distance;

    return ExtendedRGB(r, g, b);
  }
}

class _ColorWheelPainter extends CustomPainter {
  final ExtendedRGB value;
  final double maxExtension;
  final LightingSettings lighting;

  _ColorWheelPainter({
    required this.value,
    required this.maxExtension,
    required this.lighting,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final srgbRadius = radius / maxExtension; // Where sRGB boundary is

    // Draw the wheel using a sweep gradient with radial saturation
    _drawColorWheel(canvas, center, radius, srgbRadius);

    // Draw sRGB boundary circle
    final boundaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.3);
    canvas.drawCircle(center, srgbRadius, boundaryPaint);

    // Draw outer boundary
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.grey[700]!;
    canvas.drawCircle(center, radius - 1, outerPaint);

    // Draw the current selection indicator
    _drawSelectionIndicator(canvas, center, radius, srgbRadius);
  }

  void _drawColorWheel(Canvas canvas, Offset center, double radius, double srgbRadius) {
    // Draw pixel by pixel for accurate extended gamut representation
    final pixelSize = 3.0;

    for (double x = -radius; x <= radius; x += pixelSize) {
      for (double y = -radius; y <= radius; y += pixelSize) {
        final distance = sqrt(x * x + y * y);
        if (distance > radius) continue;

        final normalizedDistance = distance / srgbRadius; // 1.0 at sRGB boundary
        final angle = atan2(y, x);

        // Get the color at this position
        final color = _getColorAtPolar(angle, normalizedDistance);

        // Determine opacity - fade out in extended region
        double opacity = 1.0;
        if (normalizedDistance > 1.0) {
          // Hatching pattern for extended gamut
          final hatchPhase = ((x + y) / 6).floor() % 2;
          opacity = hatchPhase == 0 ? 0.7 : 0.4;
        }

        final paint = Paint()
          ..color = color.toColor().withValues(alpha: opacity);

        canvas.drawRect(
          Rect.fromCenter(
            center: center + Offset(x, y),
            width: pixelSize,
            height: pixelSize,
          ),
          paint,
        );
      }
    }
  }

  ExtendedRGB _getColorAtPolar(double angle, double distance) {
    if (distance < 1e-10) {
      return ExtendedRGB.white;
    }

    // Get the hue color at the edge
    final hue = (angle + pi) / (2 * pi);
    final hueColor = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor();

    final hueR = hueColor.r;
    final hueG = hueColor.g;
    final hueB = hueColor.b;

    // Interpolate/extrapolate from white
    final r = 1.0 + (hueR - 1.0) * distance;
    final g = 1.0 + (hueG - 1.0) * distance;
    final b = 1.0 + (hueB - 1.0) * distance;

    return ExtendedRGB(r, g, b);
  }

  void _drawSelectionIndicator(Canvas canvas, Offset center, double radius, double srgbRadius) {
    // Convert current value to polar coordinates
    final polar = _rgbToPolar(value);
    final angle = polar.$1;
    final distance = polar.$2;

    // Convert back to screen coordinates
    final screenDistance = distance * srgbRadius;
    final indicatorPos = center + Offset(
      cos(angle) * screenDistance,
      sin(angle) * screenDistance,
    );

    // Draw indicator
    final outerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;

    final innerRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.black;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = value.toColor();

    canvas.drawCircle(indicatorPos, 10, fill);
    canvas.drawCircle(indicatorPos, 10, innerRing);
    canvas.drawCircle(indicatorPos, 11, outerRing);
  }

  /// Convert RGB to polar (angle, distance) coordinates.
  /// White [1,1,1] maps to distance=0.
  (double angle, double distance) _rgbToPolar(ExtendedRGB rgb) {
    // Direction from white to this color
    final dr = rgb.r - 1.0;
    final dg = rgb.g - 1.0;
    final db = rgb.b - 1.0;

    final distance = sqrt(dr * dr + dg * dg + db * db);

    if (distance < 1e-10) {
      return (0, 0);
    }

    // Find the angle by projecting onto the color wheel plane
    // This is approximate - we find the hue that best matches
    double bestAngle = 0;
    double bestMatch = double.negativeInfinity;

    for (double a = 0; a < 2 * pi; a += 0.01) {
      final hue = (a + pi) / (2 * pi);
      final hueColor = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor();

      final hueR = hueColor.r - 1.0;
      final hueG = hueColor.g - 1.0;
      final hueB = hueColor.b - 1.0;

      // Dot product to measure alignment
      final dot = dr * hueR + dg * hueG + db * hueB;
      if (dot > bestMatch) {
        bestMatch = dot;
        bestAngle = a;
      }
    }

    // Calculate distance based on how far along the direction we are
    final hue = (bestAngle + pi) / (2 * pi);
    final hueColor = HSVColor.fromAHSV(1, hue * 360, 1, 1).toColor();
    final hueR = hueColor.r - 1.0;
    final hueG = hueColor.g - 1.0;
    final hueB = hueColor.b - 1.0;
    final hueMag = sqrt(hueR * hueR + hueG * hueG + hueB * hueB);

    final projectedDistance = hueMag > 1e-10 ? distance / hueMag : 0.0;

    return (bestAngle, projectedDistance);
  }

  @override
  bool shouldRepaint(covariant _ColorWheelPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.maxExtension != maxExtension;
  }
}
