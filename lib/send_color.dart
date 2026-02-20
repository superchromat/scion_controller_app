// send_color.dart

import 'package:flutter/material.dart';
import 'lut_editor.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'labeled_card.dart';
import 'grade_wheels.dart';
import 'grid.dart';

class SendColor extends StatefulWidget {
  final bool showGrade;
  final String? gradePath;

  const SendColor({super.key, this.showGrade = false, this.gradePath});

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final knobSize = (constraints.maxWidth * 0.75).clamp(30.0, 90.0);
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
                size: knobSize,
                snapConfig: SnapConfig(
                  snapPoints: snapPoints ?? [],
                  snapRegionHalfWidth: (maxValue - minValue) * 0.02,
                  snapBehavior: SnapBehavior.hard,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool showGrade = widget.showGrade;
    // Height scales with available width (35%) so the color section grows
    // proportionally as the window widens, clamped to a sensible range.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 0.45).clamp(400.0, 700.0);
        return SizedBox(
          height: height,
          child: _buildContent(showGrade),
        );
      },
    );
  }

  Widget _buildContent(bool showGrade) {
    return GridRow(
      columns: 12,
      cells: [
        (
          span: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NeumorphicInset(
                baseColor: const Color(0xFF252527),
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Global',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFAAAAAA),
                      ),
                    ),
                    const GridGap(fraction: 0.5),
                    Row(
                      children: [
                        Expanded(
                          child: _labeledKnob(
                            label: 'Brightness',
                            paramKey: 'brightness',
                            knobKey: _brightnessKey,
                            initialValue: _initialBrightness,
                            minValue: 0,
                            maxValue: 1,
                            snapPoints: const [0.0, 0.5, 1.0],
                            precision: 3,
                          ),
                        ),
                        Expanded(
                          child: _labeledKnob(
                            label: 'Contrast',
                            paramKey: 'contrast',
                            knobKey: _contrastKey,
                            initialValue: _initialContrast,
                            minValue: 0,
                            maxValue: 1,
                            snapPoints: const [0.0, 0.5, 1.0],
                            precision: 3,
                          ),
                        ),
                        Expanded(
                          child: _labeledKnob(
                            label: 'Saturation',
                            paramKey: 'saturation',
                            knobKey: _saturationKey,
                            initialValue: _initialSaturation,
                            minValue: 0,
                            maxValue: 1,
                            snapPoints: const [0.0, 0.5, 1.0],
                            precision: 3,
                          ),
                        ),
                        Expanded(
                          child: _labeledKnob(
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
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (showGrade) ...[
                const GridGap(fraction: 0.5),
                Expanded(
                  child: GradeWheels(basePath: widget.gradePath!),
                ),
              ],
            ],
          ),
        ),
        (
          span: 6,
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
    );
  }
}
