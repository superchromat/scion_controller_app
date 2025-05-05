import 'package:flutter/material.dart';

class SyncSettingsSection extends StatefulWidget {
  const SyncSettingsSection({super.key});

  @override
  _SyncSettingsSectionState createState() => _SyncSettingsSectionState();
}

class _SyncSettingsSectionState extends State<SyncSettingsSection> {
  String _selectedSync = 'Sync locked to sends';
  int _pixelOffset = 0;

  final List<String> _syncOptions = [
    'Sync locked to sends',
    'Component sync (Y/G)',
    'External H/V sync input',
  ];

  String _formatPixelOffset(int value) {
    final sign = value > 0 ? '+' : '';
    final unit = value.abs() == 1 ? 'pixel' : 'pixels';
    return '$sign$value $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Return Sync', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ..._syncOptions.map((option) => RadioListTile<String>(
                  title: Text(option,
                    style: Theme.of(context).textTheme.bodyMedium
                  ),
                  value: option,
                  groupValue: _selectedSync,
                  onChanged: (value) {
                    setState(() => _selectedSync = value!);
                  },
                )),
            const SizedBox(height: 16),
            Text('Pixel clock offset',
                style: Theme.of(context).textTheme.titleMedium),
            Slider(
              value: _pixelOffset.toDouble(),
              min: -16,
              max: 16,
              divisions: 32,
              label: _pixelOffset.toString(),
              onChanged: (value) {
                setState(() => _pixelOffset = value.round());
              },
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Text(_formatPixelOffset(_pixelOffset)),
            ),
          ],
        ),
      ),
    );
  }
}
