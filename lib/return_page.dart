import 'package:flutter/material.dart';

import 'labeled_card.dart';
import 'lut_editor.dart';
import 'osc_dropdown.dart';
import 'osc_value_label.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
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
        _ReturnOutputPictureCard(),
        SizedBox(height: 16),
        _AdvPhaseCard(),
        SizedBox(height: 16),
        AdvDeWindowCard(),
        SizedBox(height: 16),
        AdvSyncAdjustCard(),
        SizedBox(height: 16),
        _ReturnOutputLutCard(),
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

class _ReturnOutputPictureCard extends StatelessWidget {
  const _ReturnOutputPictureCard();

  @override
  Widget build(BuildContext context) {
    return const LabeledCard(
      title: 'Output Picture',
      child: Padding(
        padding: EdgeInsets.all(16),
        child: _ReturnOutputPictureControls(),
      ),
    );
  }
}

class _ReturnOutputPictureControls extends StatefulWidget {
  const _ReturnOutputPictureControls();

  @override
  State<_ReturnOutputPictureControls> createState() =>
      _ReturnOutputPictureControlsState();
}

class _ReturnOutputPictureControlsState
    extends State<_ReturnOutputPictureControls> {
  final _brightnessKey = GlobalKey<OscRotaryKnobState>();
  final _contrastKey = GlobalKey<OscRotaryKnobState>();
  final _saturationKey = GlobalKey<OscRotaryKnobState>();
  final _hueKey = GlobalKey<OscRotaryKnobState>();

  static const double _initialBrightness = 0.5;
  static const double _initialContrast = 0.5;
  static const double _initialSaturation = 0.5;
  static const double _initialHue = 0.0;

  Widget _buildKnob({
    required String label,
    required String segment,
    required GlobalKey<OscRotaryKnobState> knobKey,
    required double initialValue,
    required double minValue,
    required double maxValue,
    List<double>? snapPoints,
    required int precision,
    bool isBipolar = false,
  }) {
    final format = '%.${precision}f';
    return OscPathSegment(
      segment: segment,
      child: OscRotaryKnob(
        key: knobKey,
        initialValue: initialValue,
        minValue: minValue,
        maxValue: maxValue,
        format: format,
        label: label,
        defaultValue: initialValue,
        isBipolar: isBipolar,
        size: 70,
        snapConfig: SnapConfig(
          snapPoints: snapPoints ?? [],
          snapRegionHalfWidth: (maxValue - minValue) * 0.02,
          snapBehavior: SnapBehavior.hard,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        _buildKnob(
          label: 'Brightness',
          segment: 'brightness',
          knobKey: _brightnessKey,
          initialValue: _initialBrightness,
          minValue: 0,
          maxValue: 1,
          snapPoints: const [0.0, 0.5, 1.0],
          precision: 3,
        ),
        _buildKnob(
          label: 'Contrast',
          segment: 'contrast',
          knobKey: _contrastKey,
          initialValue: _initialContrast,
          minValue: 0,
          maxValue: 1,
          snapPoints: const [0.0, 0.5, 1.0],
          precision: 3,
        ),
        _buildKnob(
          label: 'Saturation',
          segment: 'saturation',
          knobKey: _saturationKey,
          initialValue: _initialSaturation,
          minValue: 0,
          maxValue: 1,
          snapPoints: const [0.0, 0.5, 1.0],
          precision: 3,
        ),
        _buildKnob(
          label: 'Hue',
          segment: 'hue',
          knobKey: _hueKey,
          initialValue: _initialHue,
          minValue: -180,
          maxValue: 180,
          snapPoints: const [0.0],
          precision: 1,
          isBipolar: true,
        ),
      ],
    );
  }
}

class _ReturnOutputLutCard extends StatelessWidget {
  const _ReturnOutputLutCard();

  @override
  Widget build(BuildContext context) {
    return const LabeledCard(
      title: 'Output LUT',
      child: SizedBox(
        height: 400,
        child: Card(
          color: Color(0xFF1F1F1F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: OscPathSegment(
              segment: 'lut',
              child: LUTEditor(),
            ),
          ),
        ),
      ),
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
    return Card(
      color: const Color(0xFF1F1F1F),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
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
