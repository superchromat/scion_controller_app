// oklch_color_picker.dart
// OKLCH color picker for text overlay

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'color_wheel_arc.dart';

// Cached wheel image
ui.Image? _cachedOklchWheelImage;
int _cachedOklchWheelSize = 0;
double _cachedOklchLightness = 0.5;

/// OKLCH to linear RGB conversion
/// L: 0-1 (lightness)
/// C: 0-0.4 (chroma, roughly)
/// H: 0-360 (hue in degrees)
List<double> oklchToLinearRgb(double l, double c, double h) {
  // Convert to OKLab first
  final hRad = h * pi / 180.0;
  final a = c * cos(hRad);
  final b = c * sin(hRad);

  // OKLab to linear RGB via LMS
  final l_ = l + 0.3963377774 * a + 0.2158037573 * b;
  final m_ = l - 0.1055613458 * a - 0.0638541728 * b;
  final s_ = l - 0.0894841775 * a - 1.2914855480 * b;

  final lCubed = l_ * l_ * l_;
  final mCubed = m_ * m_ * m_;
  final sCubed = s_ * s_ * s_;

  final r = 4.0767416621 * lCubed - 3.3077115913 * mCubed + 0.2309699292 * sCubed;
  final g = -1.2684380046 * lCubed + 2.6097574011 * mCubed - 0.3413193965 * sCubed;
  final bl = -0.0041960863 * lCubed - 0.7034186147 * mCubed + 1.7076147010 * sCubed;

  return [r, g, bl];
}

/// Linear RGB to sRGB (gamma correction)
double linearToSrgb(double x) {
  if (x <= 0.0031308) {
    return 12.92 * x;
  }
  return 1.055 * pow(x, 1.0 / 2.4) - 0.055;
}

/// OKLCH to sRGB (0-255)
List<int> oklchToSrgb255(double l, double c, double h) {
  final linear = oklchToLinearRgb(l, c, h);
  final r = (linearToSrgb(linear[0]).clamp(0.0, 1.0) * 255).round();
  final g = (linearToSrgb(linear[1]).clamp(0.0, 1.0) * 255).round();
  final b = (linearToSrgb(linear[2]).clamp(0.0, 1.0) * 255).round();
  return [r, g, b];
}

/// Check if OKLCH color is within sRGB gamut
bool isInGamut(double l, double c, double h) {
  final linear = oklchToLinearRgb(l, c, h);
  return linear[0] >= -0.001 && linear[0] <= 1.001 &&
         linear[1] >= -0.001 && linear[1] <= 1.001 &&
         linear[2] >= -0.001 && linear[2] <= 1.001;
}

/// Find maximum chroma for given lightness and hue
double maxChromaForLH(double l, double h) {
  double lo = 0.0, hi = 0.5;
  for (int i = 0; i < 20; i++) {
    final mid = (lo + hi) / 2;
    if (isInGamut(l, mid, h)) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// sRGB to OKLCH
List<double> srgbToOklch(int r, int g, int b) {
  // sRGB to linear
  double srgbToLinear(int v) {
    final x = v / 255.0;
    if (x <= 0.04045) return x / 12.92;
    return pow((x + 0.055) / 1.055, 2.4).toDouble();
  }

  final lr = srgbToLinear(r);
  final lg = srgbToLinear(g);
  final lb = srgbToLinear(b);

  // Linear RGB to LMS
  final l_ = pow(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb, 1.0 / 3.0);
  final m_ = pow(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb, 1.0 / 3.0);
  final s_ = pow(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb, 1.0 / 3.0);

  // LMS to OKLab
  final L = 0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_;
  final a = 1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_;
  final bVal = 0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_;

  // OKLab to OKLCH
  final C = sqrt(a * a + bVal * bVal);
  var H = atan2(bVal, a) * 180 / pi;
  if (H < 0) H += 360;

  return [L, C, H];
}

/// Generate OKLCH color wheel for given lightness
ui.Image _generateOklchWheel(int size, double lightness) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final center = size / 2.0;
  final radius = center - 1;

  for (int y = 0; y < size; y++) {
    for (int x = 0; x < size; x++) {
      final dx = x - center + 0.5;
      final dy = y - center + 0.5;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist <= radius + 1.0) {
        // Angle = hue, distance from center = chroma
        var hue = atan2(-dy, dx) * 180 / pi;
        if (hue < 0) hue += 360;

        // Chroma scaled so edge of wheel = max displayable chroma
        final maxC = maxChromaForLH(lightness, hue);
        final chroma = (dist / radius) * maxC;

        final rgb = oklchToSrgb255(lightness, chroma, hue);

        // Anti-aliasing at edge
        final alpha = (radius + 1.0 - dist).clamp(0.0, 1.0);

        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromRGBO(rgb[0], rgb[1], rgb[2], alpha),
        );
      }
    }
  }

  return recorder.endRecording().toImageSync(size, size);
}

class OklchColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color>? onColorChanged;
  final double size;

  const OklchColorPicker({
    super.key,
    this.initialColor = Colors.white,
    this.onColorChanged,
    this.size = 90,
  });

  @override
  State<OklchColorPicker> createState() => OklchColorPickerState();
}

class OklchColorPickerState extends State<OklchColorPicker> {
  final _wheelKey = GlobalKey<ColorWheelArcState>();

  bool get isDragging => _wheelKey.currentState?.isDragging ?? false;

  void setColor(Color color) {
    final state = _wheelKey.currentState;
    if (state == null || state.isDragging) return;
    final pos = _colorToWheelPos(color);
    state.setPosition(pos.x, pos.y, pos.arc);
  }

  ({double x, double y, double arc}) _colorToWheelPos(Color color) {
    final oklch = srgbToOklch(color.red, color.green, color.blue);
    final lightness = oklch[0].clamp(0.0, 1.0);
    final chroma = oklch[1];
    final hue = oklch[2];
    final maxC = maxChromaForLH(lightness, hue);
    final norm = maxC > 0 ? (chroma / maxC).clamp(0.0, 1.0) : 0.0;
    final rad = hue * pi / 180;
    return (x: cos(rad) * norm, y: -sin(rad) * norm, arc: lightness);
  }

  Color _wheelPosToColor(double wx, double wy, double lightness) {
    var hue = atan2(-wy, wx) * 180 / pi;
    if (hue < 0) hue += 360;
    final d = sqrt(wx * wx + wy * wy).clamp(0.0, 1.0);
    final chroma = d * maxChromaForLH(lightness, hue);
    final rgb = oklchToSrgb255(lightness, chroma, hue);
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }

  Color get currentColor {
    final s = _wheelKey.currentState;
    if (s == null) {
      final pos = _colorToWheelPos(widget.initialColor);
      return _wheelPosToColor(pos.x, pos.y, pos.arc);
    }
    return _wheelPosToColor(s.wheelX, s.wheelY, s.arcValue);
  }

  void _onWheelChanged(({double x, double y}) pos) {
    widget.onColorChanged?.call(currentColor);
  }

  void _onArcChanged(double value) {
    widget.onColorChanged?.call(currentColor);
  }

  void _onDoubleTap() {
    widget.onColorChanged?.call(currentColor);
  }

  @override
  Widget build(BuildContext context) {
    final init = _colorToWheelPos(widget.initialColor);
    return ColorWheelArc(
      key: _wheelKey,
      size: widget.size,
      initialWheelX: init.x,
      initialWheelY: init.y,
      initialArcValue: init.arc,
      onWheelChanged: _onWheelChanged,
      onArcChanged: _onArcChanged,
      onDoubleTap: _onDoubleTap,
      painterBuilder: ({
        required wheelX,
        required wheelY,
        required arcValue,
        required wheelRadius,
        required center,
      }) => _OklchWheelPainter(
        lightness: arcValue,
        wheelX: wheelX,
        wheelY: wheelY,
      ),
    );
  }
}

class _OklchWheelPainter extends CustomPainter {
  final double lightness;
  final double wheelX;
  final double wheelY;

  _OklchWheelPainter({
    required this.lightness,
    required this.wheelX,
    required this.wheelY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    const arcWidth = ColorWheelArcState.arcWidth;
    const arcGap = ColorWheelArcState.arcGap;
    final arcRadius = outerRadius - arcWidth / 2;
    final slotInnerRadius = outerRadius - arcWidth;
    final wheelRadius = slotInnerRadius - arcGap;

    paintArcSlot(canvas, center, outerRadius, arcRadius, slotInnerRadius);
    paintUnipolarArc(canvas, center, arcRadius, outerRadius, lightness,
        const Color(0xFFF0B830));

    // OKLCH wheel image
    final wheelSize = (wheelRadius * 2).round();
    if (_cachedOklchWheelImage == null ||
        _cachedOklchWheelSize != wheelSize ||
        (_cachedOklchLightness - lightness).abs() >= 0.01) {
      _cachedOklchWheelImage = _generateOklchWheel(wheelSize, lightness);
      _cachedOklchWheelSize = wheelSize;
      _cachedOklchLightness = lightness;
    }
    paintWheelImage(canvas, center, wheelRadius, _cachedOklchWheelImage!);

    paintWheelIndicator(canvas, center, Offset(wheelX, wheelY), wheelRadius);
    paintCrosshair(canvas, center, wheelRadius);
  }

  @override
  bool shouldRepaint(covariant _OklchWheelPainter old) {
    return old.lightness != lightness ||
        old.wheelX != wheelX ||
        old.wheelY != wheelY;
  }
}
