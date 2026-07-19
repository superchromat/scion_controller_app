import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'osc_dropdown.dart';
import 'osc_value_label.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart' show MappingSegment;
import 'send_color.dart';
import 'send_texture.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_checkbox.dart';
import 'adv_de_window.dart';
import 'adv_sync_adjust.dart';
import 'grid.dart';
import 'panel.dart';
import 'shape.dart';

class ReturnPage extends StatelessWidget {
  const ReturnPage({super.key});

  static const List<String> _colorspaces = <String>['YUV', 'RGB'];
  static const List<String> _subsamplings = <String>['4:4:4', '4:2:2', '4:2:0'];
  static const List<int> _bitDepths = <int>[8, 10, 12];

  @override
  Widget build(BuildContext context) {
    return const OscPathSegment(
      segment: 'output',
      child: _ReturnPageBody(),
    );
  }
}

class _ReturnPageBody extends StatelessWidget {
  const _ReturnPageBody();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = GridTokens(constraints.maxWidth);
        final topRow = GridRow(
          gutter: t.md,
          cells: const [
            (span: 6, child: _ReturnOutputFormatCard(compact: true)),
            (span: 6, child: _AdcAdjustmentsCard()),
          ],
        );

        return GridProvider(
          tokens: t,
          child: ListView(
            padding: t.pagePadding,
            children: [
              GridRow(
                gutter: t.md,
                cells: [
                  (
                    span: 12,
                    child: LabeledCard(
                      title: 'Shape',
                      child: const Shape(pageNumber: 2),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.md),
              GridRow(
                gutter: t.md,
                cells: const [
                  (
                    span: 12,
                    child: LabeledCard(
                      title: 'Color',
                      child: SendColor(showGrade: true, gradePath: '/output/color/grade'),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.md),
              GridRow(
                gutter: t.md,
                cells: const [
                  (
                    span: 12,
                    child: LabeledCard(
                      title: 'Texture',
                      child: SendTexture(),
                    ),
                  ),
                ],
              ),
              SizedBox(height: t.md),
              // Return Output Format + ADC Adjustments moved to the bottom.
              topRow,
            ],
          ),
        );
      },
    );
  }
}

class _ReturnOutputFormatCard extends StatelessWidget {
  final bool compact;

  const _ReturnOutputFormatCard({this.compact = false});

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      title: 'Return Output Format',
      fillChild: compact,
      child: _ReturnOutputControls(compact: compact),
    );
  }
}

class _ReturnOutputControls extends StatelessWidget {
  final bool compact;

