import 'package:SCION_Controller/system_overview.dart';
import 'package:flutter/material.dart';

import 'grid.dart';
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final pageGutter = constraints.maxWidth * AppGrid.gutterFraction;
          return GridGutterProvider(
            gutter: pageGutter,
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pageGutter),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridRow(cells: [(span: 12, child: SystemOverview())]),
                  const GridGap(),
                  GridRow(cells: [
                    (span: 7, child: VideoFormatSelectionSection()),
                    (span: 5, child: SyncSettingsSection()),
                  ]),
                ],
              ),
            ),
          );
        },
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
