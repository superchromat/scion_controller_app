import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'numeric_slider.dart';
import 'osc_checkbox.dart';
import 'osc_dropdown.dart';
import 'osc_widget_binding.dart';

class KeyPage extends StatelessWidget {
  const KeyPage({super.key});

  Widget _buildToggleRow(String label) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        const SizedBox(width: 12),
        OscPathSegment(
          segment: 'enabled',
          child: const OscCheckbox(),
        ),
      ],
    );
  }

  Widget _buildDropdownRow({
    required String title,
    required String pathSegment,
    required int defaultValue,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OscDropdown<int>(
        label: title,
        items: const [1, 2, 3],
        defaultValue: defaultValue,
        pathSegment: pathSegment,
        displayLabel: title,
      ),
    );
  }

  Widget _buildSliderRow({
    required String label,
    required String pathSegment,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: SizedBox(
              height: 32,
              child: OscPathSegment(
                segment: pathSegment,
                child: NumericSlider(
                  value: 0.0,
                  range: const RangeValues(0, 1),
                  detents: const [0.0, 0.5, 1.0],
                  precision: 3,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: OscPathSegment(
        segment: 'key',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledCard(
              title: 'Key Engine',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildToggleRow('Enabled'),
                  const SizedBox(height: 16),
                  _buildDropdownRow(
                    title: 'Primary Input',
                    pathSegment: 'source/primary',
                    defaultValue: 1,
                  ),
                  _buildDropdownRow(
                    title: 'Secondary Input',
                    pathSegment: 'source/secondary',
                    defaultValue: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildSliderRow(
                    label: 'Blend Level',
                    pathSegment: 'blend/level',
                  ),
                  _buildSliderRow(
                    label: 'Blend Softness',
                    pathSegment: 'blend/softness',
                  ),
                  _buildSliderRow(
                    label: 'Fade to Black',
                    pathSegment: 'fade_to_black',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
