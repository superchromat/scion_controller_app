import 'package:flutter/material.dart';

import 'grid.dart';
import 'system_overview.dart';
import 'video_format_selection.dart';
import 'sync_mode_selection.dart';

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
          // Provide real tokens as well as the legacy gutter: without a
          // GridProvider every card fell back to GridTokens(1200), so insets
          // stopped tracking the window and disagreed with the page gutter.
          final t = GridTokens(constraints.maxWidth);
          return GridProvider(
            tokens: t,
            child: GridGutterProvider(
              gutter: pageGutter,
              child: SingleChildScrollView(
                padding: t.pagePadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GridRow(cells: [(span: 12, child: SystemOverview())]),
                    SizedBox(height: t.panelGap),
                    GridRow(cells: [
                      (span: 7, child: VideoFormatSelectionSection()),
                      (span: 5, child: SyncSettingsSection()),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
