import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  ButtonStyle _iconButtonStyle(
      BuildContext context, {
      Color? borderColor,
      Color? foregroundColor,
  }) {
    final theme = Theme.of(context);
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.grey[600],
      foregroundColor: foregroundColor ?? theme.colorScheme.onPrimary,
      padding: const EdgeInsets.all(12),
      minimumSize: const Size(40, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(
          color: borderColor ?? theme.colorScheme.primary,
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Tooltip(
              message: 'Save',
              child: ElevatedButton(
                style: _iconButtonStyle(context,
                    borderColor: Theme.of(context).colorScheme.primary),
                onPressed: () => _save(context),
                child: const Icon(Icons.save),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Save As',
              child: ElevatedButton(
                style: _iconButtonStyle(context,
                    borderColor: Theme.of(context).colorScheme.primary),
                onPressed: () => _saveAs(context),
                child: const Icon(Icons.save_as),
              ),
            ),
            const SizedBox(width: 10),
            Tooltip(
              message: 'Load',
              child: ElevatedButton(
                style: _iconButtonStyle(context,
                    borderColor: Theme.of(context).colorScheme.primary),
                onPressed: () => _load(context),
                child: const Icon(Icons.folder_open),
              ),
            ),
            SizedBox(width: 16),
            Tooltip(
          message: 'Reset to defaults',
          child: ElevatedButton(
            style: _iconButtonStyle(
              context,
              borderColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor:
                  Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => _reset(context),
            child: const Icon(Icons.restore),
          ),
        ),
          ],
        ),
        
      ],
    );
  }
}
