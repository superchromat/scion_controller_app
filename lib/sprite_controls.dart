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
import 'shape_selection.dart';
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
  static const Color _show = Color(0xFF4E8A62);  // subtle "shown" green

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
  ShapeSelection? _sel;

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
  // Which palette index (if any) is driven by the "copper bars" per-scanline
  // rainbow, keyed by send/region. The device has one copper target, so only
  // the most-recently-enabled entry actually rainbows on hardware.
  static final Map<String, int> _copperOf = {};
  // Per-region pixel-doubling factor (1/2/4) via the OSD layer's H/V repeat.
  static final Map<String, int> _scaleOf = {};

  // The selected sprite's 16-entry palette (each entry [R, alpha, B, G] in
  // limited range, entry 0 = transparent), read from NOR for display/editing.
  Uint8List? _palette;
  int? _palLoadedFor;
  bool _palLoading = false;

  String get _rk => '$_send/$_region';
  int get _sprite => _spriteOf[_rk] ?? 0;
  bool get _live => _liveOf[_rk] ?? false;
  int? get _copper => _copperOf[_rk];
  int get _x => _xOf[_rk] ?? 200;
  int get _y => _yOf[_rk] ?? 200;
  int get _scale => _scaleOf[_rk] ?? 1;

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
    // Canvas drags echo /move locally — mirror the position into the knobs.
    OscRegistry().registerAddress('/assets/sprites/move');
    OscRegistry().registerListener('/assets/sprites/move', _onMoveEcho);
    // Device reset clears everything on-device — drop stale local live/scale.
    OscRegistry().registerAddress('/config/reset');
    OscRegistry().registerListener('/config/reset', _onReset);
    // Shared canvas/editor selection (provided by Shape): follow canvas taps,
    // drive the canvas highlight from the region chips.
    _sel = context.read<ShapeSelection>();
    _sel!.addListener(_onSel);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sel = _sel;
      if (sel == null || !mounted) return;
      if (sel.kind == ShapeSel.sprite) {
        if (sel.region != _region) {
          setState(() => _region = sel.region);
          _regionBySend[_send] = sel.region;
        }
      } else {
        sel.select(ShapeSel.sprite, _region);
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    _sel?.removeListener(_onSel);
    OscRegistry().unregisterListener('/assets/sprites/count', _onCount);
    OscRegistry().unregisterListener('/assets/sprites/info', _onInfo);
    OscRegistry().unregisterListener('/assets/sprites/move', _onMoveEcho);
    OscRegistry().unregisterListener('/config/reset', _onReset);
    super.dispose();
  }

  // Canvas drag (or any /move) for the selected region — reflect x/y in the knobs.
  void _onMoveEcho(List<Object?> a) {
    if (!mounted || a.length < 4 || a.any((e) => e is! num)) return;
    if ((a[0] as num).toInt() != _send || (a[1] as num).toInt() != _region) {
      return;
    }
    setState(() {
      _xOf[_rk] = (a[2] as num).toInt();
      _yOf[_rk] = (a[3] as num).toInt();
    });
  }

  // Device reset to defaults: nothing is shown on-device any more.
  void _onReset(List<Object?> a) {
    if (!mounted) return;
    setState(() {
      _liveOf.clear();
      _scaleOf.clear();
      _copperOf.clear();
    });
  }

  void _onSel() {
    final sel = _sel;
    if (sel == null || !mounted) return;
    if (sel.kind == ShapeSel.sprite && sel.region != _region) {
      setState(() => _region = sel.region);
      _regionBySend[_send] = sel.region;
    }
  }

  void _selectRegion(int r) {
    setState(() {
      _region = r;
      _regionBySend[_send] = r;
    });
    _sel?.select(ShapeSel.sprite, r);
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

  void _pushShow() {
    _sendSprite('/assets/sprites/show', [_send, _region, _sprite, _x, _y]);
    // Re-apply the pixel scale — a fresh show resets the layer repeat to 1x.
    if (_scale != 1) {
      _sendSprite('/assets/sprites/scale', [_send, _region, _scale]);
    }
  }

  void _setScale(int n) {
    setState(() => _scaleOf[_rk] = n);
    if (_live) _sendSprite('/assets/sprites/scale', [_send, _region, n]);
  }

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

  // Toggle the per-scanline "copper bars" rainbow on palette entry `i`. The
  // device drives one entry per line from the HS-capture ISR, so only that
  // colour animates. Turning it off (or moving it to another entry) re-pushes
  // the stored palette so the entry snaps back to its real colour.
  void _setCopper(int i, bool on) {
    final net = context.read<Network>();
    final prev = _copper;
    if (on) {
      _copperOf[_rk] = i;
      net.sendOscMessage('/assets/sprites/copper', [_send, _region, i, 1]);
    } else {
      _copperOf.remove(_rk);
      net.sendOscMessage('/assets/sprites/copper', [_send, _region, i, 0]);
    }
    // Restore the real colours of any entry we just released.
    if (!on || (prev != null && prev != i)) _pushPaletteLive();
    setState(() {});
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
                SizedBox(height: t.md),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    icon: Icons.gradient,
                    label: _copper == i ? 'Copper on' : 'Copper',
                    selected: _copper == i,
                    accentColor: const Color(0xFF7A5CFF),
                    onPressed: () {
                      _setCopper(i, _copper != i);
                      setD(() {});
                    },
                  ),
                ),
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

  // Display order for the 15 colour entries: sorted dark->light by luma, then
  // by chroma, so the palette reads as an ordered ramp. Returns the actual
  // entry indices (1..15) so edits still target the right palette slot.
  List<int> _paletteOrder() {
    final p = _palette;
    final order = [for (int i = 1; i <= 15; i++) i];
    if (p == null) return order;
    double luma(int i) {
      final r = _full(p[i * 4]).toDouble();
      final g = _full(p[i * 4 + 3]).toDouble();
      final b = _full(p[i * 4 + 2]).toDouble();
      return 0.299 * r + 0.587 * g + 0.114 * b;
    }

    int chroma(int i) {
      final r = _full(p[i * 4]), g = _full(p[i * 4 + 3]), b = _full(p[i * 4 + 2]);
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      return mx - mn;
    }

    order.sort((a, b) {
      final c = luma(a).compareTo(luma(b));
      return c != 0 ? c : chroma(a).compareTo(chroma(b));
    });
    return order;
  }

  Widget _paletteStrip(GridTokens t) {
    // 15 editable colour entries (entry 0 is the transparent key), each an
    // equal-width square so they all sit on one line. Expanded+AspectRatio
    // (rather than LayoutBuilder) keeps this measurable inside the grid's
    // IntrinsicHeight rows.
    final gap = t.xs;
    return Row(
      children: [
        for (final i in _paletteOrder())
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: AspectRatio(
                aspectRatio: 1,
                child: GestureDetector(
                  onTap: () => _editSwatch(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(painter: _CheckerPainter()),
                        Container(
                          decoration: BoxDecoration(
                            color: _swatchColor(i),
                            border: Border.all(
                              color: _copper == i
                                  ? const Color(0xFF7A5CFF)
                                  : Colors.white24,
                              width: _copper == i ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Pixel-doubling scale: 1x / 2x / 4x via the OSD layer's hardware pixel
  // repeat (no re-render). Sits in the bottom-right where Library used to be.
  Widget _resizeControls(GridTokens t) {
    final has = _names.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Pixel scale', style: t.textLabel),
        SizedBox(height: t.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final s in const [1, 2, 4]) ...[
              _scaleChip(t, s, has),
              if (s != 4) SizedBox(width: t.xs),
            ],
          ],
        ),
      ],
    );
  }

  Widget _scaleChip(GridTokens t, int s, bool enabled) {
    final selected = _scale == s;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? () => _setScale(s) : null,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF4A6A8A) : const Color(0xFF2A2A2C),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
                color: selected ? const Color(0xFF6A9ACA) : Colors.grey[600]!),
          ),
          child: Text('$s×',
              style: t.textLabel.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : Colors.grey[300])),
        ),
      ),
    );
  }

  Widget _regionChip(GridTokens t, int r) {
    final selected = _region == r;
    // A region holding text can't also hold a sprite: disable and grey it.
    final blocked = context.watch<ShapeSelection>().textOccupied(r);
    final chip = GestureDetector(
      onTap: blocked ? null : () => _selectRegion(r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.md, vertical: t.xs),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF4A6A8A) : const Color(0xFF2A2A2C),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
              color: selected ? const Color(0xFF6A9ACA) : Colors.grey[600]!),
        ),
        child: Text('$r',
            style: t.textLabel.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : Colors.grey[300])),
      ),
    );
    return Opacity(
      opacity: blocked ? 0.35 : 1.0,
      child: blocked
          ? Tooltip(
              message: 'Region $r has text',
              child:
                  MouseRegion(cursor: SystemMouseCursors.forbidden, child: chip))
          : chip,
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
        // Sprite picker + upload + show/hide, top-level (no card chrome) to
        // save vertical space.
        cell(Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: NeumorphicDropdown<int>(
                label: 'Sprite',
                showLabel: false,
                width: double.infinity,
                height: 40, // match the buttons beside it
                enabled: has,
                items:
                    has ? [for (int i = 0; i < _names.length; i++) i] : const [0],
                itemLabels: has
                    ? {for (int i = 0; i < _names.length; i++) i: _names[i]}
                    : const {0: 'no sprites'},
                value: spriteIdx,
                onChanged: _selectSprite,
              ),
            ),
            SizedBox(width: t.sm),
            AppButton(
              icon: Icons.upload_file,
              tooltip: 'Upload sprite',
              onPressed: _upload,
            ),
            SizedBox(width: t.sm),
            // Fixed width so the label swap (Show <-> Hide) doesn't reflow the row.
            SizedBox(
              width: 104,
              child: AppButton(
                icon: _live ? Icons.visibility_off : Icons.visibility,
                label: _live ? 'Hide' : 'Show',
                selected: _live,
                accentColor: _show,
                onPressed: has ? _toggleLive : null,
              ),
            ),
          ],
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
              title: 'Resize',
              fillChild: true,
              child: Center(child: _body(t, _resizeControls(t))),
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
