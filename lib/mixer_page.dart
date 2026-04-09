import 'package:flutter/material.dart';

import 'grid.dart';
import 'labeled_card.dart';
import 'neumorphic_slider.dart';
import 'panel.dart';
import 'send_source_selector.dart';

/// A/B crossfade group assignment.
enum ABGroup { none, a, b }

class MixerPage extends StatelessWidget {
  const MixerPage({super.key});

  static const List<int> sources = [1, 2, 3, 4];

  static String sourceLabel(int sourceSend) {
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

class _MixerMatrix extends StatefulWidget {
  final GridTokens tokens;

  const _MixerMatrix({required this.tokens});

  @override
  State<_MixerMatrix> createState() => _MixerMatrixState();
}

class _MixerMatrixState extends State<_MixerMatrix> {
  // Per-row A/B state: row index (0-2) -> { sourceSend -> group }
  final List<Map<int, ABGroup>> _groups = [
    for (var _ in List.filled(3, null)) {for (var s in MixerPage.sources) s: ABGroup.none},
  ];

  // Per-row crossfade position: 0.0 = A, 1.0 = B
  final List<double> _crossfade = [0.5, 0.5, 0.5];

  double _weightFor(int row, int sourceSend) {
    switch (_groups[row][sourceSend]!) {
      case ABGroup.a:
        return 1.0 - _crossfade[row];
      case ABGroup.b:
        return _crossfade[row];
      case ABGroup.none:
        return 1.0;
    }
  }

  void _setGroup(int row, int sourceSend, ABGroup group) {
    setState(() {
      final current = _groups[row][sourceSend]!;
      // Toggle off if tapping the active group
      _groups[row][sourceSend] = (current == group) ? ABGroup.none : group;
    });
  }

  void _setCrossfade(int row, double value) {
    setState(() => _crossfade[row] = value);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final headerStyle = t.textLabel.copyWith(
      color: const Color(0xFFE1E1E3),
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Column headers
        GridRow(
          gutter: t.md,
          cells: [
            (
              span: 12,
              child: Row(
                children: [
                  for (final source in MixerPage.sources)
                    Expanded(
                      child: Center(
                        child: Text(
                          MixerPage.sourceLabel(source),
                          style: headerStyle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: t.sm),
        for (int targetSend = 1; targetSend <= 3; targetSend++) ...[
          _MixerRow(
            targetSend: targetSend,
            groups: _groups[targetSend - 1],
            crossfade: _crossfade[targetSend - 1],
            weightFor: (source) => _weightFor(targetSend - 1, source),
            onGroupChanged: (source, group) => _setGroup(targetSend - 1, source, group),
            onCrossfadeChanged: (value) => _setCrossfade(targetSend - 1, value),
          ),
          if (targetSend < 3) SizedBox(height: t.md),
        ],
      ],
    );
  }
}

class _MixerRow extends StatelessWidget {
  final int targetSend;
  final Map<int, ABGroup> groups;
  final double crossfade;
  final double Function(int source) weightFor;
  final void Function(int source, ABGroup group) onGroupChanged;
  final ValueChanged<double> onCrossfadeChanged;

  const _MixerRow({
    required this.targetSend,
    required this.groups,
    required this.crossfade,
    required this.weightFor,
    required this.onGroupChanged,
    required this.onCrossfadeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return GridRow(
      gutter: t.md,
      cells: [
        (
          span: 12,
          child: Panel.dark(
            title: 'Send $targetSend',
            child: Column(
              children: [
                // Cell row — IntrinsicHeight + stretch so all cells
                // match the tallest, then A/B buttons align at bottom.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < MixerPage.sources.length; i++) ...[
                        if (i > 0) SizedBox(width: t.xs),
                        Expanded(
                          child: _MixerCell(
                            targetSend: targetSend,
                            sourceSend: MixerPage.sources[i],
                            group: groups[MixerPage.sources[i]]!,
                            alphaWeight: weightFor(MixerPage.sources[i]),
                            onGroupChanged: (g) => onGroupChanged(MixerPage.sources[i], g),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Crossfader — always visible
                SizedBox(height: t.sm),
                _Crossfader(
                  value: crossfade,
                  onChanged: onCrossfadeChanged,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A/B toggle buttons for a single mixer cell.
class _ABToggle extends StatelessWidget {
  final ABGroup group;
  final ValueChanged<ABGroup> onChanged;

  const _ABToggle({required this.group, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final btnStyle = t.textCaption.copyWith(fontWeight: FontWeight.w700);
    const aColor = Color(0xFF5B8DEF); // blue
    const bColor = Color(0xFFEF7B5B); // orange

    Widget btn(String label, ABGroup target, Color color) {
      final active = group == target;
      return GestureDetector(
        onTap: () => onChanged(target),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.5),
          decoration: BoxDecoration(
            color: active ? color : const Color(0xFF2A2A2C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? color : Colors.grey[700]!,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: btnStyle.copyWith(
              color: active ? Colors.white : Colors.grey[500],
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn('A', ABGroup.a, aColor),
        SizedBox(width: t.xs),
        btn('B', ABGroup.b, bColor),
      ],
    );
  }
}

/// Horizontal A/B crossfader with labels.
class _Crossfader extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _Crossfader({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    const aColor = Color(0xFF5B8DEF);
    const bColor = Color(0xFFEF7B5B);
    final labelStyle = t.textLabel.copyWith(fontWeight: FontWeight.w700, fontSize: t.u * 1.4);

    return Row(
      children: [
        Text('A', style: labelStyle.copyWith(color: aColor)),
        SizedBox(width: t.sm),
        Expanded(
          child: NeumorphicSlider(
            axis: SliderAxis.horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            value: value,
            defaultValue: 0.5,
            label: '',
            format: '',
            trackWidth: 14,
            thumbLength: 36,
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: t.sm),
        Text('B', style: labelStyle.copyWith(color: bColor)),
      ],
    );
  }
}

class _MixerCell extends StatelessWidget {
  final int targetSend;
  final int sourceSend;
  final ABGroup group;
  final double alphaWeight;
  final ValueChanged<ABGroup> onGroupChanged;

  const _MixerCell({
    required this.targetSend,
    required this.sourceSend,
    required this.group,
    required this.alphaWeight,
    required this.onGroupChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final isIdentity = sourceSend == targetSend;

    // Column stretches to row height (via IntrinsicHeight + stretch).
    // Expanded pushes A/B buttons to the bottom.
    return Column(
      children: [
        // Cell content fills available space
        Expanded(
          child: isIdentity
              ? SendSourceSelector2x2(pageNumber: targetSend)
              : SendOverlayCompactControls(
                  pageNumber: targetSend,
                  sourceSend: sourceSend,
                  alphaWeight: alphaWeight,
                  crossfadeActive: group != ABGroup.none,
                ),
        ),
        SizedBox(height: t.xs),
        // A/B toggle pinned at bottom
        _ABToggle(group: group, onChanged: onGroupChanged),
      ],
    );
  }
}