  const _ReturnOutputControls({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);

    if (compact) {
      return GridRow(
        gutter: t.md,
        cells: [
          (
            span: 12,
            child: Panel(
              fillChild: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridRow(
                    columns: 12,
                    gutter: t.md,
                    cells: [
                      (
                        span: 4,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const OscPathSegment(
                              segment: 'resolution',
                              child: OscValueLabel(label: 'Resolution', width: null),
                            ),
                            SizedBox(height: t.md),
                            const OscPathSegment(
                              segment: 'framerate',
                              child: OscValueLabel(
                                label: 'Framerate',
                                defaultValue: '0.0',
                                width: null,
                              ),
                            ),
                          ],
                        ),
                      ),
                      (
                        span: 8,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ColorspaceDropdown(width: double.infinity),
                            SizedBox(height: t.sm),
                            _ChromaSubsamplingDropdown(width: double.infinity),
                            SizedBox(height: t.sm),
                            _BitDepthDropdown(width: double.infinity),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: const [
        OscPathSegment(
          segment: 'resolution',
          child: OscValueLabel(label: 'Resolution'),
        ),
        OscPathSegment(
          segment: 'framerate',
          child: OscValueLabel(
            label: 'Framerate',
            defaultValue: '0.0',
          ),
        ),
        _ColorspaceDropdown(),
        _ChromaSubsamplingDropdown(),
        _BitDepthDropdown(),
      ],
    );
  }
}

class _AdcAdjustmentsCard extends StatelessWidget {
  const _AdcAdjustmentsCard();

  @override
  Widget build(BuildContext context) {
    return const LabeledCard(
      title: 'ADC Adjustments',
      child: _AdcAdjustmentsContent(),
    );
  }
}

class _AdcAdjustmentsContent extends StatelessWidget {
  const _AdcAdjustmentsContent();

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return CardColumn(
      children: [
        // TBC enable (moved here from the System page's Return Sync card). Only
        // meaningful in Component sync mode, so it greys out otherwise.
        GridRow(
          gutter: t.md,
          cells: const [
            (
              span: 4,
              child: Panel(
                title: 'Timebase Corrector',
                child: _ReturnTbcToggle(),
              ),
            ),
          ],
        ),
        GridRow(
          gutter: t.md,
          cells: const [
            (
              span: 8,
              child: Panel(
                title: 'DE Window',
                child: AdvDeWindowCard.embedded(),
              ),
            ),
            (
              span: 4,
              child: Panel(
                title: 'Offset',
                child: _OffsetCard(),
              ),
            ),
          ],
        ),
        GridRow(
          gutter: t.md,
          cells: const [
            (
              span: 8,
              child: Panel(
                title: 'Sync Adjust',
                child: AdvSyncAdjustCard.embedded(),
              ),
            ),
            (
              span: 4,
              child: Panel(
                title: 'LLC Phase',
                child: _AdvPhaseCard(embedded: true),
              ),
            ),
          ],
        ),
        GridRow(
          gutter: t.md,
          cells: const [
            (
              span: 5,
              child: Panel(
                title: 'ADC Anti-Alias Filter',
                child: _AdvAaCard(),
              ),
            ),
            (
              span: 7,
              child: Panel(
                title: 'Input Gain (AGC)',
                child: _AgcCard(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// TBC (Time Base Corrector) enable. Bound to `/return/tbc/enabled`, but only
/// meaningful in Component sync mode (STM32 TBC drives the chip's analog-input
/// HSync/VSync from PWM), so it greys out in Locked/External modes.
class _ReturnTbcToggle extends StatefulWidget {
  const _ReturnTbcToggle();

  @override
  State<_ReturnTbcToggle> createState() => _ReturnTbcToggleState();
}

class _ReturnTbcToggleState extends State<_ReturnTbcToggle> {
  String _syncMode = '';
  bool _tbcEnabled = true;

  bool get _editable => _syncMode == 'component';

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/sync_mode');
    reg.registerListener('/sync_mode', _onSyncMode);
    reg.registerAddress('/return/tbc/enabled');
    reg.registerListener('/return/tbc/enabled', _onTbc);
    final sm = reg.allParams['/sync_mode'];
    if (sm != null && sm.currentValue.isNotEmpty) {
      _syncMode = sm.currentValue.first.toString().toLowerCase();
    }
    final tb = reg.allParams['/return/tbc/enabled'];
    if (tb != null && tb.currentValue.isNotEmpty) {
      _tbcEnabled = tb.currentValue.first == true;
    }
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener('/sync_mode', _onSyncMode);
    OscRegistry().unregisterListener('/return/tbc/enabled', _onTbc);
    super.dispose();
  }

  void _onSyncMode(List<Object?> args) {
    if (!mounted || args.isEmpty) return;
    setState(() => _syncMode = args.first.toString().toLowerCase());
  }

  void _onTbc(List<Object?> args) {
    if (!mounted || args.isEmpty) return;
    setState(() => _tbcEnabled = args.first == true);
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _editable ? 1.0 : 0.5,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OscPathSegment(
            segment: 'return',
            child: OscPathSegment(
              segment: 'tbc',
              child: OscPathSegment(
                segment: 'enabled',
                child: OscCheckbox(
                  initialValue: _tbcEnabled,
                  readOnly: !_editable,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'On',
            style: TextStyle(
              fontSize: 14,
              color: _editable ? null : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}

// ADC anti-aliasing filters (ADV7842 AFE). Enable drives all four ADC channels
// (AA_FILTER_EN[3:0]); cutoff selects one of 16 filter responses (10..145 MHz,
// datasheet Table 10).  /adv/aa/* are absolute OSC paths, handled manually like
// the other /adv ADC controls.
class _AdvAaCard extends StatefulWidget {
  const _AdvAaCard();

  @override
  State<_AdvAaCard> createState() => _AdvAaCardState();
}

class _AdvAaCardState extends State<_AdvAaCard> {
  bool _enabled = false;
  int _bw = 0; // 0..15

  // The 16 filter cutoffs (datasheet Table 10). The OSC value is the INDEX
  // (0..15); the knob works in real MHz with a hard detent per cutoff.
  static const List<double> _cutoffsMHz = [
    10, 12, 14, 16, 27, 32, 36, 41,
    59, 69, 80, 91, 95, 109, 126, 145,
  ];

  // Give every detent an equal slice of drag travel (the cutoffs are 2..19 MHz
  // apart; without this the low cutoffs would be a few pixels wide).
  static final List<MappingSegment> _cutoffSegments = [
    for (var i = 0; i < _cutoffsMHz.length - 1; i++)
      MappingSegment.linear(
        t0: i / (_cutoffsMHz.length - 1),
        t1: (i + 1) / (_cutoffsMHz.length - 1),
        v0: _cutoffsMHz[i],
        v1: _cutoffsMHz[i + 1],
      ),
  ];

  static int _indexForCutoff(double mhz) {
    var best = 0;
    var bestDist = (mhz - _cutoffsMHz[0]).abs();
    for (var i = 1; i < _cutoffsMHz.length; i++) {
      final dist = (mhz - _cutoffsMHz[i]).abs();
      if (dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    return best;
  }

  final _bwKnobKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/aa/enable');
    reg.registerListener('/adv/aa/enable', _onEnableMsg);
    reg.registerAddress('/adv/aa/bandwidth');
    reg.registerListener('/adv/aa/bandwidth', _onBwMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/aa/enable', _onEnableMsg);
    reg.unregisterListener('/adv/aa/bandwidth', _onBwMsg);
    super.dispose();
  }

  void _onEnableMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt() != 0;
    if (!mounted) return;
    setState(() => _enabled = v);
  }

  void _onBwMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt().clamp(0, 15);
    if (!mounted) return;
    setState(() => _bw = v);
    _bwKnobKey.currentState?.setValue(_cutoffsMHz[v], emit: false);
  }

  void _sendEnable(bool v) {
    final m = v ? 15 : 0; // all four AA_FILTER_EN bits
    context.read<Network>().sendOscMessage('/adv/aa/enable', [m]);
    OscRegistry().dispatchLocal('/adv/aa/enable', [m]);
  }

  void _sendBw(int v) {
    context.read<Network>().sendOscMessage('/adv/aa/bandwidth', [v]);
    OscRegistry().dispatchLocal('/adv/aa/bandwidth', [v]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Enable', style: t.textLabel),
        SizedBox(width: t.xs),
        OscCheckbox(
          initialValue: _enabled,
          size: t.knobSm * 0.42,
          bindOsc: false, // OSC handled manually via _sendEnable -> /adv/aa/enable
          onChanged: (v) {
            setState(() => _enabled = v);
            _sendEnable(v);
          },
        ),
        SizedBox(width: t.md),
        OscRotaryKnob(
          key: _bwKnobKey,
          initialValue: _cutoffsMHz[_bw],
          minValue: _cutoffsMHz.first,
          maxValue: _cutoffsMHz.last,
          format: '%.0f',
          label: 'Cutoff MHz',
          labelStyle: t.textLabel,
          defaultValue: _cutoffsMHz.first,
          size: t.knobSm,
          sendOsc: false, // OSC handled manually: knob is MHz, wire is index
          detentValues: _cutoffsMHz,
          mappingSegments: _cutoffSegments,
          onChanged: (v) {
            final idx = _indexForCutoff(v);
            if (idx == _bw) return;
            setState(() => _bw = idx);
            _sendBw(idx);
          },
        ),
      ],
    );
  }
}

// CP automatic gain control. AGC on = chip tracks gain automatically (default,
// servo runs ~1.53x). AGC off = manual A/B/C gains apply.
//
// UNITS: the OSC protocol value is the HW-guide "2.8 format" gain in [0, 4)
// (code = value*256), but the silicon actually applies code/512 — half the
// documented value (verified 2026-06-12 by level sweep + HSD_FB/HSD_CHA
// readback + AGC level equivalence; the datasheet's "0x100 = unity" is wrong).
// Real ceiling is therefore 2.0x. This UI shows the APPLIED gain (unity = 1.0,
// max 2.0) and converts to/from protocol units (x2 / /2) at the OSC boundary.
// Gain mode is SNR-neutral: it does NOT change loopback noise (signal and
// converter noise scale together).
class _AgcCard extends StatefulWidget {
  const _AgcCard();

  @override
  State<_AgcCard> createState() => _AgcCardState();
}

class _AgcCardState extends State<_AgcCard> {
  static const double _protocolPerApplied = 2.0; // OSC value = applied gain * 2
  bool _agcEnabled = true;
  // Manual CP gain as the APPLIED gain factor in [0, 2.0]. Unity = 1.0.
  double _gainA = 1.0;
  double _gainB = 1.0;
  double _gainC = 1.0;
  final _gainAKey = GlobalKey<OscRotaryKnobState>();
  final _gainBKey = GlobalKey<OscRotaryKnobState>();
  final _gainCKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/agc/enable');
    reg.registerListener('/adv/agc/enable', _onEnableMsg);
    reg.registerAddress('/adv/agc/gain');
    reg.registerListener('/adv/agc/gain', _onGainMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/agc/enable', _onEnableMsg);
    reg.unregisterListener('/adv/agc/gain', _onGainMsg);
    super.dispose();
  }

  void _onEnableMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt() != 0;
    if (!mounted) return;
    setState(() => _agcEnabled = v);
  }

  void _onGainMsg(List<Object?> args) {
    if (args.length < 3) return;
    // Protocol units (2.8-format, 0..4) -> applied gain (0..2).
    final a = ((args[0] as num) / _protocolPerApplied).clamp(0.0, 2.0).toDouble();
    final b = ((args[1] as num) / _protocolPerApplied).clamp(0.0, 2.0).toDouble();
    final c = ((args[2] as num) / _protocolPerApplied).clamp(0.0, 2.0).toDouble();
    if (!mounted) return;
    setState(() {
      _gainA = a; _gainB = b; _gainC = c;
    });
    _gainAKey.currentState?.setValue(a, emit: false);
    _gainBKey.currentState?.setValue(b, emit: false);
    _gainCKey.currentState?.setValue(c, emit: false);
  }

  void _sendEnable(bool v) {
    context.read<Network>().sendOscMessage('/adv/agc/enable', [v ? 1 : 0]);
    OscRegistry().dispatchLocal('/adv/agc/enable', [v ? 1 : 0]);
  }

  void _sendGain() {
    // Sending a manual gain implies AGC off (mirrors firmware behaviour).
    setState(() => _agcEnabled = false);
    // Applied gain -> protocol units (x2) at the OSC boundary.
    final args = [
      _gainA * _protocolPerApplied,
      _gainB * _protocolPerApplied,
      _gainC * _protocolPerApplied,
    ];
    context.read<Network>().sendOscMessage('/adv/agc/gain', args);
    OscRegistry().dispatchLocal('/adv/agc/gain', args);
  }

  Widget _gainKnob(
      String label, GlobalKey<OscRotaryKnobState> key, double value, GridTokens t,
      void Function(double) onCommit) {
    return OscRotaryKnob(
      key: key,
      initialValue: value,
      minValue: 0,
      maxValue: 2,
      format: '%.2f',
      label: label,
      labelStyle: t.textLabel,
      defaultValue: 1.0,
      size: t.knobSm,
      sendOsc: false,
      preferInteger: false,
      onChanged: (v) => onCommit(v.clamp(0.0, 2.0).toDouble()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final agcRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('AGC', style: t.textLabel),
        SizedBox(width: t.xs),
        OscCheckbox(
          initialValue: _agcEnabled,
          size: t.knobSm * 0.42,
          bindOsc: false, // OSC handled manually via _sendEnable -> /adv/agc/enable
          onChanged: (v) {
            setState(() => _agcEnabled = v);
            _sendEnable(v);
          },
        ),
      ],
    );
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            agcRow,
            SizedBox(width: t.md),
            Opacity(
              opacity: _agcEnabled ? 0.4 : 1.0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _gainKnob('A·G', _gainAKey, _gainA, t,
                      (v) { _gainA = v; _sendGain(); }),
                  SizedBox(width: t.sm),
                  _gainKnob('B·B', _gainBKey, _gainB, t,
                      (v) { _gainB = v; _sendGain(); }),
                  SizedBox(width: t.sm),
                  _gainKnob('C·R', _gainCKey, _gainC, t,
                      (v) { _gainC = v; _sendGain(); }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OffsetCard extends StatefulWidget {
  const _OffsetCard();

  @override
  State<_OffsetCard> createState() => _OffsetCardState();
}

class _OffsetCardState extends State<_OffsetCard> {
  int _hOffset = 0;
  int _vOffset = 0;
  final _hKnobKey = GlobalKey<OscRotaryKnobState>();
  final _vKnobKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/h_offset');
    reg.registerListener('/adv/h_offset', _onHMsg);
    reg.registerAddress('/adv/v_offset');
    reg.registerListener('/adv/v_offset', _onVMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/h_offset', _onHMsg);
    reg.unregisterListener('/adv/v_offset', _onVMsg);
    super.dispose();
  }

  void _onHMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt().clamp(-50, 50);
    if (!mounted) return;
    setState(() => _hOffset = v);
    _hKnobKey.currentState?.setValue(v.toDouble(), emit: false);
  }

  void _onVMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt().clamp(-50, 50);
    if (!mounted) return;
    setState(() => _vOffset = v);
    _vKnobKey.currentState?.setValue(v.toDouble(), emit: false);
  }

  void _sendH(int v) {
    context.read<Network>().sendOscMessage('/adv/h_offset', [v]);
    OscRegistry().dispatchLocal('/adv/h_offset', [v]);
  }

  void _sendV(int v) {
    context.read<Network>().sendOscMessage('/adv/v_offset', [v]);
    OscRegistry().dispatchLocal('/adv/v_offset', [v]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OscRotaryKnob(
              key: _hKnobKey,
              initialValue: _hOffset.toDouble(),
              minValue: -50,
              maxValue: 50,
              format: '%.0f',
              label: 'H',
              labelStyle: t.textLabel,
              defaultValue: 0,
              isBipolar: true,
              size: t.knobSm,
              sendOsc: false,
              preferInteger: true,
              oscPathOverride: '/adv/h_offset',
              onChanged: (v) {
                final iv = v.round().clamp(-50, 50);
                _hOffset = iv;
                _sendH(iv);
              },
            ),
            SizedBox(width: t.md),
            OscRotaryKnob(
              key: _vKnobKey,
              initialValue: _vOffset.toDouble(),
              minValue: -50,
              maxValue: 50,
              format: '%.0f',
              label: 'V',
              labelStyle: t.textLabel,
              defaultValue: 0,
              isBipolar: true,
              size: t.knobSm,
              sendOsc: false,
              preferInteger: true,
              oscPathOverride: '/adv/v_offset',
              onChanged: (v) {
                final iv = v.round().clamp(-50, 50);
                _vOffset = iv;
                _sendV(iv);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvPhaseCard extends StatefulWidget {
  final bool embedded;
  final bool vertical;

  const _AdvPhaseCard({this.embedded = false, this.vertical = false});

  @override
  State<_AdvPhaseCard> createState() => _AdvPhaseCardState();
}

class _AdvPhaseCardState extends State<_AdvPhaseCard> {
  bool _dllEnabled = false;
  int _phase = 0; // 0..63
  final _phaseKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/dll');
    reg.registerListener('/adv/dll', _onDllMsg);
    reg.registerAddress('/adv/phase');
    reg.registerListener('/adv/phase', _onPhaseMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/dll', _onDllMsg);
    reg.unregisterListener('/adv/phase', _onPhaseMsg);
    super.dispose();
  }

  void _onDllMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt() != 0;
    if (!mounted) return;
    setState(() => _dllEnabled = v);
  }

  void _onPhaseMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt().clamp(0, 63);
    if (!mounted) return;
    setState(() => _phase = v);
    _phaseKey.currentState?.setValue(v.toDouble(), emit: false);
  }

  void _sendPhase(int v) {
    context.read<Network>().sendOscMessage('/adv/phase', [v]);
    // local echo so UI reflects immediately
    OscRegistry().dispatchLocal('/adv/phase', [v]);
  }

  void _sendDll(bool v) {
    context.read<Network>().sendOscMessage('/adv/dll', [v ? 1 : 0]);
    OscRegistry().dispatchLocal('/adv/dll', [v ? 1 : 0]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final phaseKnobSize = widget.embedded ? t.knobSm : t.knobMd;
    final dllCheckbox = OscCheckbox(
      initialValue: _dllEnabled,
      size: t.knobSm * 0.42,
      bindOsc: false, // OSC handled manually via _sendDll -> /adv/dll
      onChanged: (v) {
        setState(() => _dllEnabled = v);
        _sendDll(v);
      },
    );
    final dllRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('DLL', style: t.textLabel),
        SizedBox(width: t.xs),
        dllCheckbox,
      ],
    );
    final phaseKnob = OscRotaryKnob(
      key: _phaseKey,
      initialValue: _phase.toDouble(),
      minValue: 0,
      maxValue: 63,
      format: '%.0f',
      label: 'Phase',
      labelStyle: t.textLabel,
      defaultValue: 0,
      size: phaseKnobSize,
      sendOsc: false,  // Manual OSC handling
      preferInteger: true,
      oscPathOverride: '/adv/phase',
      onChanged: (v) {
        final iv = v.round().clamp(0, 63);
        _phase = iv;
        _sendPhase(iv);
      },
    );
    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dllRow,
        SizedBox(width: t.md),
        phaseKnob,
      ],
    );

    if (widget.embedded) {
      if (widget.vertical) {
        final compactRow = Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            dllRow,
            SizedBox(width: t.sm),
            phaseKnob,
          ],
        );
        return Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: compactRow,
          ),
        );
      }
      final dllStack = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dllCheckbox,
          SizedBox(height: t.xs * 0.4),
          Text('DLL', style: t.textCaption),
        ],
      );
      final compactRow = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          dllStack,
          SizedBox(width: t.sm),
          phaseKnob,
        ],
      );
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: compactRow,
        ),
      );
    }

    return NeumorphicContainer(
      baseColor: const Color(0xFF2A2A2C),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text('ADV7842 LLC Phase',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          controls,
        ],
      ),
    );
  }
}

class _ColorspaceDropdown extends StatelessWidget {
  final double? width;

  const _ColorspaceDropdown({this.width});

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Colorspace',
      displayLabel: 'Colorspace',
      pathSegment: 'colorspace',
      items: ReturnPage._colorspaces,
      defaultValue: ReturnPage._colorspaces.first,
      width: width ?? 160,
    );
  }
}

class _ChromaSubsamplingDropdown extends StatelessWidget {
  final double? width;

  const _ChromaSubsamplingDropdown({this.width});

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Chroma Subsampling',
      displayLabel: 'Chroma Subsampling',
      pathSegment: 'chroma_subsampling',
      items: ReturnPage._subsamplings,
      defaultValue: ReturnPage._subsamplings.first,
      width: width ?? 160,
    );
  }
}

class _BitDepthDropdown extends StatelessWidget {
  final double? width;

  const _BitDepthDropdown({this.width});

  @override
  Widget build(BuildContext context) {
    return OscDropdown<int>(
      label: 'Bit Depth',
      displayLabel: 'Bit Depth',
      pathSegment: 'bit_depth',
      items: ReturnPage._bitDepths,
      defaultValue: ReturnPage._bitDepths.first,
      width: width ?? 160,
    );
  }
}
