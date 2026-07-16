// sprite_controls.dart
// Sprite placement panel: overlay a bitmap from the device's sprite store onto
// one of this send's OSD regions (2-4). Region chips + sprite selector on top;
// Position and Library share one row (half each) beneath. Upload/Delete manage
// the NOR sprite store in-app (asset_upload_ui.dart); spritectl.py is the CLI.

import 'dart:async';
import 'package:flutter/material.dart';
import 'asset_upload_ui.dart';
import 'rotary_knob.dart';
import 'package:provider/provider.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'grid.dart';
import 'panel.dart';
import 'app_button.dart';
import 'osc_dropdown.dart';

class SpritePanel extends StatefulWidget {
  const SpritePanel({super.key});

  @override
  State<SpritePanel> createState() => _SpritePanelState();
}

class _SpritePanelState extends State<SpritePanel> {
  // Sprites overlay OSD regions 2-4 (region 1 is the legacy text overlay).
  static const List<int> _regions = [2, 3, 4];
  static const Color _onAir = Color(0xFFE0503A); // broadcast tally red
  static const Color _delete = Color(0xFFE0736A);

  int _send = 1;
  final List<String> _names = [];
  // Which indices have actually returned an info reply. Over UDP some replies
  // drop; a retry re-requests the ones still missing.
  final Set<int> _loaded = {};
  bool _gotCount = false;
  int _expected = 0;
  int _fetchTries = 0;
  Timer? _fetchTimer;
  int _region = 2;
  bool _wired = false;

  // Per-region state, so switching the region chip reflects that layer's own
  // sprite / position / on-air.
  final Map<int, int> _spriteOf = {};
  final Map<int, bool> _liveOf = {};
  final Map<int, int> _xOf = {};
  final Map<int, int> _yOf = {};

