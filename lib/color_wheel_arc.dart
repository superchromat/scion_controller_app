// color_wheel_arc.dart — Shared wheel+arc gesture and painting base.

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Callback that builds a [CustomPainter] given the current wheel state.
typedef WheelPainterBuilder = CustomPainter Function({
  required double wheelX,
  required double wheelY,
  required double arcValue,
  required double wheelRadius,
  required Offset center,
});

/// A color wheel with a surrounding arc control.
///
/// Manages normalized state:
/// - [wheelX], [wheelY]: position on the wheel, each in [-1, 1]
/// - [arcValue]: arc position in [0, 1]
///
/// Gesture handling is identical for all uses (OKLCH picker, grade wheels).
/// Visual appearance is pluggable via [painterBuilder].
class ColorWheelArc extends StatefulWidget {
  final double size;
  final double initialWheelX;
  final double initialWheelY;
  final double initialArcValue;
  final ValueChanged<({double x, double y})>? onWheelChanged;
  final ValueChanged<double>? onArcChanged;
  final VoidCallback? onDoubleTap;
  final WheelPainterBuilder painterBuilder;

  const ColorWheelArc({
    super.key,
    required this.size,
    this.initialWheelX = 0.0,
    this.initialWheelY = 0.0,
    this.initialArcValue = 0.5,
    this.onWheelChanged,
    this.onArcChanged,
    this.onDoubleTap,
    required this.painterBuilder,
  });

  @override
  State<ColorWheelArc> createState() => ColorWheelArcState();
}

class ColorWheelArcState extends State<ColorWheelArc> {
  late double wheelX;
  late double wheelY;
  late double arcValue;

  int _dragMode = 0; // 0=none, 1=wheel, 2=arc
  bool get isDragging => _dragMode != 0;

  static const double arcWidth = 6.0;
  static const double arcGap = 2.0;
  static const double startAngle = 0.75 * pi;
  static const double sweepAngle = 1.5 * pi;

  @override
  void initState() {
    super.initState();
    wheelX = widget.initialWheelX;
    wheelY = widget.initialWheelY;
    arcValue = widget.initialArcValue;
  }

  /// Update position externally (e.g. from OSC). Ignored during drag.
  void setPosition(double x, double y, double arc) {
    if (_dragMode != 0) return;
    setState(() {
      wheelX = x;
      wheelY = y;
      arcValue = arc;
    });
  }

  /// Update just the wheel position. Ignored during drag.
  void setWheelPosition(double x, double y) {
    if (_dragMode != 0) return;
    setState(() {
      wheelX = x;
      wheelY = y;
    });
  }

  /// Update just the arc value. Ignored during drag.
  void setArcValue(double value) {
    if (_dragMode != 0) return;
    setState(() => arcValue = value);
  }

  double get _innerRadius =>
      widget.size / 2 - arcWidth - arcGap;

  void _handleDrag(Offset pos, {required bool isStart}) {
    final totalSize = widget.size;
    final center = Offset(totalSize / 2, totalSize / 2);
    final offset = pos - center;
    final dist = offset.distance;
    final innerRadius = _innerRadius;

    if (isStart && _dragMode == 0) {
      _dragMode = dist > innerRadius ? 2 : 1;
    }

    if (_dragMode == 2) {
      // Arc — angle to normalized 0..1
      var angle = atan2(offset.dy, offset.dx);
      var relAngle = angle - startAngle;
      while (relAngle < 0) relAngle += 2 * pi;
      while (relAngle >= 2 * pi) relAngle -= 2 * pi;

      if (relAngle > sweepAngle) {
        relAngle = relAngle < (sweepAngle + (2 * pi - sweepAngle) / 2)
            ? sweepAngle
            : 0;
      }

      setState(() => arcValue = (relAngle / sweepAngle).clamp(0.0, 1.0));
      widget.onArcChanged?.call(arcValue);
    } else {
      // Wheel — position to normalized (-1..1) clamped to unit circle
      final wheelRadius = innerRadius;
      var nx = offset.dx / wheelRadius;
      var ny = offset.dy / wheelRadius;
      final d = sqrt(nx * nx + ny * ny);
      if (d > 1.0) {
        nx /= d;
        ny /= d;
      }

      setState(() {
        wheelX = nx;
        wheelY = ny;
      });
      widget.onWheelChanged?.call((x: wheelX, y: wheelY));
    }
  }

  void _handleDragEnd() {
    setState(() => _dragMode = 0);
  }

