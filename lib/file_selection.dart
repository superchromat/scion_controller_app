import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'labeled_card.dart';
import 'osc_widget_binding.dart'; // provides OscRegistry

final GlobalKey<FileManagementSectionState> fileManagementKey = GlobalKey<FileManagementSectionState>();

/// Stateful widget to manage config file I/O and currentFile state.
class FileManagementSection extends StatefulWidget {
  const FileManagementSection({super.key});

  @override
  State<FileManagementSection> createState() => FileManagementSectionState();
}

class FileManagementSectionState extends State<FileManagementSection> {
  String? _currentFile;

  Future<void> _save(BuildContext context) async {
    // If no currentFile, prompt "Save As"
    final path = _currentFile ?? await FilePicker.platform.saveFile(
      dialogTitle: 'Save Configuration',
      fileName: 'default.config',
    );
    if (path == null) return;

    await OscRegistry().saveToFile(path);
    setState(() => _currentFile = path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Configuration saved to $path')),
    );
  }

  Future<void> _saveAs(BuildContext context) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save As',
      fileName: 'default.config',
    );
    if (path == null) return;

    await OscRegistry().saveToFile(path);
    setState(() => _currentFile = path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Configuration saved to $path')),
    );
  }

  Future<void> _load(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Load Configuration',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path == null) return;

    await OscRegistry().loadFromFile(path);
    setState(() => _currentFile = path);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Configuration loaded from $path')),
    );
  }

  void _reset(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: const Text('Are you sure you want to restore all settings?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              OscRegistry().resetToDefaults(null);
              Navigator.of(ctx).pop();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

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
                onPressed: () => _save(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_as),
                label: const Text('Save As'),
                onPressed: () => _saveAs(context),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Load'),
                onPressed: () => _load(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('Reset to defaults'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => _reset(context),
          ),
        ],
      ),
    );
  }
}
