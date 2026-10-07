import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app_button.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'neumorphic_slider.dart';
import 'panel.dart';
import 'rotary_knob.dart';
import 'send_source_selector.dart';
import 'signal_colors.dart';

/// A/B crossfade group assignment.
enum ABGroup { none, a, b }

class MixerPage extends StatelessWidget {
  const MixerPage({super.key});

  static const List<int> sources = [1, 2, 3, 4];

  /// The last column is the capture return, not a send.
  static bool isReturn(int sourceSend) => sourceSend == 4;

  /// Column heading: a column is a source feeding INTO each row's send, so the
  /// sends are named as inputs. The Return keeps its bare name — it is only
  /// ever a source, so 'Input' would not distinguish it from anything.
  static String sourceLabel(int sourceSend) =>
      isReturn(sourceSend) ? 'Return' : 'Send $sourceSend Input';

  /// The signal-path colour a source column is tinted with, matching the
  /// System Overview diagram.
  static Color sourceColor(int sourceSend) =>
      isReturn(sourceSend) ? kReturnSignalColor : kSendSignalColor;

  /// Opening A/B assignment for a cell: a row's identity source (Send N on the
  /// Send N row) is A, the Return column is B, everything else unassigned.
  ///
  /// This is the arrangement a row gets set to by hand anyway — fade the send
  /// against the return — so the crossfader is usable on arrival instead of
  /// refusing to move until both groups are picked. The two cases never
  /// collide: rows are sends 1-3, the return is source 4.
  static ABGroup defaultGroup(int targetSend, int sourceSend) {
    if (sourceSend == targetSend) return ABGroup.a;
    if (isReturn(sourceSend)) return ABGroup.b;
    return ABGroup.none;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = GridTokens(constraints.maxWidth);
        return GridProvider(
          tokens: t,
          child: SingleChildScrollView(
            padding: t.pagePadding,
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
    for (int row = 0; row < 3; row++)
      {
        for (final s in MixerPage.sources)
          s: MixerPage.defaultGroup(row + 1, s),
      },
  ];

  // Per-row crossfade position: 0.0 = A, 1.0 = B.
  //
  // Opens hard on A, so the row's own send starts at full weight and the
  // Return overlay (B, see MixerPage.defaultGroup) contributes nothing until
  // the fader is moved. Starting centred would have every row come up at a
  // half-mix nobody asked for.
  final List<double> _crossfade = [0.0, 0.0, 0.0];

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

    // No column-header strip: each cell names its own source (see _MixerCell).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int targetSend = 1; targetSend <= 3; targetSend++) ...[
          _MixerRow(
            targetSend: targetSend,
            groups: _groups[targetSend - 1],
            crossfade: _crossfade[targetSend - 1],
            weightFor: (source) => _weightFor(targetSend - 1, source),
            onGroupChanged: (source, group) =>
                _setGroup(targetSend - 1, source, group),
            onCrossfadeChanged: (value) => _setCrossfade(targetSend - 1, value),
          ),
          if (targetSend < 3) SizedBox(height: t.panelGap),
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
      cells: [
        (
          span: 12,
          child: Panel.dark(
            // A row is one send's output bus; the columns above are its inputs.
            title: 'Send ${widget.targetSend} Output',
            titleStyle: t.textPanelTitle.copyWith(
              fontSize: t.u * 1.3,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE1E1E3),
            ),
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
                            onGroupChanged: (g) =>
                                widget.onGroupChanged(MixerPage.sources[i], g),
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
    const aColor = Color(0xFF5B8DEF);
    const bColor = Color(0xFFEF7B5B);
    const flashColor = Color(0xFFFFF176); // yellow

    return AnimatedBuilder(
      animation: _flashAnim,
      builder: (context, _) {
        final flash = _flashAnim.value; // 1.0 → 0.0

        Widget btn(String label, ABGroup target, Color color) {
          final active = widget.group == target;
          // Flash only unassigned buttons. AppButton draws its hairline rim
          // from the accent when unselected, so flashing is a lerp of the
          // accent toward yellow — the same trick the LUT editor's lock button
          // uses (lut_editor.dart:928).
          final showFlash = !active && flash > 0.01;
          return AppButton(
            label: label,
            dense: true,
            selected: active,
            accentColor:
                showFlash ? Color.lerp(color, flashColor, flash)! : color,
            onPressed: () => widget.onChanged(target),
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
  // Auto-take transition time, in seconds, per direction. Seconds rather than
  // milliseconds so the knob reads 0.10-5.00 instead of 100-5000; the default
  // is the 1s that used to be hardcoded here.
  static const double _minTake = 0.1;
  static const double _maxTake = 5.0;
  static const double _defaultTake = 1.0;

  // ~30 fps: update every ~33ms for smooth motion without flooding OSC
  static const _autoStepInterval = Duration(milliseconds: 33);

  double _takeToA = _defaultTake;
  double _takeToB = _defaultTake;

  /// Linked by default, so an auto take runs for the same time in both
  /// directions and A->B->A is symmetric. Unlink to set the two ends apart.
  bool _linked = true;

  late final Ticker _ticker;
  double _autoFrom = 0;
  double _autoTo = 0;
  bool _autoRunning = false;
  Duration _lastStep = Duration.zero;

  /// Which end the bar was last parked at. The fill grows from that side, so
  /// it reads as "how far off the bus you are" rather than always creeping in
  /// from the left — which is how a hardware T-bar's LEDs behave, and which
  /// otherwise makes a fader sitting hard on A look half mixed toward B.
  /// Starts false: _crossfade opens at 0.0, i.e. parked on A.
  bool _parkedOnB = false;

  /// Duration of the take currently running, captured when it starts so that
  /// turning a knob mid-transition cannot warp the one already under way.
  Duration _activeDuration = _durationOf(_defaultTake);

  static Duration _durationOf(double seconds) =>
      Duration(microseconds: (seconds * 1000000).round());

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _notePark(widget.value);
  }

  @override
  void didUpdateWidget(_Crossfader old) {
    super.didUpdateWidget(old);
    // Catches both ends of a take and a manual drag run to the stop, since
    // every value change arrives here from the parent.
    _notePark(widget.value);
  }

  /// Remember the end the bar has reached; ignore everything in between.
  void _notePark(double v) {
    if (v <= 0.0 && _parkedOnB) {
      setState(() => _parkedOnB = false);
    } else if (v >= 1.0 && !_parkedOnB) {
      setState(() => _parkedOnB = true);
    }
  }

  void _onTick(Duration elapsed) {
    // Throttle: only call onChanged at ~30fps intervals
    if (elapsed - _lastStep < _autoStepInterval && elapsed < _activeDuration) {
      return;
    }
    _lastStep = elapsed;

    final t = (elapsed.inMicroseconds / _activeDuration.inMicroseconds)
        .clamp(0.0, 1.0);
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

  /// Which knob governs a take: the one at the end being faded toward.
  void _startAuto(double target) {
    if (widget.onAutoRequest?.call(target) == true) return; // blocked
    _activeDuration = _durationOf(target <= 0.5 ? _takeToA : _takeToB);
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

  void _setTake(bool toA, double seconds) {
    setState(() {
      if (_linked) {
        _takeToA = seconds;
        _takeToB = seconds;
      } else if (toA) {
        _takeToA = seconds;
      } else {
        _takeToB = seconds;
      }
    });
  }

  void _toggleLink() {
    setState(() {
      _linked = !_linked;
      // Re-linking adopts the A end's time for both. Otherwise the two knobs
      // could sit at visibly different values while the icon claims they are
      // linked, and the next take would pick whichever end it happened to be
      // headed for.
      if (_linked) _takeToB = _takeToA;
    });
  }

  /// One of the two take-time knobs flanking the fader. [toA] is the left one,
  /// governing the take toward A.
  /// The knob face only — its caption is supplied by the row, so the knob and
  /// the AUTO button caption on the same line rather than each captioning
  /// itself at its own height.
  Widget _takeKnob(GridTokens t, {required bool toA}) => RotaryKnob(
        label: '',
        minValue: _minTake,
        maxValue: _maxTake,
        value: toA ? _takeToA : _takeToB,
        defaultValue: _defaultTake,
        format: '%.2f',
        size: t.knobSm,
        labelStyle: t.textLabel,
        // Detent at the default so a knob clicks back to a 1s take.
        snapConfig: SnapConfig(
          snapPoints: const [_defaultTake],
          snapRegionHalfWidth: (_maxTake - _minTake) * 0.015,
          snapBehavior: SnapBehavior.hard,
        ),
        onChanged: (v) => _setTake(toA, v),
      );

  // No tooltip: the link/link_off glyph carries its own meaning, and a bare
  // Material Tooltip brings its own styling that matches nothing else here.
  Widget _linkToggle(GridTokens t) => GestureDetector(
        onTap: _toggleLink,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: t.xs),
          child: Icon(
            _linked ? Icons.link : Icons.link_off,
            size: t.knobSm * 0.4,
            color: _linked ? const Color(0xFFFFF176) : Colors.grey[600],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    const aColor = Color(0xFF5B8DEF);
    const bColor = Color(0xFFEF7B5B);

    // The row is a two-line grid, and everything hangs off it:
    //
    //   band     one row of controls, all vertically centred in a box of the
    //            same height, so the knob face, the link icon, the AUTO button
    //            and the fader thumb share one centreline;
    //   caption  one line of text directly beneath, so 'Take' and 'A' sit on
    //            the same baseline.
    //
    // Aligning the outer Row to .start is what holds those two lines true —
    // centring or bottom-aligning lets each element float to its own height,
    // which is what made this read as parts scattered on the page.
    final band = t.knobSm;
    final captionStyle = t.textLabel;

    Widget banded(Widget child) =>
        SizedBox(height: band, child: Center(child: child));

    Widget captioned(Widget control, Widget caption) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [banded(control), SizedBox(height: t.xs), caption],
        );

    // Momentary, never selected — the accent supplies both the group-coloured
    // label (AppButton uses it as the foreground when unselected) and the
    // hairline rim, which is what the hand-rolled version drew by hand.
    Widget autoBtn(Color color, double target) => AppButton(
          label: 'AUTO',
          dense: true,
          accentColor: color,
          onPressed: () => _startAuto(target),
        );

    // Knob, link, AUTO — then the fader — then the mirror of that, so the row
    // is symmetric about the bar and each link icon sits against the knob it
    // acts on.
    Widget end({required bool isA}) {
      final color = isA ? aColor : bColor;
      final children = <Widget>[
        captioned(
          _takeKnob(t, toA: isA),
          Text('Take', style: captionStyle),
        ),
        banded(_linkToggle(t)),
        captioned(
          autoBtn(color, isA ? 0.0 : 1.0),
          // Same size and baseline as 'Take'; the group reads from the colour,
          // which already carries it on the AUTO rim and the cell toggles.
          Text(isA ? 'A' : 'B',
              style: captionStyle.copyWith(
                  fontWeight: FontWeight.w700, color: color)),
        ),
      ];
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: isA ? children : children.reversed.toList(),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        end(isA: true),
        SizedBox(width: t.sm),
        // The fader sits in the same band, so its thumb centres on the row's
        // one centreline instead of straddling it.
        Expanded(
          child: banded(
            NeumorphicSlider(
              axis: SliderAxis.horizontal,
              minValue: 0.0,
              maxValue: 1.0,
              value: widget.value,
              defaultValue: 0.5,
              fillOrigin:
                  _parkedOnB ? SliderFillOrigin.end : SliderFillOrigin.start,
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
        ),
        SizedBox(width: t.sm),
        end(isA: false),
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
              // Names its own source, rather than relying on a header strip
              // above the matrix — three rows down, that header is a long way
              // from the cell you are reading.
              Text(
                MixerPage.sourceLabel(sourceSend),
                style: t.textLabel.copyWith(
                  color: const Color(0xFFE1E1E3),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: t.xs),
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
              _ABToggle(
                  group: group,
                  onChanged: onGroupChanged,
                  flashTrigger: flashTrigger),
              SizedBox(height: t.sm),
            ],
          ),
        ),
        if (isIdentity)
          Positioned(
            left: 1,
            top: 1,
            right: 1,
            bottom: 1,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.5),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(5.0),
                ),
              ),
            ),
          ),
        if (!isIdentity)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // Tint by which signal the COLUMN carries, not by "is this a
                  // cross-feed": every column was amber, so the Return column
                  // read as a send. Matches the System Overview's section
                  // colours.
                  color:
                      MixerPage.sourceColor(sourceSend).withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(6.0),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
