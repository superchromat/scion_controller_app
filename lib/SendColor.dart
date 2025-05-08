import 'package:flutter/material.dart';
import 'package:namer_app/LUTEditor.dart';
import 'package:namer_app/OscWidgetBinding.dart';

import 'NumericSlider.dart';

void colorChange(String key, double val) {
  // Callback stub
}

class SendColor extends StatelessWidget {
  final void Function(String key, double value) onParamChanged = colorChange;

  const SendColor({super.key});

  Widget _labeledSlider({
    required String label,
    required String key,
    required double value,
    required RangeValues range,
    List<double>? detents,
    required int precision,
  }) {
    final sliderKey = GlobalKey<NumericSliderState>();
    final initialValue = value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: OscPathSegment(
            segment: label.toLowerCase(),
            child: NumericSlider(
              key: sliderKey,
              value: value,
              range: range,
              detents: detents,
              precision: precision,
              onChanged: (v) => onParamChanged(key, v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            sliderKey.currentState?.setValue(initialValue, immediate: true);
            onParamChanged(key, initialValue);
          },
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  Widget _rowWithHeight(
      {required Widget child, double height = 25, double padding = 4}) {
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
          crossAxisAlignment: CrossAxisAlignment.start, // aligns column to top
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _rowWithHeight(
                    child: _labeledSlider(
                        label: "Brightness",
                        key: "brightness",
                        value: 0.5,
                        range: const RangeValues(0, 1),
                        detents: const [0.0, 0.5, 1.0],
                        precision: 3)),
                _rowWithHeight(
                    child: _labeledSlider(
                        label: "Contrast",
                        key: "contrast",
                        value: 0.5,
                        range: const RangeValues(0, 1),
                        detents: const [0.0, 0.5, 1.0],
                        precision: 3)),
                _rowWithHeight(
                    child: _labeledSlider(
                        label: "Saturation",
                        key: "saturation",
                        value: 0.5,
                        range: const RangeValues(0, 1),
                        detents: const [0.0, 0.5, 1.0],
                        precision: 3)),
                _rowWithHeight(
                    child: _labeledSlider(
                        label: "Hue",
                        key: "hue",
                        value: 0.0,
                        range: const RangeValues(-180, 180),
                        detents: const [0.0],
                        precision: 3)),
              ],
            ),
            SizedBox(width: 48),
            Expanded(
              child: Card(
                color: Colors.grey[900],
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: OscPathSegment(segment: "lut", child: LUTEditor())
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
