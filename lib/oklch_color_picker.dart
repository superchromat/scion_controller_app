// oklch_color_picker.dart
// OKLCH color picker for text overlay

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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
  late double _lightness;
  late double _chroma;
  late double _hue;

  // Drag mode: 0 = none, 1 = wheel (hue/chroma), 2 = arc (lightness)
  int _dragMode = 0;

  static const double _arcWidth = 6.0;
  static const double _arcGap = 2.0;
  static const double _startAngle = 0.75 * pi;
  static const double _sweepAngle = 1.5 * pi;

  @override
  void initState() {
    super.initState();
    _initFromColor(widget.initialColor);
  }

  void _initFromColor(Color color) {
    final oklch = srgbToOklch(color.red, color.green, color.blue);
    _lightness = oklch[0].clamp(0.0, 1.0);
    _chroma = oklch[1];
    _hue = oklch[2];
  }

  void setColor(Color color) {
    setState(() {
      _initFromColor(color);
    });
  }

  Color get currentColor {
    final rgb = oklchToSrgb255(_lightness, _chroma, _hue);
    return Color.fromARGB(255, rgb[0], rgb[1], rgb[2]);
  }

  void _handleDrag(Offset pos, {required bool isStart}) {
    final totalSize = widget.size;
    final center = Offset(totalSize / 2, totalSize / 2);
    final offset = pos - center;
    final dist = offset.distance;
    final outerRadius = totalSize / 2;
    final innerRadius = outerRadius - _arcWidth - _arcGap;

    if (isStart) {
      _dragMode = dist > innerRadius ? 2 : 1;
    }

    if (_dragMode == 2) {
      // Arc mode — map angle to lightness 0→1 (unipolar)
      var angle = atan2(offset.dy, offset.dx);
      var relAngle = angle - _startAngle;
      while (relAngle < 0) { relAngle += 2 * pi; }
      while (relAngle >= 2 * pi) { relAngle -= 2 * pi; }

      if (relAngle > _sweepAngle) {
        relAngle = relAngle < (_sweepAngle + (2 * pi - _sweepAngle) / 2)
            ? _sweepAngle
            : 0;
      }

      final lightness = (relAngle / _sweepAngle).clamp(0.0, 1.0);

      setState(() {
        _lightness = lightness;
        // Clamp chroma to max for new lightness
        final maxC = maxChromaForLH(_lightness, _hue);
        if (_chroma > maxC) _chroma = maxC;
      });
      _notifyChange();
    } else {
      // Wheel mode — map position to hue/chroma
      final wheelRadius = innerRadius;

      var hue = atan2(-offset.dy, offset.dx) * 180 / pi;
      if (hue < 0) hue += 360;

      final clampedDist = dist.clamp(0.0, wheelRadius);
      final maxC = maxChromaForLH(_lightness, hue);
      final chroma = (clampedDist / wheelRadius) * maxC;

      setState(() {
        _hue = hue;
        _chroma = chroma;
      });
      _notifyChange();
    }
  }

  void _handleDragEnd() {
    setState(() => _dragMode = 0);
  }

  void _handleDoubleTap() {
    setState(() {
      _initFromColor(widget.initialColor);
    });
    _notifyChange();
  }

  void _notifyChange() {
    widget.onColorChanged?.call(currentColor);
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = widget.size;
    return GestureDetector(
      onPanStart: (d) => _handleDrag(d.localPosition, isStart: true),
      onPanUpdate: (d) => _handleDrag(d.localPosition, isStart: false),
      onPanEnd: (_) => _handleDragEnd(),
      onTapDown: (d) => _handleDrag(d.localPosition, isStart: true),
      onTapUp: (_) => _handleDragEnd(),
      onDoubleTap: _handleDoubleTap,
      child: CustomPaint(
        size: Size(totalSize, totalSize),
        painter: _OklchWheelPainter(
          lightness: _lightness,
          chroma: _chroma,
          hue: _hue,
        ),
      ),
    );
  }
}

class _OklchWheelPainter extends CustomPainter {
  final double lightness;
  final double chroma;
  final double hue;

  static const double arcWidth = 6.0;
  static const double arcGap = 2.0;
  static const double startAngle = 0.75 * pi;
  static const double sweepAngle = 1.5 * pi;

