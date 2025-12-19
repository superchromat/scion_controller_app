// ignore_for_file: unused_field

import 'package:flutter/material.dart';
import 'osc_radiolist.dart';
import 'osc_checkbox.dart';
import 'numeric_slider.dart';
import 'labeled_card.dart';
import 'osc_widget_binding.dart';
import 'osc_registry.dart';

class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  _SyncSettingsSectionState createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection>
    with OscAddressMixin {
  String _selectedSync = 'locked';
  bool _dacGenlock = false;

  final List<List<String>> _syncOptions = [
    ['locked', 'Sync locked to sends'],
    ['component', 'Component sync (Y/G)'],
    ['external', 'External H/V sync input']
  ];

  @override
  void initState() {
    super.initState();
    // Listen to sync_mode changes
    OscRegistry().registerAddress('/sync_mode');
    OscRegistry().registerListener('/sync_mode', _onSyncModeChanged);
    // Listen to dac_genlock changes
    OscRegistry().registerAddress('/dac_genlock');
    OscRegistry().registerListener('/dac_genlock', _onDacGenlockChanged);
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener('/sync_mode', _onSyncModeChanged);
    OscRegistry().unregisterListener('/dac_genlock', _onDacGenlockChanged);
    super.dispose();
  }

  void _onSyncModeChanged(List<Object?> args) {
    if (args.isNotEmpty && args.first is String) {
      setState(() {
        _selectedSync = (args.first as String).toLowerCase();
      });
    }
  }

  void _onDacGenlockChanged(List<Object?> args) {
    if (args.isNotEmpty && args.first is bool) {
      setState(() {
        _dacGenlock = args.first as bool;
      });
    }
  }

  /// DAC genlock checkbox is only enabled when NOT in locked mode
  bool get _dacGenlockEnabled => _selectedSync != 'locked';

  @override
  Widget build(BuildContext context) {
    RangeValues pixelClockShiftRange = RangeValues(-20, 20);
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
          const SizedBox(height: 8),
          // DAC Genlock checkbox - disabled when in locked mode
          Opacity(
            opacity: _dacGenlockEnabled ? 1.0 : 0.5,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OscPathSegment(
                  segment: 'dac_genlock',
                  child: OscCheckbox(
                    initialValue: _dacGenlock,
                    readOnly: !_dacGenlockEnabled,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Genlock DAC to external source',
                  style: TextStyle(
                    fontSize: 13,
                    color: _dacGenlockEnabled ? null : Colors.grey,
                  ),
                ),
              ],
            ),
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
