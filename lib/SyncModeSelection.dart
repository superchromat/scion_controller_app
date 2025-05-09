import 'dart:math';

import 'package:flutter/material.dart';
import 'package:namer_app/NumericSlider.dart';
import 'LabeledCard.dart';
import 'OscWidgetBinding.dart';

class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  _SyncSettingsSectionState createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection>
    with OscAddressMixin {
  String _selectedSync = 'locked';
  int _pixelOffset = 0;

  final List<List<String>> _syncOptions = [
    ['locked', 'Sync locked to sends'],
    ['component', 'Component sync (Y/G)'],
    ['external', 'External H/V sync input']
  ];

  String _formatPixelOffset(int value) {
    final sign = value > 0 ? '+' : '';
    final unit = value.abs() == 1 ? 'pixel' : 'pixels';
    return '$sign$value $unit';
  }

  @override
  Widget build(BuildContext context) {
    RangeValues pixel_clock_shift_range = RangeValues(-16, 17);
    List<double> pcsri = List.generate(
        (pixel_clock_shift_range.end - pixel_clock_shift_range.start).toInt(),
        (i) => (pixel_clock_shift_range.start.toInt() + i).toDouble());
    return LabeledCard(
      title: 'Return Sync',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._syncOptions.map((option_pair) => SizedBox(
                width: double.infinity,
                child: OscPathSegment(
                  segment: 'sync_mode',
                  child: Builder(builder: (radioContext) {
                    return RadioListTile<String>(
                      title: Text(option_pair[1],
                          style: Theme.of(context).textTheme.bodyMedium),
                      value: option_pair[0],
                      groupValue: _selectedSync,
                      onChanged: (value) {
                        setState(() => _selectedSync = value!);
                        if (value != null) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            sendOscFromContext(radioContext, value);
                          });
                        }
                      },
                    );
                  }),
                ),
              )),
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
                      range: pixel_clock_shift_range,
                      detents: pcsri,
                      hardDetents: true,
                      precision: 0,))
              /*
            child: Builder(builder: (sliderContext) {
              return Slider(
                value: _pixelOffset.toDouble(),
                min: -16,
                max: 16,
                divisions: 32,
                label: _pixelOffset.toString(),
                onChanged: (value) {
                  setState(() => _pixelOffset = value.round());
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    sendOscFromContext(sliderContext, value);
                  });
                },
              );}),
            ),
              */
              ),
        ],
      ),
    );
  }
}
