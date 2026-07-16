// sprite_controls.dart
// Sprite placement panel: overlay a bitmap from the device's sprite store onto
// one of this send's OSD regions (2-4). Region chips + sprite selector on top;
// Position and Library share one row (half each) beneath. Upload/Delete manage
// the NOR sprite store in-app (asset_upload_ui.dart); spritectl.py is the CLI.

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'asset_upload_ui.dart';
import 'asset_store.dart';
import 'oklch_color_picker.dart';
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
  // sprite / position / on-air. Static + keyed by send/region so it survives
  // this panel being disposed and rebuilt on a tab switch — the device has no
  // "what's in region N" query to restore from, so we hold it here.
  static final Map<String, int> _spriteOf = {};
  static final Map<String, bool> _liveOf = {};
  static final Map<String, int> _xOf = {};
  static final Map<String, int> _yOf = {};
  // Remember which region was selected per send, so returning to the tab lands
  // on the same layer rather than snapping back to region 2.
  static final Map<int, int> _regionBySend = {};

  // The selected sprite's 16-entry palette (each entry [R, alpha, B, G] in
  // limited range, entry 0 = transparent), read from NOR for display/editing.
  Uint8List? _palette;
  int? _palLoadedFor;
  bool _palLoading = false;

  String get _rk => '$_send/$_region';
  int get _sprite => _spriteOf[_rk] ?? 0;
  bool get _live => _liveOf[_rk] ?? false;
  int get _x => _xOf[_rk] ?? 200;
  int get _y => _yOf[_rk] ?? 200;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    final joined = segs.join('/');
    final m = RegExp(r'send/(\d)').firstMatch(joined);
    if (m != null) _send = int.parse(m.group(1)!);
    _region = _regionBySend[_send] ?? 2;
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
    setState(() => _spriteOf[_rk] = v);
    if (_live) _pushShow();
  }

  void _toggleLive() {
    final now = !_live;
    setState(() => _liveOf[_rk] = now);
    if (now) {
      _pushShow();
    } else {
      _sendSprite('/assets/sprites/hide', [_send, _region]);
    }
  }

  void _setX(int v) {
    setState(() => _xOf[_rk] = v);
    if (_live) _sendSprite('/assets/sprites/move', [_send, _region, _x, _y]);
  }

  void _setY(int v) {
    setState(() => _yOf[_rk] = v);
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

  // ── Palette ────────────────────────────────────────────────────────────────
  // Limited-range (16..235) <-> full-range (0..255) per channel, matching the
  // device/upload convention (lim(v) = 16 + (v*219+127)/255).
  static int _lim(int v) => 16 + (v.clamp(0, 255) * 219 + 127) ~/ 255;
  static int _full(int v) => (((v - 16) * 255) / 219).round().clamp(0, 255);

  Color _swatchColor(int i) {
    final p = _palette;
    if (p == null || i * 4 + 3 >= p.length) return const Color(0x00000000);
    return Color.fromARGB(
        p[i * 4 + 1], _full(p[i * 4]), _full(p[i * 4 + 3]), _full(p[i * 4 + 2]));
  }

  // Load the selected sprite's palette from NOR (cheap — palette bytes only).
  void _ensurePalette() {
    if (_names.isEmpty || _palLoading) return;
    if (_palLoadedFor == _sprite && _palette != null) return;
    _palLoading = true;
    final idx = _sprite;
    SpriteStore(NorClient(context.read<Network>()))
        .fetchPalette(idx)
        .then((pal) {
      if (!mounted) return;
      setState(() {
        _palette = pal;
        _palLoadedFor = idx;
        _palLoading = false;
      });
    }).catchError((_) {
      if (mounted) _palLoading = false;
    });
  }

  // Live-recolour the shown region (no bitmap re-stream) — instant preview.
  void _pushPaletteLive() {
    final p = _palette;
    if (p == null || !_live) return;
    context
        .read<Network>()
        .sendOscMessage('/assets/sprites/palette', [_send, _region, p]);
  }

  void _applySwatch(int i, Color color, int alpha) {
    final p = _palette;
    if (p == null || i * 4 + 3 >= p.length) return;
    p[i * 4] = _lim(color.red);
    p[i * 4 + 1] = alpha.clamp(0, 255);
    p[i * 4 + 2] = _lim(color.blue);
    p[i * 4 + 3] = _lim(color.green);
    setState(() {});
    _pushPaletteLive();
  }

  Future<void> _persistPalette() async {
    final p = _palette;
    final idx = _palLoadedFor;
    if (p == null || idx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(const SnackBar(
        duration: Duration(seconds: 2), content: Text('Saving palette…')));
    try {
      await SpriteStore(NorClient(context.read<Network>()))
          .savePalette(idx, Uint8List.fromList(p));
      messenger?.showSnackBar(const SnackBar(
          duration: Duration(milliseconds: 900),
          content: Text('Palette saved')));
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(
          duration: Duration(seconds: 2), content: Text('Palette save failed')));
    }
  }

  Future<void> _editSwatch(int i) async {
    final p = _palette;
    if (p == null || i * 4 + 3 >= p.length) return;
    Color color =
        Color.fromARGB(255, _full(p[i * 4]), _full(p[i * 4 + 3]), _full(p[i * 4 + 2]));
    int alpha = p[i * 4 + 1];
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        final t = GridProvider.of(dctx);
        return StatefulBuilder(builder: (dctx, setD) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            title: Text('Palette colour $i', style: t.textHeading),
            content: SizedBox(
              width: 300,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                OklchColorPicker(
                  initialColor: color,
                  size: 150,
                  onColorChanged: (c) {
                    color = Color.fromARGB(255, c.red, c.green, c.blue);
                    _applySwatch(i, color, alpha);
                    setD(() {});
                  },
                ),
                SizedBox(height: t.md),
                Row(children: [
                  Text('Opacity', style: t.textLabel),
                  Expanded(
                    child: Slider(
                      value: alpha.toDouble(),
                      min: 0,
                      max: 255,
                      onChanged: (v) {
                        alpha = v.round();
                        _applySwatch(i, color, alpha);
                        setD(() {});
                      },
                    ),
                  ),
                  Text('${(alpha * 100 / 255).round()}%', style: t.textCaption),
                ]),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('Done')),
            ],
          );
        });
      },
    );
    if (mounted) _persistPalette();
  }

  Widget _paletteStrip(GridTokens t) {
    final sw = t.u * 2.1;
    return Wrap(
      spacing: t.xs,
      runSpacing: t.xs,
      children: [
        // Entry 0 is the transparent key; edit the 15 colour entries.
        for (int i = 1; i < 16; i++)
          GestureDetector(
            onTap: () => _editSwatch(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: sw,
                height: sw,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _CheckerPainter()),
                    Container(
                      decoration: BoxDecoration(
                        color: _swatchColor(i),
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _regionChip(GridTokens t, int r) {
    final sel = _region == r;
    return GestureDetector(
      onTap: () => setState(() {
        _region = r;
        _regionBySend[_send] = r;
      }),
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
    if (has) _ensurePalette();

    // gutter: t.md matches the Text tab's grid inset (the default would be lg,
    // which pushes the sprite content ~6px further right than the other tabs).
    Widget cell(Widget child) =>
        GridRow(columns: 1, gutter: t.md, cells: [(span: 1, child: child)]);

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
        // Palette: the selected sprite's 16 colours; tap a swatch to edit its
        // colour + opacity (live on the output when On Air).
        if (has && _palette != null)
          cell(Panel(
            title: 'Palette',
            child: _body(t, _paletteStrip(t)),
          )),
        // Position (fine-tune; canvas drag is primary) and Library share a row,
        // half each — both secondary. Keyed so the knobs reset to the selected
        // region's own x/y when the region changes.
        KeyedSubtree(
            key: ValueKey(_region),
            // Same md gutter as the single-cell rows above, so these two panels'
            // outer edges align with the Sprite panel and match the Text tab.
            child: GridRow(columns: 2, gutter: t.md, cells: [
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

// Small transparency checkerboard drawn behind palette swatches so per-entry
// opacity reads at a glance.
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cs = 5.0;
    final light = Paint()..color = const Color(0xFFB4B4B8);
    final dark = Paint()..color = const Color(0xFF6E6E74);
    for (double y = 0; y < size.height; y += cs) {
      for (double x = 0; x < size.width; x += cs) {
        final even = ((x ~/ cs) + (y ~/ cs)).isEven;
        canvas.drawRect(Rect.fromLTWH(x, y, cs, cs), even ? light : dark);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
