import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'osc_registry.dart';

class AdvSyncAdjustCard extends StatefulWidget {
  const AdvSyncAdjustCard({super.key});

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
    return Card(
      color: const Color(0xFF1F1F1F),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ADV7842 Sync Adjust',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _syncKnob('HS Start', _hsStartKey, -512, 511, (v) { _hsStart = v; _sendSync(); }),
                _syncKnob('HS End', _hsEndKey, -512, 511, (v) { _hsEnd = v; _sendSync(); }),
                _syncKnob('VS Start', _vsStartKey, -8, 7, (v) { _vsStart = v; _sendSync(); }),
                _syncKnob('VS End', _vsEndKey, -8, 7, (v) { _vsEnd = v; _sendSync(); }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncKnob(String label, GlobalKey<OscRotaryKnobState> key,
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

