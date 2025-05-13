// send_color.dart

import 'package:flutter/material.dart';
import 'lut_editor.dart';
import 'osc_widget_binding.dart';
import 'numeric_slider.dart';

class SendColor extends StatefulWidget {
  const SendColor({super.key});

  @override
  _SendColorState createState() => _SendColorState();
}

class _SendColorState extends State<SendColor> {
  // Keys for each slider to preserve state
  final _brightnessKey = GlobalKey<NumericSliderState>();
  final _contrastKey   = GlobalKey<NumericSliderState>();
  final _saturationKey = GlobalKey<NumericSliderState>();
  final _hueKey        = GlobalKey<NumericSliderState>();

  // Initial values for reset
  static const double _initialBrightness = 0.5;
  static const double _initialContrast   = 0.5;
  static const double _initialSaturation = 0.5;
  static const double _initialHue        = 0.0;

  Widget _labeledSlider({
    required String label,
    required String paramKey,
    required GlobalKey<NumericSliderState> sliderKey,
    required double initialValue,
    required RangeValues range,
    List<double>? detents,
    required int precision,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: OscPathSegment(
            segment: paramKey,
            child: NumericSlider(
              key: sliderKey,
              value: initialValue,
              range: range,
              detents: detents,
              precision: precision,
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            sliderKey.currentState
                ?.setValue(initialValue, immediate: true);
          },
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  Widget _rowWithHeight({required Widget child, double height = 25, double padding = 4}) {
    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: padding),
        child: Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _rowWithHeight(
                  child: _labeledSlider(
                    label: 'Brightness',
                    paramKey: 'brightness',
                    sliderKey: _brightnessKey,
                    initialValue: _initialBrightness,
                    range: const RangeValues(0, 1),
                    detents: const [0.0, 0.5, 1.0],
                    precision: 3,
                  ),
                ),
                _rowWithHeight(
                  child: _labeledSlider(
                    label: 'Contrast',
                    paramKey: 'contrast',
                    sliderKey: _contrastKey,
                    initialValue: _initialContrast,
                    range: const RangeValues(0, 1),
                    detents: const [0.0, 0.5, 1.0],
                    precision: 3,
                  ),
                ),
                _rowWithHeight(
                  child: _labeledSlider(
                    label: 'Saturation',
                    paramKey: 'saturation',
                    sliderKey: _saturationKey,
                    initialValue: _initialSaturation,
                    range: const RangeValues(0, 1),
                    detents: const [0.0, 0.5, 1.0],
                    precision: 3,
                  ),
                ),
                _rowWithHeight(
                  child: _labeledSlider(
                    label: 'Hue',
                    paramKey: 'hue',
                    sliderKey: _hueKey,
                    initialValue: _initialHue,
                    range: const RangeValues(-180, 180),
                    detents: const [0.0],
                    precision: 3,
                  ),
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
