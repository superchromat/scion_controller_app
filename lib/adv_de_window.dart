import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';

class AdvDeWindowCard extends StatefulWidget {
  const AdvDeWindowCard({super.key});

  @override
  State<AdvDeWindowCard> createState() => _AdvDeWindowCardState();
}

class _AdvDeWindowCardState extends State<AdvDeWindowCard> {
  // Start/End offsets for DE window. Horizontal: -512..+511, Vertical: -8..+7
  int _hStart = 0;
  int _hEnd = 0;
  int _vStart = 0;
  int _vEnd = 0;

  final _hStartKey = GlobalKey<OscRotaryKnobState>();
  final _hEndKey = GlobalKey<OscRotaryKnobState>();
  final _vStartKey = GlobalKey<OscRotaryKnobState>();
  final _vEndKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/de');
    reg.registerListener('/adv/de', _onDeMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/de', _onDeMsg);
    super.dispose();
  }

  void _onDeMsg(List<Object?> args) {
    if (args.length < 4) return;
    final hs = (args[0] as num).toInt();
    final he = (args[1] as num).toInt();
    final vs = (args[2] as num).toInt();
    final ve = (args[3] as num).toInt();
    if (!mounted) return;
    setState(() {
      _hStart = hs;
      _hEnd = he;
      _vStart = vs;
      _vEnd = ve;
    });
    _hStartKey.currentState?.setValue(hs.toDouble(), emit: false);
    _hEndKey.currentState?.setValue(he.toDouble(), emit: false);
    _vStartKey.currentState?.setValue(vs.toDouble(), emit: false);
    _vEndKey.currentState?.setValue(ve.toDouble(), emit: false);
  }

  void _sendDe() {
    context.read<Network>().sendOscMessage('/adv/de', [_hStart, _hEnd, _vStart, _vEnd]);
    OscRegistry().dispatchLocal('/adv/de', [_hStart, _hEnd, _vStart, _vEnd]);
  }

  @override
  Widget build(BuildContext context) {
    return NeumorphicContainer(
      baseColor: const Color(0xFF2A2A2C),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ADV7842 DE Window',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _deKnob('H Start', _hStartKey, -512, 511, (v) { _hStart = v; _sendDe(); }),
              _deKnob('H End', _hEndKey, -512, 511, (v) { _hEnd = v; _sendDe(); }),
              _deKnob('V Start', _vStartKey, -8, 7, (v) { _vStart = v; _sendDe(); }),
              _deKnob('V End', _vEndKey, -8, 7, (v) { _vEnd = v; _sendDe(); }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deKnob(String label, GlobalKey<OscRotaryKnobState> key,
      double min, double max, void Function(int) onCommit) {
    return OscRotaryKnob(
      key: key,
      initialValue: 0,
      minValue: min,
      maxValue: max,
      format: '%.0f',
      label: label,
      defaultValue: 0,
      size: 55,
      sendOsc: false,
      preferInteger: true,
      isBipolar: min < 0,
      snapConfig: SnapConfig(
        snapPoints: const [0.0],
        snapRegionHalfWidth: (max - min) * 0.02,
        snapBehavior: SnapBehavior.hard,
      ),
      onChanged: (v) { onCommit(v.round()); },
    );
  }
}

