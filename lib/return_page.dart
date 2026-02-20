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
import 'adv_de_window.dart';
import 'adv_sync_adjust.dart';

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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        _ReturnOutputFormatCard(),
        SizedBox(height: 16),
        LabeledCard(
          title: 'Color',
          child: SendColor(showGrade: true, gradePath: '/output/grade'),
        ),
        SizedBox(height: 16),
        _AdvPhaseCard(),
        SizedBox(height: 16),
        AdvDeWindowCard(),
        SizedBox(height: 16),
        AdvSyncAdjustCard(),
      ],
    );
  }
}

class _ReturnOutputFormatCard extends StatelessWidget {
  const _ReturnOutputFormatCard();

  @override
  Widget build(BuildContext context) {
    return LabeledCard(
      title: 'Return Output Format',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _ReturnOutputControls(),
          ],
        ),
      ),
    );
  }
}

class _ReturnOutputControls extends StatelessWidget {
  const _ReturnOutputControls();

  @override
  Widget build(BuildContext context) {
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

class _AdvPhaseCard extends StatefulWidget {
  const _AdvPhaseCard();

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
    return NeumorphicContainer(
      baseColor: const Color(0xFF2A2A2C),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Text('ADV7842 LLC Phase',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          const Text('DLL'),
          const SizedBox(width: 8),
          Switch(
            value: _dllEnabled,
            onChanged: (v) {
              setState(() => _dllEnabled = v);
              _sendDll(v);
            },
          ),
          const SizedBox(width: 16),
          OscRotaryKnob(
            key: _phaseKey,
            initialValue: _phase.toDouble(),
            minValue: 0,
            maxValue: 63,
            format: '%.0f',
            label: 'Phase',
            defaultValue: 0,
            size: 60,
            sendOsc: false,  // Manual OSC handling
            preferInteger: true,
            onChanged: (v) {
              final iv = v.round().clamp(0, 63);
              _phase = iv;
              _sendPhase(iv);
            },
          ),
        ],
      ),
    );
  }
}

class _ColorspaceDropdown extends StatelessWidget {
  const _ColorspaceDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Colorspace',
      displayLabel: 'Colorspace',
      pathSegment: 'colorspace',
      items: ReturnPage._colorspaces,
      defaultValue: ReturnPage._colorspaces.first,
    );
  }
}

class _ChromaSubsamplingDropdown extends StatelessWidget {
  const _ChromaSubsamplingDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<String>(
      label: 'Chroma Subsampling',
      displayLabel: 'Chroma Subsampling',
      pathSegment: 'chroma_subsampling',
      items: ReturnPage._subsamplings,
      defaultValue: ReturnPage._subsamplings.first,
    );
  }
}

class _BitDepthDropdown extends StatelessWidget {
  const _BitDepthDropdown();

  @override
  Widget build(BuildContext context) {
    return OscDropdown<int>(
      label: 'Bit Depth',
      displayLabel: 'Bit Depth',
      pathSegment: 'bit_depth',
      items: ReturnPage._bitDepths,
      defaultValue: ReturnPage._bitDepths.first,
    );
  }
}
