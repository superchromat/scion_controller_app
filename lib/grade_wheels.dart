// grade_wheels.dart — Per-zone color grading wheels (shadows/midtones/highlights)
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'oklch_color_picker.dart';
import 'labeled_card.dart';

// ---------------------------------------------------------------------------
// Cached OKLCH wheel image for grade wheels — keyed by (size, lightness)
// ---------------------------------------------------------------------------
ui.Image? _cachedGradeWheelImage;
int _cachedGradeWheelSize = 0;
double _cachedGradeWheelLightness = -1;

/// Generate OKLCH color wheel at given lightness, synchronously cached.
/// Level (-1..+1) is mapped to OKLCH lightness (0.1..0.9).
/// Uses same approach as oklch_color_picker.dart: PictureRecorder + toImageSync.
ui.Image _getGradeWheelImage(int size, double lightness) {
  if (_cachedGradeWheelImage != null &&
      _cachedGradeWheelSize == size &&
      (_cachedGradeWheelLightness - lightness).abs() < 0.01) {
    return _cachedGradeWheelImage!;
  }

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
        var hue = atan2(-dy, dx) * 180 / pi;
        if (hue < 0) hue += 360;

        final maxC = maxChromaForLH(lightness, hue);
        final chroma = (dist / radius) * maxC;
        final rgb = oklchToSrgb255(lightness, chroma, hue);

        final alpha = (radius + 1.0 - dist).clamp(0.0, 1.0);

        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1),
          Paint()..color = Color.fromRGBO(rgb[0], rgb[1], rgb[2], alpha),
        );
      }
    }
  }

  _cachedGradeWheelImage = recorder.endRecording().toImageSync(size, size);
  _cachedGradeWheelSize = size;
  _cachedGradeWheelLightness = lightness;
  return _cachedGradeWheelImage!;
}

// ---------------------------------------------------------------------------
// GradeWheel — StatefulWidget managing shift_x, shift_y, level
// ---------------------------------------------------------------------------
class GradeWheel extends StatefulWidget {
  final String basePath; // e.g. "/send/1/grade/shadows"
  final double size;

  const GradeWheel({
    super.key,
    required this.basePath,
    this.size = 100.0,
  });

  @override
  State<GradeWheel> createState() => _GradeWheelState();
}

class _GradeWheelState extends State<GradeWheel> {
  double _shiftX = 0.0;
  double _shiftY = 0.0;
  double _level = 0.0;

  // Drag mode: 0 = none, 1 = wheel (shift), 2 = arc (level)
  int _dragMode = 0;

