import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'grid.dart';

class AdvDeWindowCard extends StatefulWidget {
  final bool embedded;

  const AdvDeWindowCard({super.key}) : embedded = false;
  const AdvDeWindowCard.embedded({super.key}) : embedded = true;

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
    final t = GridProvider.of(context);
    final knobSize = widget.embedded ? t.knobSm : t.knobMd;
    final knobWidgets = [
      _deKnob(context, 'H Start', _hStartKey, -512, 511, knobSize, (v) { _hStart = v; _sendDe(); }),
      _deKnob(context, 'H End', _hEndKey, -512, 511, knobSize, (v) { _hEnd = v; _sendDe(); }),
      _deKnob(context, 'V Start', _vStartKey, -8, 7, knobSize, (v) { _vStart = v; _sendDe(); }),
      _deKnob(context, 'V End', _vEndKey, -8, 7, knobSize, (v) { _vEnd = v; _sendDe(); }),
    ];
    final controls = widget.embedded
        ? GridRow(
            columns: 4,
            gutter: t.sm,
            equalHeight: false,
            cells: [
              for (final k in knobWidgets) (span: 1, child: k),
            ],
          )
        : Wrap(
            spacing: t.md,
            runSpacing: t.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: knobWidgets,
          );

    if (widget.embedded) {
      return Align(alignment: Alignment.centerLeft, child: controls);
    }

    return NeumorphicContainer(
      baseColor: const Color(0xFF2A2A2C),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ADV7842 DE Window',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          controls,
        ],
      ),
    );
  }

  Widget _deKnob(BuildContext context, String label, GlobalKey<OscRotaryKnobState> key,
      double min, double max, double size, void Function(int) onCommit) {
    final t = GridProvider.of(context);
    return OscRotaryKnob(
      key: key,
      initialValue: 0,
      minValue: min,
      maxValue: max,
      format: '%.0f',
      label: label,
      labelStyle: t.textLabel,
      defaultValue: 0,
      size: size,
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
