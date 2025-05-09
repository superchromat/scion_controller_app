import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'LabeledCard.dart'; // Ensure this import is added

class FileManagementSection extends StatelessWidget {
  const FileManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      title: 'Configuration',
      networkIndependent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('Save'),
                onPressed: () async {
                  String? outputFile = await FilePicker.platform.saveFile(
                    dialogTitle: 'Save As',
                    fileName: 'default.config',
                  );
                  if (outputFile != null) {
                    print('Saving to $outputFile');
                  }
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_as),
                label: const Text('Save As'),
                onPressed: () async {
                  String? outputFile = await FilePicker.platform.saveFile(
                    dialogTitle: 'Save As',
                    fileName: 'default.config',
                  );
                  if (outputFile != null) {
                    print('Saving to $outputFile');
                  }
                },
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Load'),
                onPressed: () {},
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('Restore All Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Restore'),
                  content: const Text(
                      'Are you sure you want to restore all settings?'),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('Confirm'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