  void _handleDoubleTap() {
    setState(() {
      wheelX = widget.initialWheelX;
      wheelY = widget.initialWheelY;
      arcValue = widget.initialArcValue;
    });
    widget.onWheelChanged?.call((x: wheelX, y: wheelY));
    widget.onArcChanged?.call(arcValue);
    widget.onDoubleTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = widget.size;
    final center = Offset(totalSize / 2, totalSize / 2);
    return GestureDetector(
      onPanStart: (d) => _handleDrag(d.localPosition, isStart: true),
      onPanUpdate: (d) => _handleDrag(d.localPosition, isStart: false),
      onPanEnd: (_) => _handleDragEnd(),
      onTapDown: (d) => _handleDrag(d.localPosition, isStart: true),
      onTapUp: (_) => _handleDragEnd(),
      onDoubleTap: _handleDoubleTap,
      child: CustomPaint(
        size: Size(totalSize, totalSize),
        painter: widget.painterBuilder(
          wheelX: wheelX,
          wheelY: wheelY,
          arcValue: arcValue,
          wheelRadius: _innerRadius,
          center: center,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared arc painting helpers
// ---------------------------------------------------------------------------

/// Paints the neumorphic arc slot (the track the value arc sits in).
void paintArcSlot(
  Canvas canvas,
  Offset center,
  double outerRadius,
  double arcRadius,
  double slotInnerRadius,
) {
  const startAngle = 0.75 * pi;
  const sweepAngle = 1.5 * pi;
  const arcWidth = 6.0;
  const lightOffset = Alignment(0.0, -0.4);
  final shaderRect = Rect.fromCircle(center: center, radius: outerRadius);

  // Border gradient
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: arcRadius),
    startAngle, sweepAngle, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth + 2
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: lightOffset,
        radius: 0.7,
        colors: const [Color(0xFF686868), Color(0xFF484848), Color(0xFF383838)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(shaderRect),
  );

  // Outer shadow
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: outerRadius - 1),
    startAngle, sweepAngle, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: const Alignment(0.0, 0.5),
        radius: 0.6,
        colors: const [Color(0xFF0C0C0C), Color(0xFF040404), Color(0x00000000)],
        stops: const [0.0, 0.3, 0.8],
      ).createShader(shaderRect),
  );

  // Inner highlight
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: slotInnerRadius + 1),
    startAngle, sweepAngle, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: lightOffset,
        radius: 0.6,
        colors: const [Color(0xFF353535), Color(0xFF252525), Color(0x00000000)],
        stops: const [0.0, 0.2, 0.5],
      ).createShader(shaderRect),
  );

  // Dark floor
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: arcRadius),
    startAngle, sweepAngle, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: lightOffset,
        radius: 0.7,
        colors: const [Color(0xFF1C1C1C), Color(0xFF161616), Color(0xFF101010)],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(shaderRect),
  );
}

/// Paints a unipolar value arc (0 = empty, 1 = full sweep).
void paintUnipolarArc(
  Canvas canvas,
  Offset center,
  double arcRadius,
  double outerRadius,
  double value,
  Color activeColor,
) {
  const startAngle = 0.75 * pi;
  const sweepAngle = 1.5 * pi;
  const arcWidth = 6.0;
  const lightOffset = Alignment(0.0, -0.4);
  const minArcSweep = 0.10;
  final shaderRect = Rect.fromCircle(center: center, radius: outerRadius);

  final valueSweep = value * sweepAngle;
  final drawSweep = valueSweep < minArcSweep ? minArcSweep : valueSweep;

  final gradient = RadialGradient(
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
    startAngle, drawSweep, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = gradient.createShader(shaderRect),
  );

  // Highlight
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: arcRadius),
    startAngle, drawSweep, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.6),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7],
      ).createShader(shaderRect),
  );
}

/// Paints a bipolar value arc (center = neutral, extends left or right).
void paintBipolarArc(
  Canvas canvas,
  Offset center,
  double arcRadius,
  double outerRadius,
  double normalizedValue, // 0..1 where 0.5 = neutral
  Color activeColor,
) {
  const startAngle = 0.75 * pi;
  const sweepAngle = 1.5 * pi;
  const arcWidth = 6.0;
  const lightOffset = Alignment(0.0, -0.4);
  const minArcSweep = 0.10;
  final shaderRect = Rect.fromCircle(center: center, radius: outerRadius);

  const neutralNormalized = 0.5;
  final neutralAngle = startAngle + neutralNormalized * sweepAngle;
  final valueAngle = startAngle + normalizedValue * sweepAngle;
  final arcStartAngle = min(neutralAngle, valueAngle);
  final arcEndAngle = max(neutralAngle, valueAngle);
  final arcSweep = arcEndAngle - arcStartAngle;

  var drawStart = arcStartAngle;
  var drawSweep = arcSweep;
  if (arcSweep < minArcSweep) {
    drawStart = valueAngle - minArcSweep / 2;
    drawSweep = minArcSweep;
  }

  final gradient = RadialGradient(
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
    drawStart, drawSweep, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = gradient.createShader(shaderRect),
  );

  // Highlight
  canvas.drawArc(
    Rect.fromCircle(center: center, radius: arcRadius),
    drawStart, drawSweep, false,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = RadialGradient(
        center: const Alignment(0.0, -0.6),
        radius: 0.5,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.7],
      ).createShader(shaderRect),
  );
}

/// Paints the selection indicator (circle outline + fill).
void paintWheelIndicator(Canvas canvas, Offset center, Offset position,
    double wheelRadius, {double radius = 5.0}) {
  final pos = Offset(
    center.dx + position.dx * wheelRadius,
    center.dy + position.dy * wheelRadius,
  );
  canvas.drawCircle(
    pos,
    radius + 1.5,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white,
  );
  canvas.drawCircle(
    pos,
    radius,
    Paint()..color = Colors.white.withValues(alpha: 0.3),
  );
}

/// Paints a crosshair at center.
void paintCrosshair(Canvas canvas, Offset center, double wheelRadius) {
  final paint = Paint()
    ..color = Colors.white.withValues(alpha: 0.3)
    ..strokeWidth = 0.5;
  canvas.drawLine(
    Offset(center.dx - wheelRadius * 0.3, center.dy),
    Offset(center.dx + wheelRadius * 0.3, center.dy),
    paint,
  );
  canvas.drawLine(
    Offset(center.dx, center.dy - wheelRadius * 0.3),
    Offset(center.dx, center.dy + wheelRadius * 0.3),
    paint,
  );
}

/// Paints a clipped wheel image into the wheel area.
void paintWheelImage(
  Canvas canvas,
  Offset center,
  double wheelRadius,
  ui.Image image,
) {
  canvas.save();
  canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: wheelRadius)));
  final src = Rect.fromLTWH(
      0, 0, image.width.toDouble(), image.height.toDouble());
  final dst = Rect.fromCircle(center: center, radius: wheelRadius);
  canvas.drawImageRect(image, src, dst,
      Paint()..filterQuality = FilterQuality.high);
  canvas.restore();
}
