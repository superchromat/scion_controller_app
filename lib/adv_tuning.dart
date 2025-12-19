import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'osc_registry.dart';
import 'numeric_slider.dart';

class AdvTuningCard extends StatefulWidget {
  const AdvTuningCard({super.key});

  @override
  State<AdvTuningCard> createState() => _AdvTuningCardState();
}

class _AdvTuningCardState extends State<AdvTuningCard> {
  bool _dllEnabled = false;
  int _phase = 0; // 0..63

  // DE parameters
  int _hStart = 0;
  int _hWidth = 0;
  int _vStart = 0;
  int _vHeight = 0;

  final _phaseKey = GlobalKey<NumericSliderState>();
  final _hStartKey = GlobalKey<NumericSliderState>();
  final _hWidthKey = GlobalKey<NumericSliderState>();
  final _vStartKey = GlobalKey<NumericSliderState>();
  final _vHeightKey = GlobalKey<NumericSliderState>();

  @override
  void initState() {
    super.initState();
    // Register for incoming updates
    final reg = OscRegistry();
    reg.registerAddress('/adv/dll');
    reg.registerListener('/adv/dll', _onDllMsg);
    reg.registerAddress('/adv/phase');
    reg.registerListener('/adv/phase', _onPhaseMsg);
    reg.registerAddress('/adv/de');
    reg.registerListener('/adv/de', _onDeMsg);
  }

  @override
  void dispose() {
    final reg = OscRegistry();
    reg.unregisterListener('/adv/dll', _onDllMsg);
    reg.unregisterListener('/adv/phase', _onPhaseMsg);
    reg.unregisterListener('/adv/de', _onDeMsg);
    super.dispose();
  }

  void _send(String addr, List<Object> args) {
    context.read<Network>().sendOscMessage(addr, args);
    // local echo so UI reflects immediately
    OscRegistry().dispatchLocal(addr, args);
  }

  void _onDllMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt() != 0;
    if (mounted) setState(() => _dllEnabled = v);
  }

  void _onPhaseMsg(List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toInt().clamp(0, 63);
    if (mounted) {
      setState(() => _phase = v);
      _phaseKey.currentState?.setValue(v.toDouble(), immediate: true, emit: false);
    }
  }

  void _onDeMsg(List<Object?> args) {
    if (args.length < 4) return;
    int hs = (args[0] as num).toInt();
    int hw = (args[1] as num).toInt();
    int vs = (args[2] as num).toInt();
    int vh = (args[3] as num).toInt();
    if (mounted) {
      setState(() {
        _hStart = hs; _hWidth = hw; _vStart = vs; _vHeight = vh;
      });
      _hStartKey.currentState?.setValue(hs.toDouble(), immediate: true, emit: false);
      _hWidthKey.currentState?.setValue(hw.toDouble(), immediate: true, emit: false);
      _vStartKey.currentState?.setValue(vs.toDouble(), immediate: true, emit: false);
      _vHeightKey.currentState?.setValue(vh.toDouble(), immediate: true, emit: false);
    }
  }

  void _sendDe() {
    _send('/adv/de', [_hStart, _hWidth, _vStart, _vHeight]);
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
            const Text('ADC / ADV7842 Tuning',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Switch(
                  value: _dllEnabled,
                  onChanged: (v) {
                    _dllEnabled = v;
                    setState(() {});
                    _send('/adv/dll', [v ? 1 : 0]);
                  },
                ),
                const SizedBox(width: 8),
                const Text('LLC DLL Enable'),
                const Spacer(),
                const Text('Phase'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 200,
                  height: 24,
                  child: NumericSlider(
                    key: _phaseKey,
                    value: _phase.toDouble(),
                    range: const RangeValues(0, 63),
                    detents: const [],
                    precision: 0,
                    hardDetents: false,
                    sendOsc: false,
                    onChanged: (v) {
                      final iv = v.round().clamp(0, 63);
                      _phase = iv;
                      _send('/adv/phase', [iv]);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _deSlider('H Start', _hStartKey, 0, 2200, (v){ _hStart = v; _sendDe(); }),
                _deSlider('H Width', _hWidthKey, 0, 2200, (v){ _hWidth = v; _sendDe(); }),
                _deSlider('V Start', _vStartKey, 0, 200, (v){ _vStart = v; _sendDe(); }),
                _deSlider('V Height', _vHeightKey, 0, 1080, (v){ _vHeight = v; _sendDe(); }),
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
            onChanged: (v) {
              onCommit(v.round());
            },
          ),
        ),
      ],
    );
  }
}

