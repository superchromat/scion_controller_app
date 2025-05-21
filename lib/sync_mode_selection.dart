// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'osc_radiolist.dart';
import 'numeric_slider.dart';
import 'labeled_card.dart';
import 'osc_widget_binding.dart';

class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  _SyncSettingsSectionState createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection>
    with OscAddressMixin {
  String _selectedSync = 'locked';

  final List<List<String>> _syncOptions = [
    ['locked', 'Sync locked to sends'],
    ['component', 'Component sync (Y/G)'],
    ['external', 'External H/V sync input']
  ];

  @override
  Widget build(BuildContext context) {
    RangeValues pixelClockShiftRange = RangeValues(-16, 17);
    List<double> pcsri = List.generate(
        (pixelClockShiftRange.end - pixelClockShiftRange.start).toInt(),
        (i) => (pixelClockShiftRange.start.toInt() + i).toDouble());

    return LabeledCard(
      title: 'Return Sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            OscPathSegment(
        segment: 'sync_mode',
        child: OscRadioList(options: _syncOptions),
      ),
          const SizedBox(height: 16),
          Text('Pixel clock offset',
              style: Theme.of(context).textTheme.titleMedium),
          OscPathSegment(
              segment: 'clock_offset',
              child: SizedBox(
                  width: 80,
                  height: 24,
                  child: NumericSlider(
                    value: 0,
                    onChanged: (_) {},
                    range: pixelClockShiftRange,
                    detents: pcsri,
                    hardDetents: true,
                    precision: 0,
                  ))),
        ],
      ),
    );
  }
}