  int get _sprite => _spriteOf[_region] ?? 0;
  bool get _live => _liveOf[_region] ?? false;
  int get _x => _xOf[_region] ?? 200;
  int get _y => _yOf[_region] ?? 200;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    final joined = segs.join('/');
    final m = RegExp(r'send/(\d)').firstMatch(joined);
    if (m != null) _send = int.parse(m.group(1)!);
    OscRegistry().registerAddress('/assets/sprites/count');
    OscRegistry().registerListener('/assets/sprites/count', _onCount);
    OscRegistry().registerAddress('/assets/sprites/info');
    OscRegistry().registerListener('/assets/sprites/info', _onInfo);
    _refresh();
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    OscRegistry().unregisterListener('/assets/sprites/count', _onCount);
    OscRegistry().unregisterListener('/assets/sprites/info', _onInfo);
    super.dispose();
  }

  void _refresh() {
    _names.clear();
    _loaded.clear();
    _expected = 0;
    _gotCount = false;
    context.read<Network>().sendOscMessage('/assets/sprites/count', const []);
    _startRetry();
  }

  void _onCount(List<Object?> args) {
    if (args.isEmpty || args.first is! int || !mounted) return;
    final n = args.first as int;
    // Ignore duplicate replies from the count retry.
    if (_gotCount && n == _expected) return;
    _gotCount = true;
    _expected = n;
    _loaded.clear();
    // Placeholder names until each info reply lands, so a not-yet-loaded (or
    // dropped) slot shows '(sprite i)' rather than a blank, unselectable row.
    _names
      ..clear()
      ..addAll([for (int i = 0; i < n; i++) '(sprite $i)']);
    _requestMissing();
    setState(() {});
  }

  void _requestMissing() {
    if (!mounted) return;
    final net = context.read<Network>();
    for (int i = 0; i < _expected; i++) {
      if (!_loaded.contains(i)) {
        net.sendOscMessage('/assets/sprites/info', [i]);
      }
    }
  }

  // Over UDP the count OR any info reply can drop. Re-ask until we have the
  // count and every info reply, backing off after a handful of tries.
  void _startRetry() {
    _fetchTries = 0;
    _fetchTimer?.cancel();
    _fetchTimer = Timer.periodic(const Duration(milliseconds: 350), (tm) {
      if (!mounted || _fetchTries++ >= 8) {
        tm.cancel();
        return;
      }
      final net = context.read<Network>();
      if (!_gotCount) {
        net.sendOscMessage('/assets/sprites/count', const []);
      } else if (_loaded.length >= _expected) {
        tm.cancel();
      } else {
        _requestMissing();
      }
    });
  }

  void _onInfo(List<Object?> args) {
    // /sprite/info reply: [index, name, w, h]
    if (args.length < 2 || args[0] is! int || args[1] is! String || !mounted) {
      return;
    }
    final i = args[0] as int;
    if (i < 0) return;
    final name = args[1] as String;
    while (_names.length <= i) {
      _names.add('(sprite ${_names.length})');
    }
    _names[i] = name.isEmpty ? '(sprite $i)' : name;
    _loaded.add(i);
    setState(() {});
  }

  // Send + local echo, so the shape canvas (same app instance) can mirror the
  // sprite as a placeholder box — these commands aren't reflected by the device.
  void _sendSprite(String addr, List<Object> args) {
    context.read<Network>().sendOscMessage(addr, args);
    OscRegistry()
      ..registerAddress(addr)
      ..dispatchLocal(addr, args.cast<Object?>());
  }

  void _pushShow() =>
      _sendSprite('/assets/sprites/show', [_send, _region, _sprite, _x, _y]);

  void _selectSprite(int v) {
    setState(() => _spriteOf[_region] = v);
    if (_live) _pushShow();
  }

  void _toggleLive() {
    final now = !_live;
    setState(() => _liveOf[_region] = now);
    if (now) {
      _pushShow();
    } else {
      _sendSprite('/assets/sprites/hide', [_send, _region]);
    }
  }

  void _setX(int v) {
    setState(() => _xOf[_region] = v);
    if (_live) _sendSprite('/assets/sprites/move', [_send, _region, _x, _y]);
  }

  void _setY(int v) {
    setState(() => _yOf[_region] = v);
    if (_live) _sendSprite('/assets/sprites/move', [_send, _region, _x, _y]);
  }

  Future<void> _upload() async {
    if (await uploadSpriteFlow(context)) _refresh();
  }

  Future<void> _deleteSelected() async {
    if (_names.isEmpty) return;
    final i = _sprite.clamp(0, _names.length - 1);
    final sure = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E22),
        title: Text('Delete sprite "${_names[i]}"?',
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (sure == true && mounted && context.mounted) {
      if (await deleteSpriteFlow(context, i)) _refresh();
    }
  }

  Widget _regionChip(GridTokens t, int r) {
    final sel = _region == r;
    return GestureDetector(
      onTap: () => setState(() => _region = r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF4A6A8A) : const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: sel ? const Color(0xFF6A9ACA) : Colors.grey[600]!),
        ),
        child: Text('$r',
            style: t.textLabel.copyWith(
                fontWeight: FontWeight.w700,
                color: sel ? Colors.white : Colors.grey[300])),
      ),
    );
  }

  Widget _posKnob(
      GridTokens t, String label, int value, int max, ValueChanged<int> onCh) {
    return RotaryKnob(
      label: label,
      minValue: 0,
      maxValue: max.toDouble(),
      value: value.toDouble(),
      defaultValue: 200,
      format: '%d',
      integerOnly: true,
      size: t.knobMd,
      labelStyle: t.textLabel,
      onChanged: (v) => onCh(v.round()),
    );
  }

  // Equal interior breathing room on all four sides — combined with the Panel's
  // own xs padding this gives a uniform margin so nothing is inset unevenly.
  Widget _body(GridTokens t, Widget child) => Padding(
        padding: EdgeInsets.all(t.xs),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final has = _names.isNotEmpty;
    final spriteIdx = has ? _sprite.clamp(0, _names.length - 1) : 0;

    Widget cell(Widget child) =>
        GridRow(columns: 1, cells: [(span: 1, child: child)]);

    return CardColumn(
      spacing: t.md,
      children: [
        // Region layer picker + which sprite is loaded there + go live.
        cell(Row(
          children: [
            Text('Region', style: t.textLabel),
            SizedBox(width: t.sm),
            for (final r in _regions) ...[
              _regionChip(t, r),
              SizedBox(width: t.xs),
            ],
          ],
        )),
        cell(Panel(
          title: 'Sprite',
          child: _body(
            t,
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: NeumorphicDropdown<int>(
                    label: 'Sprite',
                    showLabel: false,
                    width: double.infinity,
                    enabled: has,
                    items: has
                        ? [for (int i = 0; i < _names.length; i++) i]
                        : const [0],
                    itemLabels: has
                        ? {for (int i = 0; i < _names.length; i++) i: _names[i]}
                        : const {0: 'no sprites'},
                    value: spriteIdx,
                    onChanged: _selectSprite,
                  ),
                ),
                SizedBox(width: t.sm),
                AppButton(
                  icon: Icons.fiber_manual_record,
                  label: 'On Air',
                  selected: _live,
                  accentColor: _onAir,
                  onPressed: has ? _toggleLive : null,
                ),
              ],
            ),
          ),
        )),
        // Position (fine-tune; canvas drag is primary) and Library share a row,
        // half each — both secondary. Keyed so the knobs reset to the selected
        // region's own x/y when the region changes.
        KeyedSubtree(
            key: ValueKey(_region),
            // No explicit gutter → same (lg) gutter as the single-cell rows
            // above, so these two panels' outer edges align with the Sprite
            // panel's edges.
            child: GridRow(columns: 2, cells: [
          (
            span: 1,
            child: Panel(
              title: 'Position',
              child: _body(
                t,
                ControlGrid(cols: 2, children: [
                  _posKnob(t, 'X', _x, 1920, _setX),
                  _posKnob(t, 'Y', _y, 1080, _setY),
                ]),
              ),
            ),
          ),
          (
            span: 1,
            child: Panel(
              title: 'Library',
              fillChild: true,
              child: Center(
                child: _body(
                  t,
                  ControlGrid(cols: has ? 2 : 1, children: [
                    AppButton(
                        icon: Icons.upload_file,
                        tooltip: 'Upload sprite',
                        onPressed: _upload),
                    if (has)
                      AppButton(
                          icon: Icons.delete_outline,
                          tooltip: 'Delete selected',
                          accentColor: _delete,
                          onPressed: _deleteSelected),
                  ]),
                ),
              ),
            ),
          ),
        ])),
      ],
    );
  }
}
