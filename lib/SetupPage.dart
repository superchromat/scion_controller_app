import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'VideoFormatSelection.dart';

import 'package:flutter/material.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: NetworkConnectionSection(),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: FileManagementSection(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const VideoFormatSelectionSection(),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------- Network Connection Section -----------------

class NetworkConnectionSection extends StatefulWidget {
  const NetworkConnectionSection({super.key});

  @override
  State<NetworkConnectionSection> createState() =>
      _NetworkConnectionSectionState();
}

class _NetworkConnectionSectionState extends State<NetworkConnectionSection> {
  final TextEditingController addressController = TextEditingController();
  final TextEditingController txPortController =
      TextEditingController(text: '8000');
  final TextEditingController rxPortController =
      TextEditingController(text: '9000');

  bool discovering = false;
  List<String> discoveredAddresses = [];

  void startDiscovery() {
    setState(() {
      discovering = true;
      discoveredAddresses = [];
    });

    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        discovering = false;
        discoveredAddresses = [
          '192.168.10.10',
          'device.local',
          '192.168.1.5',
        ];
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Connection',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(
                labelText: 'Network Address',
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: txPortController,
                    decoration: const InputDecoration(
                      labelText: 'Transmit Port',
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: rxPortController,
                    decoration: const InputDecoration(
                      labelText: 'Receive Port',
                    ),
                    style: const TextStyle(fontFamily: 'monospace'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.network_ping),
                  label: const Text('Connect'),
                  onPressed: () {},
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  icon: discovering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: const Text('Zeroconf'),
                  onPressed: discovering ? null : startDiscovery,
                ),
              ],
            ),
            if (discoveredAddresses.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButton<String>(
                isExpanded: true,
                value: discoveredAddresses.first,
                items: discoveredAddresses
                    .map((address) => DropdownMenuItem(
                          value: address,
                          child: Text(address),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      addressController.text = value;
                    });
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ----------------- File Management Section -----------------

class FileManagementSection extends StatelessWidget {
  const FileManagementSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File Management',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
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
                        // User selected a file path
                        print('Saving to $outputFile');
                        // TODO: Write your save logic here
                      } else {
                        print('Save As cancelled');
                      }
                    }),
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
                        // User selected a file path
                        print('Saving to $outputFile');
                        // TODO: Write your save logic here
                      } else {
                        print('Save As cancelled');
                      }
                    }),
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
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
