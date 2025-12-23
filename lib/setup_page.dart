import 'package:SCION_Controller/system_overview.dart';
import 'package:flutter/material.dart';

import 'video_format_selection.dart';
import 'sync_mode_selection.dart';
import 'firmware_update.dart';

/// System page - contains system overview, video format, and sync settings
class SystemPage extends StatefulWidget {
  const SystemPage({super.key});

  @override
  State<SystemPage> createState() => _SystemPageState();
}

class _SystemPageState extends State<SystemPage> {
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
                  child: SizedBox(
                      height: TileLayout.computeCardHeight(),
                      child: SystemOverview())),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: VideoFormatSelectionSection()),
                    SizedBox(
                      width: 400,
                      child: SyncSettingsSection(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Setup page - contains firmware update
class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: const Padding(
        padding: EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: FirmwareUpdateSection(),
        ),
      ),
    );
  }
}