  _OklchWheelPainter({
    required this.lightness,
    required this.chroma,
    required this.hue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final arcRadius = outerRadius - arcWidth / 2;
    final slotInnerRadius = outerRadius - arcWidth;
    final wheelRadius = slotInnerRadius - arcGap;

    // === NEUMORPHIC ARC SLOT ===
    const lightOffset = Alignment(0.0, -0.4);

    // Border gradient
    final borderGradient = RadialGradient(
      center: lightOffset,
      radius: 0.7,
      colors: const [Color(0xFF686868), Color(0xFF484848), Color(0xFF383838)],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle, sweepAngle, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcWidth + 2
        ..strokeCap = StrokeCap.butt
        ..shader = borderGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // Outer shadow
    final outerShadowGradient = RadialGradient(
      center: const Alignment(0.0, 0.5),
      radius: 0.6,
      colors: const [Color(0xFF0C0C0C), Color(0xFF040404), Color(0x00000000)],
      stops: const [0.0, 0.3, 0.8],
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius - 1),
      startAngle, sweepAngle, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.butt
        ..shader = outerShadowGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // Inner highlight
    final innerHighlightGradient = RadialGradient(
      center: lightOffset,
      radius: 0.6,
      colors: const [Color(0xFF353535), Color(0xFF252525), Color(0x00000000)],
      stops: const [0.0, 0.2, 0.5],
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: slotInnerRadius + 1),
      startAngle, sweepAngle, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.butt
        ..shader = innerHighlightGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // Dark floor
    final floorGradient = RadialGradient(
      center: lightOffset,
      radius: 0.7,
      colors: const [Color(0xFF1C1C1C), Color(0xFF161616), Color(0xFF101010)],
      stops: const [0.0, 0.5, 1.0],
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle, sweepAngle, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcWidth - 2
        ..strokeCap = StrokeCap.butt
        ..shader = floorGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // === UNIPOLAR LIGHTNESS ARC ===
    const Color activeColor = Color(0xFFF0B830);

    // Unipolar: arc fills from start angle, length = lightness * sweepAngle
    final valueSweep = lightness * sweepAngle;

    const minArcSweep = 0.10;
    final drawArcSweep = valueSweep < minArcSweep ? minArcSweep : valueSweep;

    final valueArcGradient = RadialGradient(
      center: lightOffset,
      radius: 0.8,
      colors: [
        activeColor,
        Color.lerp(activeColor, Colors.black, 0.10)!,
        Color.lerp(activeColor, Colors.black, 0.20)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle, drawArcSweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcWidth - 2
        ..strokeCap = StrokeCap.butt
        ..shader = valueArcGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // Highlight on value arc
    final highlightGradient = RadialGradient(
      center: const Alignment(0.0, -0.6),
      radius: 0.5,
      colors: [
        Colors.white.withValues(alpha: 0.35),
        Colors.white.withValues(alpha: 0.10),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.7],
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: arcRadius),
      startAngle, drawArcSweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcWidth - 2
        ..strokeCap = StrokeCap.butt
        ..shader = highlightGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // === INNER OKLCH COLOR WHEEL ===
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: wheelRadius)));

    final wheelSize = (wheelRadius * 2).round();

    // Check cache
    if (_cachedOklchWheelImage == null ||
        _cachedOklchWheelSize != wheelSize ||
        (_cachedOklchLightness - lightness).abs() >= 0.01) {
      _cachedOklchWheelImage = _generateOklchWheel(wheelSize, lightness);
      _cachedOklchWheelSize = wheelSize;
      _cachedOklchLightness = lightness;
    }

    final src = Rect.fromLTWH(0, 0,
        _cachedOklchWheelImage!.width.toDouble(),
        _cachedOklchWheelImage!.height.toDouble());
    final dst = Rect.fromCircle(center: center, radius: wheelRadius);
    canvas.drawImageRect(_cachedOklchWheelImage!, src, dst,
        Paint()..filterQuality = FilterQuality.high);

    canvas.restore();

    // === SELECTION INDICATOR ===
    final maxC = maxChromaForLH(lightness, hue);
    final normalizedChroma = maxC > 0 ? chroma / maxC : 0.0;
    final dist = normalizedChroma * wheelRadius;
    final hueRad = hue * pi / 180;
    final selX = center.dx + dist * cos(hueRad);
    final selY = center.dy - dist * sin(hueRad);
    final selPos = Offset(selX, selY);

    const indicatorRadius = 5.0;
    canvas.drawCircle(
      selPos,
      indicatorRadius + 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      selPos,
      indicatorRadius,
      Paint()..color = Colors.white.withValues(alpha: 0.3),
    );

    // === CROSSHAIR AT CENTER ===
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(center.dx - wheelRadius * 0.3, center.dy),
      Offset(center.dx + wheelRadius * 0.3, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - wheelRadius * 0.3),
      Offset(center.dx, center.dy + wheelRadius * 0.3),
      crossPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _OklchWheelPainter old) {
    return old.lightness != lightness ||
        old.chroma != chroma ||
        old.hue != hue;
  }
}
