import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_registry.dart';
import 'labeled_card.dart';
import 'grid.dart';

class AdvSyncAdjustCard extends StatefulWidget {
  final bool embedded;

  const AdvSyncAdjustCard({super.key}) : embedded = false;
  const AdvSyncAdjustCard.embedded({super.key}) : embedded = true;

  @override
  State<AdvSyncAdjustCard> createState() => _AdvSyncAdjustCardState();
}

class _AdvSyncAdjustCardState extends State<AdvSyncAdjustCard> {
  // CP manual HS/VS shift: Horizontal [-512..+511], Vertical [-8..+7]
  int _hsStart = 0;
  int _hsEnd = 0;
  int _vsStart = 0;
  int _vsEnd = 0;

  final _hsStartKey = GlobalKey<OscRotaryKnobState>();
  final _hsEndKey = GlobalKey<OscRotaryKnobState>();
  final _vsStartKey = GlobalKey<OscRotaryKnobState>();
  final _vsEndKey = GlobalKey<OscRotaryKnobState>();

  @override
  void initState() {
    super.initState();
    final reg = OscRegistry();
    reg.registerAddress('/adv/sync');
    reg.registerListener('/adv/sync', _onSyncMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/sync', _onSyncMsg);
    super.dispose();
  }

  void _onSyncMsg(List<Object?> args) {
    if (args.length < 4) return;
    final hs = (args[0] as num).toInt();
    final he = (args[1] as num).toInt();
    final vs = (args[2] as num).toInt();
    final ve = (args[3] as num).toInt();
    if (!mounted) return;
    setState(() {
      _hsStart = hs;
      _hsEnd = he;
      _vsStart = vs;
      _vsEnd = ve;
    });
    _hsStartKey.currentState?.setValue(hs.toDouble(), emit: false);
    _hsEndKey.currentState?.setValue(he.toDouble(), emit: false);
    _vsStartKey.currentState?.setValue(vs.toDouble(), emit: false);
    _vsEndKey.currentState?.setValue(ve.toDouble(), emit: false);
  }

  void _sendSync() {
    context.read<Network>().sendOscMessage('/adv/sync', [_hsStart, _hsEnd, _vsStart, _vsEnd]);
    OscRegistry().dispatchLocal('/adv/sync', [_hsStart, _hsEnd, _vsStart, _vsEnd]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final knobSize = widget.embedded ? t.knobSm : t.knobMd;
    final knobWidgets = [
      _syncKnob(context, 'HS Start', _hsStartKey, -512, 511, knobSize, (v) { _hsStart = v; _sendSync(); }),
      _syncKnob(context, 'HS End', _hsEndKey, -512, 511, knobSize, (v) { _hsEnd = v; _sendSync(); }),
      _syncKnob(context, 'VS Start', _vsStartKey, -8, 7, knobSize, (v) { _vsStart = v; _sendSync(); }),
      _syncKnob(context, 'VS End', _vsEndKey, -8, 7, knobSize, (v) { _vsEnd = v; _sendSync(); }),
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
          const Text('ADV7842 Sync Adjust',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          controls,
        ],
      ),
    );
  }

  Widget _syncKnob(BuildContext context, String label, GlobalKey<OscRotaryKnobState> key,
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
