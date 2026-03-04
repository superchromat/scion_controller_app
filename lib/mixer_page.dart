import 'package:flutter/material.dart';

import 'grid.dart';
import 'labeled_card.dart';
import 'panel.dart';
import 'send_source_selector.dart';

class MixerPage extends StatelessWidget {
  const MixerPage({super.key});

  static const List<int> _sources = [1, 2, 3, 4];

  static String _sourceLabel(int sourceSend) {
    if (sourceSend == 4) return 'Return';
    return 'Send $sourceSend';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = GridTokens(constraints.maxWidth);
        return GridProvider(
          tokens: t,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(t.md),
            child: LabeledCard(
              title: 'Mixer',
              child: _MixerMatrix(tokens: t),
            ),
          ),
        );
      },
    );
  }
}

class _MixerMatrix extends StatelessWidget {
  final GridTokens tokens;

  const _MixerMatrix({required this.tokens});

  @override
  Widget build(BuildContext context) {
    final headerStyle = tokens.textLabel.copyWith(
      color: const Color(0xFFE1E1E3),
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridRow(
          gutter: tokens.md,
          cells: [
            (
              span: 12,
              child: Row(
                children: [
                  for (final sourceSend in MixerPage._sources)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: tokens.xs),
                        child: Center(
                          child: Text(
                            MixerPage._sourceLabel(sourceSend),
                            style: headerStyle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.sm),
        for (int targetSend = 1; targetSend <= 3; targetSend++) ...[
          GridRow(
            gutter: tokens.md,
            cells: [
              (
                span: 12,
                child: Panel.dark(
                  title: 'Send $targetSend',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < MixerPage._sources.length; i++) ...[
                        if (i > 0) SizedBox(width: tokens.xs * 2),
                        Expanded(
                          child: _MixerCell(
                            targetSend: targetSend,
                            sourceSend: MixerPage._sources[i],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (targetSend < 3) SizedBox(height: tokens.md),
        ],
      ],
    );
  }
}

class _MixerCell extends StatelessWidget {
  final int targetSend;
  final int sourceSend;

  const _MixerCell({
    required this.targetSend,
    required this.sourceSend,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return Padding(
      padding: EdgeInsets.all(t.xs),
      child: SendOverlayCompactControls(
        pageNumber: targetSend,
        sourceSend: sourceSend,
      ),
    );
  }
}
