// send_color.dart

import 'package:flutter/material.dart';
import 'lut_editor.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'grade_wheels.dart';
import 'grid.dart';
import 'panel.dart';
import 'labeled_card.dart';

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
    final t = GridProvider.of(context);
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
            labelStyle: t.textLabel,
            size: t.knobLg,
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
    final t = GridProvider.of(context);
    final bool showGrade = widget.showGrade;
    // Height scales with available width so the color section grows
    // proportionally as the window widens, clamped to a sensible range.
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth * 0.45).clamp(400.0, 700.0);
        return SizedBox(
          height: height,
          child: _buildContent(showGrade, t),
        );
      },
    );
  }

  Widget _buildContent(bool showGrade, GridTokens t) {
    return GridRow(
      columns: 12,
      gutter: t.md,
      cells: [
        (
          span: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                title: 'Global',
                child: Row(
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
              ),
              if (showGrade) ...[
                SizedBox(height: t.md),
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
            padding: t.panelPadding,
            child: OscPathSegment(
              segment: 'lut',
              child: LUTEditor(
                gradePath: showGrade ? widget.gradePath : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
