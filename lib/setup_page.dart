import 'package:SCION_Controller/system_overview.dart';
import 'package:flutter/material.dart';

import 'video_format_selection.dart';
import 'sync_mode_selection.dart';
import 'firmware_update.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            children: [
              IntrinsicHeight(
                  child: SizedBox(height: 490, child: SystemOverview())),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment
                      .start, // or stretch, depending on your intent
                  children: [
                    Expanded(child: VideoFormatSelectionSection()),
                    SizedBox(
                      width: 400,
                      child: SyncSettingsSection(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const FirmwareUpdateSection(),
            ],
          ),
        ),
      ),
    );
  }
}
