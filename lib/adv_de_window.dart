import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'numeric_slider.dart';
import 'osc_registry.dart';

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

  final _hStartKey = GlobalKey<NumericSliderState>();
  final _hEndKey = GlobalKey<NumericSliderState>();
  final _vStartKey = GlobalKey<NumericSliderState>();
  final _vEndKey = GlobalKey<NumericSliderState>();

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
    _hStartKey.currentState?.setValue(hs.toDouble(), immediate: true, emit: false);
    _hEndKey.currentState?.setValue(he.toDouble(), immediate: true, emit: false);
    _vStartKey.currentState?.setValue(vs.toDouble(), immediate: true, emit: false);
    _vEndKey.currentState?.setValue(ve.toDouble(), immediate: true, emit: false);
  }

  void _sendDe() {
    context.read<Network>().sendOscMessage('/adv/de', [_hStart, _hEnd, _vStart, _vEnd]);
    OscRegistry().dispatchLocal('/adv/de', [_hStart, _hEnd, _vStart, _vEnd]);
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
            const Text('ADV7842 DE Window',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _deSlider('H Start', _hStartKey, -512, 511, (v) { _hStart = v; _sendDe(); }),
                _deSlider('H End', _hEndKey, -512, 511, (v) { _hEnd = v; _sendDe(); }),
                _deSlider('V Start', _vStartKey, -8, 7, (v) { _vStart = v; _sendDe(); }),
                _deSlider('V End', _vEndKey, -8, 7, (v) { _vEnd = v; _sendDe(); }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _deSlider(String label, GlobalKey<NumericSliderState> key,
      double min, double max, void Function(int) onCommit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 70, child: Text(label)),
        SizedBox(
          width: 200,
          height: 24,
          child: NumericSlider(
            key: key,
            value: 0,
            range: RangeValues(min, max),
            detents: const [],
            precision: 0,
            hardDetents: false,
            sendOsc: false,
            onChanged: (v) { onCommit(v.round()); },
          ),
        ),
      ],
    );
  }
}

