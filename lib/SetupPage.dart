import 'package:flutter/material.dart';

import 'FileSelection.dart';
import 'VideoFormatSelection.dart';
import 'NetworkSelection.dart';
import 'SyncModeSelection.dart';

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
                    Expanded(child: NetworkConnectionSection()),
                    const SizedBox(width: 24),
                    Expanded(child: FileManagementSection()),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 600, // Adjust width to fit your VideoFormat widget
                    child: VideoFormatSelectionSection(),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: SyncSettingsSection()),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}