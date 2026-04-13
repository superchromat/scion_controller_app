import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
      if (current == group) {
        // Toggle off
        _groups[row][sourceSend] = ABGroup.none;
      } else {
        // Clear any other cell that had this group in the same row
        for (final s in MixerPage.sources) {
          if (_groups[row][s] == group) {
            _groups[row][s] = ABGroup.none;
          }
        }
        _groups[row][sourceSend] = group;
      }
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

class _MixerRow extends StatefulWidget {
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
  State<_MixerRow> createState() => _MixerRowState();
}

class _MixerRowState extends State<_MixerRow> {
  // Incremented to trigger a flash on all A/B toggle buttons in this row.
  final ValueNotifier<int> _flashTrigger = ValueNotifier<int>(0);

  bool get _hasA => widget.groups.values.any((g) => g == ABGroup.a);
  bool get _hasB => widget.groups.values.any((g) => g == ABGroup.b);
  bool get _hasBothAB => _hasA && _hasB;

  /// If A/B groups aren't both assigned, flash the buttons and return true.
  bool _guardCrossfade() {
    if (_hasBothAB) return false;
    _flashTrigger.value++;
    return true; // blocked
  }

  @override
  void dispose() {
    _flashTrigger.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    return GridRow(
      gutter: t.md,
      cells: [
        (
          span: 12,
          child: Panel.dark(
            title: 'Send ${widget.targetSend}',
            child: Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < MixerPage.sources.length; i++) ...[
                        if (i > 0) SizedBox(width: t.xs),
                        Expanded(
                          child: _MixerCell(
                            targetSend: widget.targetSend,
                            sourceSend: MixerPage.sources[i],
                            group: widget.groups[MixerPage.sources[i]]!,
                            alphaWeight: widget.weightFor(MixerPage.sources[i]),
                            onGroupChanged: (g) => widget.onGroupChanged(MixerPage.sources[i], g),
                            flashTrigger: _flashTrigger,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: t.sm),
                FractionallySizedBox(
                  widthFactor: 3 / 4,
                  child: _Crossfader(
                    value: widget.crossfade,
                    onChanged: (v) {
                      if (_guardCrossfade()) return;
                      widget.onCrossfadeChanged(v);
                    },
                    onAutoRequest: (target) => _guardCrossfade(),
                  ),
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
/// Listens to [flashTrigger] to briefly flash yellow when crossfade is
/// attempted without both A and B assigned.
class _ABToggle extends StatefulWidget {
  final ABGroup group;
  final ValueChanged<ABGroup> onChanged;
  final ValueNotifier<int> flashTrigger;

  const _ABToggle({
    required this.group,
    required this.onChanged,
    required this.flashTrigger,
  });

  @override
  State<_ABToggle> createState() => _ABToggleState();
}

class _ABToggleState extends State<_ABToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashCtrl;
  late final Animation<double> _flashAnim;

  @override
  void initState() {
    super.initState();
    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _flashAnim = CurvedAnimation(parent: _flashCtrl, curve: Curves.easeOut);
    widget.flashTrigger.addListener(_onFlash);
  }

  @override
  void didUpdateWidget(_ABToggle old) {
    super.didUpdateWidget(old);
    if (old.flashTrigger != widget.flashTrigger) {
      old.flashTrigger.removeListener(_onFlash);
      widget.flashTrigger.addListener(_onFlash);
    }
  }

  @override
  void dispose() {
    widget.flashTrigger.removeListener(_onFlash);
    _flashCtrl.dispose();
    super.dispose();
  }

  void _onFlash() {
    _flashCtrl.reverse(from: 1);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final btnStyle = t.textCaption.copyWith(fontWeight: FontWeight.w700);
    const aColor = Color(0xFF5B8DEF);
    const bColor = Color(0xFFEF7B5B);
    const flashColor = Color(0xFFFFF176); // yellow

    return AnimatedBuilder(
      animation: _flashAnim,
      builder: (context, _) {
        final flash = _flashAnim.value; // 1.0 → 0.0

        Widget btn(String label, ABGroup target, Color color) {
          final active = widget.group == target;
          // Flash border only on unassigned buttons
          final showFlash = !active && flash > 0.01;
          final bgColor = active ? color : const Color(0xFF2A2A2C);
          final borderColor = active
              ? color
              : showFlash
                  ? Color.lerp(Colors.grey[700]!, flashColor, flash)!
                  : Colors.grey[700]!;
          final textColor = active ? Colors.white : Colors.grey[500]!;

          return GestureDetector(
            onTap: () => widget.onChanged(target),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.5),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: borderColor, width: 1),
              ),
              child: Text(label, style: btnStyle.copyWith(color: textColor)),
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
      },
    );
  }
}

/// Horizontal A/B crossfader with AUTO buttons and labels.
class _Crossfader extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  /// Called before auto-crossfade starts. Return true to block it.
  final bool Function(double target)? onAutoRequest;

  const _Crossfader({
    required this.value,
    required this.onChanged,
    this.onAutoRequest,
  });

  @override
  State<_Crossfader> createState() => _CrossfaderState();
}

class _CrossfaderState extends State<_Crossfader>
    with SingleTickerProviderStateMixin {
  static const _autoDuration = Duration(seconds: 1);
  // ~30 fps: update every ~33ms for smooth motion without flooding OSC
  static const _autoStepInterval = Duration(milliseconds: 33);

  late final Ticker _ticker;
  double _autoFrom = 0;
  double _autoTo = 0;
  bool _autoRunning = false;
  Duration _lastStep = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    // Throttle: only call onChanged at ~30fps intervals
    if (elapsed - _lastStep < _autoStepInterval && elapsed < _autoDuration) {
      return;
    }
    _lastStep = elapsed;

    final t = (elapsed.inMicroseconds / _autoDuration.inMicroseconds).clamp(0.0, 1.0);
    // Ease in-out
    final eased = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
    final v = _autoFrom + (_autoTo - _autoFrom) * eased;
    widget.onChanged(v.clamp(0.0, 1.0));

    if (t >= 1.0) {
      widget.onChanged(_autoTo);
      _ticker.stop();
      _autoRunning = false;
    }
  }

  void _startAuto(double target) {
    if (widget.onAutoRequest?.call(target) == true) return; // blocked
    _autoFrom = widget.value;
    _autoTo = target;
    _autoRunning = true;
    _lastStep = Duration.zero;
    if (_ticker.isActive) _ticker.stop();
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    const aColor = Color(0xFF5B8DEF);
    const bColor = Color(0xFFEF7B5B);
    final labelStyle = t.textLabel.copyWith(fontWeight: FontWeight.w700, fontSize: t.u * 1.4);
    final btnStyle = t.textCaption.copyWith(fontWeight: FontWeight.w700, fontSize: t.u * 0.9);

    Widget autoBtn(String label, Color color, double target) {
      return GestureDetector(
        onTap: () => _startAuto(target),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.5),
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2C),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.grey[700]!, width: 1),
          ),
          child: Text('AUTO', style: btnStyle.copyWith(color: color)),
        ),
      );
    }

