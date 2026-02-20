// send_color.dart

import 'package:flutter/material.dart';
import 'lut_editor.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'labeled_card.dart';
import 'grade_wheels.dart';

class SendColor extends StatefulWidget {
  final int pageNumber;

  const SendColor({super.key, required this.pageNumber});

  @override
  _SendColorState createState() => _SendColorState();
}

class _SendColorState extends State<SendColor> {
  // Keys for each knob to preserve state
  final _brightnessKey = GlobalKey<OscRotaryKnobState>();
  final _contrastKey   = GlobalKey<OscRotaryKnobState>();
  final _saturationKey = GlobalKey<OscRotaryKnobState>();
  final _hueKey        = GlobalKey<OscRotaryKnobState>();

  // Initial values for reset
  static const double _initialBrightness = 0.5;
  static const double _initialContrast   = 0.5;
  static const double _initialSaturation = 0.5;
  static const double _initialHue        = 0.0;

  Widget _labeledKnob({
    required String label,
    required String paramKey,
    required GlobalKey<OscRotaryKnobState> knobKey,
    required double initialValue,
    required double minValue,
    required double maxValue,
    List<double>? snapPoints,
    required int precision,
    bool isBipolar = false,
  }) {
    final format = '%.${precision}f';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OscPathSegment(
          segment: paramKey,
          child: OscRotaryKnob(
            key: knobKey,
            initialValue: initialValue,
            minValue: minValue,
            maxValue: maxValue,
            format: format,
            label: label,
            defaultValue: initialValue,
            isBipolar: isBipolar,
            size: 70,
            snapConfig: SnapConfig(
              snapPoints: snapPoints ?? [],
              snapRegionHalfWidth: (maxValue - minValue) * 0.02,
              snapBehavior: SnapBehavior.hard,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showGrade = widget.pageNumber <= 2;
    return SizedBox(
      height: 400,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: global knobs + grade wheels stacked vertically
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeumorphicInset(
                baseColor: const Color(0xFF252527),
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 16,
                  children: [
                    _labeledKnob(
                      label: 'Brightness',
                      paramKey: 'brightness',
                      knobKey: _brightnessKey,
                      initialValue: _initialBrightness,
                      minValue: 0,
                      maxValue: 1,
                      snapPoints: const [0.0, 0.5, 1.0],
                      precision: 3,
                    ),
                    _labeledKnob(
                      label: 'Contrast',
                      paramKey: 'contrast',
                      knobKey: _contrastKey,
                      initialValue: _initialContrast,
                      minValue: 0,
                      maxValue: 1,
                      snapPoints: const [0.0, 0.5, 1.0],
                      precision: 3,
                    ),
                    _labeledKnob(
                      label: 'Saturation',
                      paramKey: 'saturation',
                      knobKey: _saturationKey,
                      initialValue: _initialSaturation,
                      minValue: 0,
                      maxValue: 1,
                      snapPoints: const [0.0, 0.5, 1.0],
                      precision: 3,
                    ),
                    _labeledKnob(
                      label: 'Hue',
                      paramKey: 'hue',
                      knobKey: _hueKey,
                      initialValue: _initialHue,
                      minValue: -180,
                      maxValue: 180,
                      snapPoints: const [0.0],
                      precision: 1,
                      isBipolar: true,
                    ),
                  ],
                ),
              ),
              if (showGrade) ...[
                const SizedBox(height: 12),
                GradeWheels(basePath: '/send/${widget.pageNumber}/grade'),
              ],
            ],
          ),
          const SizedBox(width: 16),
          // Right column: LUT curve editor
          Expanded(
            child: NeumorphicInset(
              baseColor: const Color(0xFF252527),
              padding: const EdgeInsets.all(16),
              child: OscPathSegment(
                segment: 'lut',
                child: LUTEditor(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
