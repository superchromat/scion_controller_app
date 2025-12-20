// send_color.dart

import 'package:flutter/material.dart';
import 'lut_editor.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';

class SendColor extends StatefulWidget {
  const SendColor({super.key});

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
    return IntrinsicHeight(
      child: SizedBox(
        height: 400,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
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
            const SizedBox(width: 48),
            Expanded(
              child: Card(
                color: Colors.grey[900],
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OscPathSegment(
                    segment: 'lut',
                    child: LUTEditor(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
