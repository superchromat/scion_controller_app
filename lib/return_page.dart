import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'osc_dropdown.dart';
import 'osc_value_label.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'send_color.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_checkbox.dart';
import 'adv_de_window.dart';
import 'adv_sync_adjust.dart';
import 'grid.dart';
import 'panel.dart';

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
            padding: EdgeInsets.all(t.md),
            children: [
              topRow,
              SizedBox(height: t.md),
              GridRow(
                gutter: t.md,
                cells: const [
                  (
                    span: 12,
                    child: LabeledCard(
                      title: 'Color',
                      child: SendColor(showGrade: true, gradePath: '/output/grade'),
                    ),
                  ),
                ],
              ),
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
              span: 8,
              child: Panel(
                title: 'Sync Adjust',
                child: AdvSyncAdjustCard.embedded(),
              ),
            ),
            (
              span: 4,
              child: SizedBox.shrink(),
            ),
          ],
        ),
      ],
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