  String get _shiftXAddr => '${widget.basePath}/shift_x';
  String get _shiftYAddr => '${widget.basePath}/shift_y';
  String get _levelAddr => '${widget.basePath}/level';

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress(_shiftXAddr);
    reg.registerAddress(_shiftYAddr);
    reg.registerAddress(_levelAddr);
    reg.registerListener(_shiftXAddr, _onShiftX);
    reg.registerListener(_shiftYAddr, _onShiftY);
    reg.registerListener(_levelAddr, _onLevel);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener(_shiftXAddr, _onShiftX);
    reg.unregisterListener(_shiftYAddr, _onShiftY);
    reg.unregisterListener(_levelAddr, _onLevel);
    super.dispose();
  }

  void _onShiftX(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      setState(() => _shiftX = (args.first as num).toDouble());
    }
  }

  void _onShiftY(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      setState(() => _shiftY = (args.first as num).toDouble());
    }
  }

  void _onLevel(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      setState(() => _level = (args.first as num).toDouble());
    }
  }

  void _sendOsc(String address, double value) {
    final network = context.read<Network>();
    network.sendOscMessage(address, [value]);
    // Local echo
    final reg = OscRegistry();
    reg.registerAddress(address);
    reg.dispatchLocal(address, [value]);
  }

  void _handleDrag(Offset pos, {required bool isStart}) {
    const arcWidth = 6.0;
    const arcGap = 2.0;
    final totalSize = widget.size;
    final center = Offset(totalSize / 2, totalSize / 2);
    final offset = pos - center;
    final dist = offset.distance;
    final outerRadius = totalSize / 2;
    final innerRadius = outerRadius - arcWidth - arcGap;

    if (isStart) {
      _dragMode = dist > innerRadius ? 2 : 1;
    }

    if (_dragMode == 2) {
      // Arc mode — map angle to level (-1 to +1)
      const startAngle = 0.75 * pi;
      const sweepAngle = 1.5 * pi;

      var angle = atan2(offset.dy, offset.dx);
      var relAngle = angle - startAngle;
      while (relAngle < 0) relAngle += 2 * pi;
      while (relAngle >= 2 * pi) relAngle -= 2 * pi;

      if (relAngle > sweepAngle) {
        relAngle = relAngle < (sweepAngle + (2 * pi - sweepAngle) / 2)
            ? sweepAngle
            : 0;
      }

      final normalized = relAngle / sweepAngle;
      final level = (-1.0 + normalized * 2.0).clamp(-1.0, 1.0);

      setState(() => _level = level);
      _sendOsc(_levelAddr, _level);
    } else {
      // Wheel mode — map position to shift_x/shift_y (-1 to +1)
      final wheelRadius = innerRadius;
      var nx = offset.dx / wheelRadius;
      var ny = offset.dy / wheelRadius;

      // Clamp to circle
      final d = sqrt(nx * nx + ny * ny);
      if (d > 1.0) {
        nx /= d;
        ny /= d;
      }

      setState(() {
        _shiftX = nx.clamp(-1.0, 1.0);
        _shiftY = ny.clamp(-1.0, 1.0);
      });
      _sendOsc(_shiftXAddr, _shiftX);
      _sendOsc(_shiftYAddr, _shiftY);
    }
  }

  void _handleDragEnd() {
    setState(() => _dragMode = 0);
  }

  void _handleDoubleTap() {
    setState(() {
      _shiftX = 0.0;
      _shiftY = 0.0;
      _level = 0.0;
    });
    _sendOsc(_shiftXAddr, 0.0);
    _sendOsc(_shiftYAddr, 0.0);
    _sendOsc(_levelAddr, 0.0);
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
        painter: _GradeWheelPainter(
          shiftX: _shiftX,
          shiftY: _shiftY,
          level: _level,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _GradeWheelPainter
// ---------------------------------------------------------------------------
class _GradeWheelPainter extends CustomPainter {
  final double shiftX;
  final double shiftY;
  final double level;

  static const double arcWidth = 6.0;
  static const double arcGap = 2.0;
  static const double startAngle = 0.75 * pi;
  static const double sweepAngle = 1.5 * pi;

  _GradeWheelPainter({
    required this.shiftX,
    required this.shiftY,
    required this.level,
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

    // === BIPOLAR LEVEL ARC ===
    const Color activeColor = Color(0xFFF0B830);

    // level: -1 to +1, neutral at 0
    // Map to normalized: -1 -> 0, 0 -> 0.5, +1 -> 1
    final normalized = (level + 1.0) / 2.0;
    const neutralNormalized = 0.5;

    final neutralAngle = startAngle + neutralNormalized * sweepAngle;
    final valueAngle = startAngle + normalized * sweepAngle;
    final arcStartAngle = min(neutralAngle, valueAngle);
    final arcEndAngle = max(neutralAngle, valueAngle);
    final arcSweep = arcEndAngle - arcStartAngle;

    const minArcSweep = 0.10;
    var drawArcStart = arcStartAngle;
    var drawArcSweep = arcSweep;

    if (arcSweep < minArcSweep) {
      drawArcStart = valueAngle - minArcSweep / 2;
      drawArcSweep = minArcSweep;
    }

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
      drawArcStart, drawArcSweep, false,
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
      drawArcStart, drawArcSweep, false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = arcWidth - 2
        ..strokeCap = StrokeCap.butt
        ..shader = highlightGradient.createShader(
            Rect.fromCircle(center: center, radius: outerRadius)),
    );

    // === INNER OKLCH COLOR WHEEL (lightness driven by level arc) ===
    canvas.save();
    canvas.clipPath(
        Path()..addOval(Rect.fromCircle(center: center, radius: wheelRadius)));

    // Map level (-1..+1) to OKLCH lightness (0.1..0.9)
    final oklchLightness = 0.5 + level * 0.4;
    final wheelImage = _getGradeWheelImage(
        (wheelRadius * 2).round(), oklchLightness);
    final src = Rect.fromLTWH(0, 0,
        wheelImage.width.toDouble(), wheelImage.height.toDouble());
    final dst = Rect.fromCircle(center: center, radius: wheelRadius);
    canvas.drawImageRect(wheelImage, src, dst,
        Paint()..filterQuality = FilterQuality.high);

    canvas.restore();

    // === SELECTION INDICATOR ===
    final indicatorX = center.dx + shiftX * wheelRadius;
    final indicatorY = center.dy + shiftY * wheelRadius;
    final indicatorPos = Offset(indicatorX, indicatorY);
    const indicatorRadius = 5.0;

    canvas.drawCircle(
      indicatorPos,
      indicatorRadius + 1.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      indicatorPos,
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
  bool shouldRepaint(covariant _GradeWheelPainter old) =>
      old.shiftX != shiftX ||
      old.shiftY != shiftY ||
      old.level != level;
}

// ---------------------------------------------------------------------------
// GradeZone — Column: wheel + label + 2 knobs
// ---------------------------------------------------------------------------
class GradeZone extends StatelessWidget {
  final String label;
  final String zoneName; // 'shadows', 'midtones', 'highlights'
  final String basePath; // e.g. "/send/1/grade"

  const GradeZone({
    super.key,
    required this.label,
    required this.zoneName,
    required this.basePath,
  });

  void _resetZone(BuildContext context) {
    final network = context.read<Network>();
    final reg = OscRegistry();
    final zonePath = '$basePath/$zoneName';

    for (final param in ['shift_x', 'shift_y', 'level']) {
      network.sendOscMessage('$zonePath/$param', [0.0]);
      reg.dispatchLocal('$zonePath/$param', [0.0]);
    }
    for (final param in ['contrast', 'saturation']) {
      network.sendOscMessage('$zonePath/$param', [0.5]);
      reg.dispatchLocal('$zonePath/$param', [0.5]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: zoneName,
      child: NeumorphicInset(
        baseColor: const Color(0xFF252527),
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            // Reserve space for title (~22px), gaps (8px), knobs (~knobSize+16px)
            final knobSize = (w / 3).clamp(25.0, 50.0);
            // title ~24, gaps ~12, knob row ~(knobSize+20 for label), plus 8px buffer
            final reservedVertical = 24 + 12 + knobSize + 20 + 8;
            final maxWheelFromHeight = h.isFinite ? (h - reservedVertical).clamp(40.0, 300.0) : w;
            final wheelSize = w.clamp(40.0, maxWheelFromHeight);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          icon: const Icon(Icons.refresh, color: Color(0xFF888888)),
                          onPressed: () => _resetZone(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                GradeWheel(
                  basePath: '$basePath/$zoneName',
                  size: wheelSize,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: OscPathSegment(
                          segment: 'contrast',
                          child: OscRotaryKnob(
                            initialValue: 0.5,
                            minValue: 0.0,
                            maxValue: 1.0,
                            format: '%.2f',
                            label: 'Con',
                            defaultValue: 0.5,
                            size: knobSize,
                            snapConfig: SnapConfig(
                              snapPoints: const [0.5],
                              snapRegionHalfWidth: 0.02,
                              snapBehavior: SnapBehavior.hard,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: OscPathSegment(
                          segment: 'saturation',
                          child: OscRotaryKnob(
                            initialValue: 0.5,
                            minValue: 0.0,
                            maxValue: 1.0,
                            format: '%.2f',
                            label: 'Sat',
                            defaultValue: 0.5,
                            size: knobSize,
                            snapConfig: SnapConfig(
                              snapPoints: const [0.5],
                              snapRegionHalfWidth: 0.02,
                              snapBehavior: SnapBehavior.hard,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// GradeWheels — Row of 3 GradeZones
// ---------------------------------------------------------------------------
class GradeWheels extends StatelessWidget {
  final String basePath; // e.g. "/send/1/grade"

  const GradeWheels({
    super.key,
    required this.basePath,
  });

  @override
  Widget build(BuildContext context) {
    return OscPathSegment(
      segment: 'grade',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: GradeZone(label: 'Shadows', zoneName: 'shadows', basePath: basePath)),
          const SizedBox(width: 8),
          Expanded(child: GradeZone(label: 'Midtones', zoneName: 'midtones', basePath: basePath)),
          const SizedBox(width: 8),
          Expanded(child: GradeZone(label: 'Highlights', zoneName: 'highlights', basePath: basePath)),
        ],
      ),
    );
  }
}
