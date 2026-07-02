// sprite_controls.dart
// Sprite placement panel: pick a sprite from the device index and show it on
// one of this send's text-region slots (2-4). Uploads are host-side
// (tools/fonts/spritectl.py); this drives /sprite/show//hide.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'grid.dart';

class SpritePanel extends StatefulWidget {
  const SpritePanel({super.key});

  @override
  State<SpritePanel> createState() => _SpritePanelState();
}

class _SpritePanelState extends State<SpritePanel> {
  int _send = 1;
  final List<String> _names = [];
  int _sprite = 0;
  int _region = 2;
  int _x = 200, _y = 200;
  bool _wired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    // Which send page are we on? The page pushes a single 'send/N' segment.
    final segs = OscPathSegment.resolvePath(context);
    final joined = segs.join('/');
    final m = RegExp(r'send/(\d)').firstMatch(joined);
    if (m != null) _send = int.parse(m.group(1)!);
    OscRegistry().registerAddress('/sprite/count');
    OscRegistry().registerListener('/sprite/count', _onCount);
    OscRegistry().registerAddress('/sprite/info');
    OscRegistry().registerListener('/sprite/info', _onInfo);
    _refresh();
  }

  @override
  void dispose() {
    OscRegistry().unregisterListener('/sprite/count', _onCount);
    OscRegistry().unregisterListener('/sprite/info', _onInfo);
    super.dispose();
  }

  void _refresh() {
    _names.clear();
    context.read<Network>().sendOscMessage('/sprite/count', const []);
  }

  void _onCount(List<Object?> args) {
    if (args.isEmpty || args.first is! int || !mounted) return;
    final n = args.first as int;
    _names.clear();
    final net = context.read<Network>();
    for (int i = 0; i < n; i++) {
      net.sendOscMessage('/sprite/info', [i]);
    }
    setState(() {});
  }

  void _onInfo(List<Object?> args) {
    // /sprite/info reply: [index, name, w, h]
    if (args.length < 2 || args[0] is! int || args[1] is! String || !mounted) {
      return;
    }
    final i = args[0] as int;
    final name = args[1] as String;
    while (_names.length <= i) {
      _names.add('');
    }
    _names[i] = name.isEmpty ? '(sprite $i)' : name;
    setState(() {});
  }

  Widget _btn(String label, VoidCallback onTap, {Color? color}) {
    final t = GridProvider.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.grey[600]!),
        ),
        child: Text(label,
            style: t.textLabel.copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _numField(String label, int value, ValueChanged<int> onCh) {
    final t = GridProvider.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: t.textLabel),
      SizedBox(width: t.xs),
      SizedBox(
        width: 64,
        child: TextFormField(
          initialValue: '$value',
          style: t.textLabel.copyWith(color: Colors.white),
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(isDense: true),
          onChanged: (s) {
            final v = int.tryParse(s);
            if (v != null) onCh(v);
          },
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Wrap(
      spacing: t.sm,
      runSpacing: t.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        DropdownButton<int>(
          value: _names.isEmpty ? null : _sprite.clamp(0, _names.length - 1),
          hint: Text('no sprites', style: t.textLabel),
          isDense: true,
          dropdownColor: const Color(0xFF2A2A2E),
          style: t.textLabel.copyWith(color: Colors.white),
          items: [
            for (int i = 0; i < _names.length; i++)
              DropdownMenuItem(value: i, child: Text(_names[i])),
          ],
          onChanged: (v) => setState(() => _sprite = v ?? 0),
        ),
        DropdownButton<int>(
          value: _region,
          isDense: true,
          dropdownColor: const Color(0xFF2A2A2E),
          style: t.textLabel.copyWith(color: Colors.white),
          items: const [
            DropdownMenuItem(value: 2, child: Text('Region 2')),
            DropdownMenuItem(value: 3, child: Text('Region 3')),
            DropdownMenuItem(value: 4, child: Text('Region 4')),
          ],
          onChanged: (v) => setState(() => _region = v ?? 2),
        ),
        _numField('X', _x, (v) => _x = v),
        _numField('Y', _y, (v) => _y = v),
        _btn('Show', () {
          context.read<Network>().sendOscMessage(
              '/sprite/show', [_send, _region, _sprite, _x, _y]);
        }, color: const Color(0xFF3A5A3A)),
        _btn('Hide', () {
          context.read<Network>().sendOscMessage(
              '/sprite/hide', [_send, _region]);
        }),
        _btn('↻', _refresh),
      ],
    );
  }
}
