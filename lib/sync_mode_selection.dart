
import 'package:flutter/material.dart';
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
    RangeValues pixel_clock_shift_range = RangeValues(-16, 17);
    List<double> pcsri = List.generate(
        (pixel_clock_shift_range.end - pixel_clock_shift_range.start).toInt(),
        (i) => (pixel_clock_shift_range.start.toInt() + i).toDouble());
    return LabeledCard( // TODO: This doesn't call setDefaultValue, so it doesn't go in the OscRegistry, so it isn't saved
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
              ),
        ],
      ),
    );
  }
}