    return Row(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('A', style: labelStyle.copyWith(color: aColor)),
            SizedBox(height: t.xs),
            autoBtn('AUTO', aColor, 0.0),
          ],
        ),
        SizedBox(width: t.sm),
        Expanded(
          child: NeumorphicSlider(
            axis: SliderAxis.horizontal,
            minValue: 0.0,
            maxValue: 1.0,
            value: widget.value,
            defaultValue: 0.5,
            label: '',
            format: '',
            trackWidth: 14,
            thumbLength: 36,
            graduations: 10,
            onChanged: (v) {
              // Manual drag cancels any running auto-crossfade
              if (_autoRunning) {
                _ticker.stop();
                _autoRunning = false;
              }
              widget.onChanged(v);
            },
          ),
        ),
        SizedBox(width: t.sm),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('B', style: labelStyle.copyWith(color: bColor)),
            SizedBox(height: t.xs),
            autoBtn('AUTO', bColor, 1.0),
          ],
        ),
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
  final ValueNotifier<int> flashTrigger;

  const _MixerCell({
    required this.targetSend,
    required this.sourceSend,
    required this.group,
    required this.alphaWeight,
    required this.onGroupChanged,
    required this.flashTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final isIdentity = sourceSend == targetSend;

    // Column stretches to row height (via IntrinsicHeight + stretch).
    // Expanded pushes A/B buttons to the bottom.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NeumorphicInset(
          padding: EdgeInsets.all(t.xs),
          child: Column(
            children: [
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
              _ABToggle(group: group, onChanged: onGroupChanged, flashTrigger: flashTrigger),
              SizedBox(height: t.sm),
            ],
          ),
        ),
        if (isIdentity)
          Positioned(
            left: 1, top: 1, right: 1, bottom: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFF8BA00).withOpacity(0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
