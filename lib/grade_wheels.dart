// grade_wheels.dart — Per-zone color grading wheels (shadows/midtones/highlights)
// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'grid.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'oklch_color_picker.dart';
import 'color_wheel_arc.dart';
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
  final _wheelKey = GlobalKey<ColorWheelArcState>();

  String get _shiftXAddr => '${widget.basePath}/shift_x';
  String get _shiftYAddr => '${widget.basePath}/shift_y';
  // Arc controls lift, not level/upper.
  String get _levelAddr => '${widget.basePath}/lift';

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
      final v = (args.first as num).toDouble();
      _wheelKey.currentState?.setWheelPosition(
        v, _wheelKey.currentState?.wheelY ?? 0.0);
    }
  }

  void _onShiftY(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      final v = (args.first as num).toDouble();
      _wheelKey.currentState?.setWheelPosition(
        _wheelKey.currentState?.wheelX ?? 0.0, v);
    }
  }

  void _onLevel(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      final level = (args.first as num).toDouble();
      _wheelKey.currentState?.setArcValue((level + 1.0) / 2.0);
    }
  }

  void _sendOsc(String address, double value) {
    final network = context.read<Network>();
    network.sendOscMessage(address, [value]);
    final reg = OscRegistry();
    reg.registerAddress(address);
    reg.dispatchLocal(address, [value]);
  }

  @override
  Widget build(BuildContext context) {
    return ColorWheelArc(
      key: _wheelKey,
      size: widget.size,
      initialArcValue: 0.5, // level 0 = center
      onWheelChanged: (pos) {
        _sendOsc(_shiftXAddr, pos.x);
        _sendOsc(_shiftYAddr, pos.y);
      },
      onArcChanged: (value) {
        final level = (-1.0 + value * 2.0).clamp(-1.0, 1.0);
        _sendOsc(_levelAddr, level);
      },
      onDoubleTap: () {
        _sendOsc(_shiftXAddr, 0.0);
        _sendOsc(_shiftYAddr, 0.0);
        _sendOsc(_levelAddr, 0.0);
      },
      painterBuilder: ({
        required wheelX,
        required wheelY,
        required arcValue,
        required wheelRadius,
        required center,
      }) => _GradeWheelPainter(
        shiftX: wheelX,
        shiftY: wheelY,
        level: (-1.0 + arcValue * 2.0).clamp(-1.0, 1.0),
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

  _GradeWheelPainter({
    required this.shiftX,
    required this.shiftY,
    required this.level,
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

    // Bipolar: level -1..+1 → normalized 0..1
    final normalized = (level + 1.0) / 2.0;
    paintBipolarArc(canvas, center, arcRadius, outerRadius, normalized,
        const Color(0xFFF0B830));

    // Grade wheel image
    final oklchLightness = 0.5 + level * 0.4;
    final wheelImage = _getGradeWheelImage(
        (wheelRadius * 2).round(), oklchLightness);
    paintWheelImage(canvas, center, wheelRadius, wheelImage);

    paintWheelIndicator(
        canvas, center, Offset(shiftX, shiftY), wheelRadius);
    paintCrosshair(canvas, center, wheelRadius);
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

  TextStyle _headingStyle(GridTokens t) {
    final base = t.textHeading;
    final size = (base.fontSize ?? 14).clamp(12.0, 16.0);
    return base.copyWith(fontSize: size);
  }

  void _resetZone(BuildContext context) {
    final network = context.read<Network>();
    final reg = OscRegistry();
    final zonePath = '$basePath/$zoneName';

    for (final param in ['shift_x', 'shift_y', 'lift']) {
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
    final t = GridProvider.of(context);
    final headingStyle = _headingStyle(t);
    return OscPathSegment(
      segment: zoneName,
      child: NeumorphicInset(
        baseColor: const Color(0xFF252527),
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final titleH = 24.0;
            final gap = 4.0;
            final knobSize = w * 0.5;
            final knobH = knobSize + 16;
            final diagH = knobH * 1.5;
            // Wheel gets remaining height
            final wheelSize = h.isFinite
                ? (h - titleH - gap - diagH).clamp(40.0, w)
                : w;
            return Column(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      label,
                      style: headingStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          iconSize: 14,
                          icon: Icon(Icons.refresh, color: t.textCaption.color),
                          onPressed: () => _resetZone(context),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap),
                Center(
                  child: GradeWheel(
                    basePath: '$basePath/$zoneName',
                    size: wheelSize,
                  ),
                ),
                const Spacer(),
                // Diagonal knob area: Con top-left, Sat bottom-right
                SizedBox(
                  width: w,
                  height: diagH,
                  child: Stack(
                    children: [
                      Positioned(
                        top: 0,
                        left: 0,
                        child: OscPathSegment(
                          segment: 'contrast',
                          child: OscRotaryKnob(
                            initialValue: 0.5,
                            minValue: 0.0,
                            maxValue: 1.0,
                            format: '%.2f',
                            label: 'Contrast',
                            defaultValue: 0.5,
                            size: knobSize,
                            labelStyle: GridProvider.maybeOf(context)?.textLabel,
                            snapConfig: SnapConfig(
                              snapPoints: const [0.5],
                              snapRegionHalfWidth: 0.02,
                              snapBehavior: SnapBehavior.hard,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: OscPathSegment(
                          segment: 'saturation',
                          child: OscRotaryKnob(
                            initialValue: 0.5,
                            minValue: 0.0,
                            maxValue: 1.0,
                            format: '%.2f',
                            label: 'Saturation',
                            defaultValue: 0.5,
                            size: knobSize,
                            labelStyle: GridProvider.maybeOf(context)?.textLabel,
                            snapConfig: SnapConfig(
                              snapPoints: const [0.5],
                              snapRegionHalfWidth: 0.02,
                              snapBehavior: SnapBehavior.hard,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
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
