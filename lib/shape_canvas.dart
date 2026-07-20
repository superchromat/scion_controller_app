// shape_canvas.dart — direct-manipulation Shape widget, two-way bound to OSC.
//
// The left-hand canvas of the Shape control: scale (outer corners), crop (inner
// edge bars), rotation (grip), position (Move tool), keystone (double-click a
// corner to free it), and — Send 1 only — a free-form warp mesh (Warp tool).
//
// Binding: it listens to the same /…/shape/* OSC addresses the knobs use, so
// turning a knob moves the canvas; dragging a handle sends OSC (+ local echo),
// so the canvas moves the knobs. No device round-trip needed (local registry).
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'drag_area.dart';
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';
import 'shape_selection.dart';

const _amber = Color(0xFFF0B830);
const _blue = Color(0xFF9AA6FF);
const _teal = Color(0xFF66E0C0);
const _green = Color(0xFF56C271);

// Output raster the canvas maps into (px). Keystone corners + mesh points are
// sent in these coordinates.
const double _outW = 1920, _outH = 1080;
const int _warpMeshMax = 9;

class ShapeCanvas extends StatefulWidget {
  final int?
      pageNumber; // null/1 = Send 1 (full rig); 2/3 = reduced; Return uses 2 under /output
  // Which editing overlay to show, driven by the active tab on the Shape page:
  // 'transform' (scale/crop/warp handles), 'text' / 'sprites' (screen-space
  // placeholder boxes), or 'colorField' (the uniformity gain mesh).
  final String overlay;
  const ShapeCanvas({super.key, this.pageNumber, this.overlay = 'transform'});
  @override
  State<ShapeCanvas> createState() => _ShapeCanvasState();
}

class _ShapeCanvasState extends State<ShapeCanvas> {
  // ── bound shape state (OSC units) ──────────────────────────────────────────
  double scaleX = 1, scaleY = 1;
  double posX = 0.5, posY = 0.5;
  double rotOsc = 180; // 0..360, 180 = identity
  double cl = 0, cr = 0, ct = 0, cb = 0; // crop 0..0.95
  // Send-1 warp (parametric — the canvas reflects the knobs and drives them back)
  double keyH = 0,
      keyV = 0,
      shearX = 0,
      shearY = 0; // keystone/shear px (output)
  double barrel = 0; // lens k2 x1000 (<0 barrel)
  double lensX = 0, lensY = 0; // lens optical centre px (output)
  int meshN = 0;
  final List<Offset> mesh =
      List<Offset>.filled(_warpMeshMax * _warpMeshMax, Offset.zero); // px

  // ── device warp LUT (source→output forward map, the real deformation) ────────
  // Frame-normalized output positions for a regular _lutN×_lutN source grid.
  // The device composes every warp stage (keystone/barrel/lens/field/mesh) at
  // the live animation phase, so this is the authoritative deformation — the
  // client just draws it. Null until the first reply / offline.
  List<Offset>? _lut;
  int _lutN = 0;
  Timer? _lutPoll;
  bool _lutDirty = false;
  // Animation params — tracked only to decide when to poll the LUT live.
  int _fieldType = 0;
  double _famp = 0, _wob = 0, _brea = 0, _roam = 0;
  bool get _animating =>
      (_fieldType != 0 && _famp > 0) || _wob > 0 || _brea > 0 || _roam > 0;

  // ── text overlay (screen-space OSD placeholders, output pixels) ─────────────
  // Regions 1-4; region 1 aliases the legacy flat /text/* fields on the device.
  final List<String> _txtStr = List.filled(4, '');
  final List<double> _txtX = List.filled(4, 100);
  final List<double> _txtY = List.filled(4, 100);
  final List<double> _txtSize = List.filled(4, 48);

  // ── sprite overlay ──────────────────────────────────────────────────────────
  // Tracked from /assets/sprites/{show,move,hide} for this send (the panel
  // echoes them locally, so canvas + panel stay in sync in-session). Keyed by
  // region (2..4). info map: sprite index → (name, w, h) in output px.
  final Map<int, _SpriteBox> _sprites = {};
  final Map<int, ({String name, int w, int h})> _spriteInfo = {};

  // ── colour-field mesh (UC block, Send-1 output) ─────────────────────────────
  // Authored as control points (position + colour + falloff); the client bakes
  // them into the fixed gain grid and streams it via /color/field/cells. The
  // block is darken-only (10-bit gains, 1023 ≈ unity), so a point's colour is a
  // target reached by attenuating the *other* channels.
  final int _ucNx = 20, _ucNy = 11; // bake grid (220 cells, one packet)
  final List<_UcPoint> _ucPts = [];
  List<int> _ucR = [], _ucG = [], _ucB = []; // baked gains 0..1023, row-major
  int? _ucSel; // selected control point
  String _ucMode = 'A'; // A = falloff (fade to neutral), B = gradient fill
  Timer? _ucTimer; // coalesces bake→send during a drag
  bool _ucDirty = false;
  int _ucAddHue = 0; // cycles the colour of freshly-dropped points

  // Addresses to re-query (empty-arg readback) on connect / after a reset —
  // the text + colour-field state the overlays reflect.
  final List<String> _extraQuery = [];

  // ── ui state ───────────────────────────────────────────────────────────────
  String tool = 'move'; // move | warp
  String? _drag;
  double _px0 = 0, _py0 = 0;
  Offset _p0 = Offset.zero;
  Size _size = Size.zero;
  Offset _stageOffset = Offset.zero;
  Offset? _hover;

  String get _overlay => widget.overlay;
  bool get _full => widget.pageNumber == null || widget.pageNumber == 1;
  bool get _canRotate => _full; // rotation/keystone/warp are Send-1 only
  double get rotDeg => rotOsc - 180; // degrees from identity

  // Send number the sprite messages (/assets/sprites/*) address — parsed from
  // the resolved OSC path, matching SpritePanel (defaults to 1 off /output).
  int _sendIdx = 1;

  String _base = '';
  bool _wired = false;
  final Map<String, void Function(List<Object?>)> _subs = {};

  // Shared selection/occupancy (provided by Shape). The canvas highlights the
  // selected region and writes the selection on tap; it also feeds occupancy
  // (which regions hold text vs a sprite) from the state it already mirrors.
  ShapeSelection? _sel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sel = context.read<ShapeSelection>();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
    final sm = RegExp(r'send/(\d)').firstMatch(segs.join('/'));
    if (sm != null) _sendIdx = int.parse(sm.group(1)!);
    _bindD('shape/scale/x', (v) => scaleX = v);
    _bindD('shape/scale/y', (v) => scaleY = v);
    _bindD('shape/pos/x', (v) => posX = v);
    _bindD('shape/pos/y', (v) => posY = v);
    _bindD('shape/crop/left', (v) => cl = v);
    _bindD('shape/crop/right', (v) => cr = v);
    _bindD('shape/crop/top', (v) => ct = v);
    _bindD('shape/crop/bottom', (v) => cb = v);
    if (_canRotate) _bindD('shape/rotation', (v) => rotOsc = v);
    if (_full) {
      _bindD('shape/warp/key_h', (v) => keyH = v);
      _bindD('shape/warp/key_v', (v) => keyV = v);
      _bindD('shape/warp/shear_x', (v) => shearX = v);
      _bindD('shape/warp/shear_y', (v) => shearY = v);
      _bindD('shape/warp/barrel', (v) => barrel = v);
      _bindD('shape/warp/lens_x', (v) => lensX = v);
      _bindD('shape/warp/lens_y', (v) => lensY = v);
      _bindI('shape/warp/mesh/size', (v) => meshN = v.clamp(0, _warpMeshMax));
      _bindMesh();
      // Animation params — tracked so we know when to poll the LUT live.
      _bindI('shape/warp/field', (v) => _fieldType = v);
      _bindD('shape/warp/famp', (v) => _famp = v);
      _bindD('shape/warp/wobble', (v) => _wob = v);
      _bindD('shape/warp/breathe', (v) => _brea = v);
      _bindD('shape/warp/roam', (v) => _roam = v);
      _bindLut();
      // One throttled pump (~15 Hz) drives both change-driven refreshes (a knob
      // moved / a handle was dragged → _lutDirty) and live animation (the device
      // engine only recomputes at ~8 Hz anyway). Coalescing here keeps a fast
      // drag from flooding the device with Newton-solve queries.
      _lutPoll = Timer.periodic(const Duration(milliseconds: 66), (_) {
        if (_lutDirty || _animating) {
          _lutDirty = false;
          _requestLut();
        }
      });
      // Seed the first LUT once the widget is mounted / connected.
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestLut());
    }

    // ── text / sprite / colour-field overlay bindings ─────────────────────────
    _bindOverlays();

    // Pull initial state for the overlay readbacks + sprite catalogue once the
    // widget is connected (the device replies flow back through the listeners).
    WidgetsBinding.instance.addPostFrameCallback((_) => _queryOverlays());

    // A preset reset applies defaults on the device but doesn't broadcast them,
    // so re-query our addresses whenever any reset completes — the replies flow
    // back through the same listeners and refresh the canvas.
    const resetAddr = '/assets/presets/reset';
    OscRegistry().registerAddress(resetAddr);
    void onReset(List<Object?> _) {
      final net = context.read<Network>();
      for (final a in _subs.keys.toList()) {
        if (a.startsWith('$_base/shape')) net.sendOscMessage(a, const []);
      }
      // Reset clears text/colour-field state too; the sprite overlays drop since
      // a reset disables them on the device.
      _sprites.clear();
      _queryOverlays();
    }

    _subs[resetAddr] = onReset;
    OscRegistry().registerListener(resetAddr, onReset);
  }

  void _bindD(String rel, void Function(double) set) {
    final addr = '$_base/$rel';
    final reg = OscRegistry()..registerAddress(addr);
    final cur = reg.allParams[addr]?.currentValue;
    if (cur != null && cur.isNotEmpty && cur.first is num)
      set((cur.first as num).toDouble());
    void cb(List<Object?> a) {
      if (a.isNotEmpty && a.first is num && mounted) {
        setState(() => set((a.first as num).toDouble()));
        _scheduleLut();
      }
    }

    _subs[addr] = cb;
    reg.registerListener(addr, cb);
  }

  void _bindI(String rel, void Function(int) set) {
    final addr = '$_base/$rel';
    final reg = OscRegistry()..registerAddress(addr);
    final cur = reg.allParams[addr]?.currentValue;
    if (cur != null && cur.isNotEmpty && cur.first is num)
      set((cur.first as num).toInt());
    void cb(List<Object?> a) {
      if (a.isNotEmpty && a.first is num && mounted) {
        setState(() => set((a.first as num).toInt()));
        _scheduleLut();
      }
    }

    _subs[addr] = cb;
    reg.registerListener(addr, cb);
  }

  // Bind the device forward-map readback. Reply: [N, out_w, out_h, blob] where
  // blob is N*N little-endian int16 (oxn,oyn) pairs, Q12 (/4096).
  void _bindLut() {
    final addr = '$_base/shape/warp/lut';
    final reg = OscRegistry()..registerAddress(addr);
    void cb(List<Object?> a) {
      if (a.length < 4 || a[0] is! num || a[3] is! Uint8List) return;
      final n = (a[0] as num).toInt();
      final bytes = a[3] as Uint8List;
      if (n < 2 || bytes.length < n * n * 4) return;
      final bd = ByteData.sublistView(bytes);
      final pts = List<Offset>.generate(
          n * n,
          (k) => Offset(bd.getInt16(k * 4, Endian.little) / 4096.0,
              bd.getInt16(k * 4 + 2, Endian.little) / 4096.0));
      if (!mounted) return;
      setState(() {
        _lutN = n;
        _lut = pts;
      });
    }

    _subs[addr] = cb;
    reg.registerListener(addr, cb);
  }

  void _requestLut() {
    if (!mounted) return;
    context.read<Network>().sendOscMessage('$_base/shape/warp/lut', const []);
  }

  // Mark the LUT stale; the throttled pump re-queries on its next tick.
  void _scheduleLut() => _lutDirty = true;

  // Full-mesh readback (device replies "i" N + blob) — keeps the canvas in sync
  // with a saved/loaded mesh.
  void _bindMesh() {
    final addr = '$_base/shape/warp/mesh';
    final reg = OscRegistry()..registerAddress(addr);
    void cb(List<Object?> a) {
      if (a.isEmpty || a.first is! num) return;
      final n = (a.first as num).toInt().clamp(0, _warpMeshMax);
      if (!mounted) return;
      setState(() {
        meshN = n;
        if (a.length > 1 && a[1] is List) {
          final vals = (a[1] as List).cast<num>();
          for (int k = 0; k < n * n && (k * 2 + 1) < vals.length; k++) {
            mesh[k] =
                Offset(vals[k * 2].toDouble(), vals[k * 2 + 1].toDouble());
          }
        }
      });
    }

    _subs[addr] = cb;
    reg.registerListener(addr, cb);
  }

  // ── overlay bindings (text / sprites / colour field) ────────────────────────
  bool _seeding = false;

  // Register a listener that mutates overlay state then repaints. Seeds from the
  // registry's cached value (without a spurious setState). `query` marks the
  // address for an empty-arg readback on connect / reset.
  void _listen(String addr, void Function(List<Object?>) parse,
      {bool query = false}) {
    final reg = OscRegistry()..registerAddress(addr);
    void cb(List<Object?> a) {
      parse(a);
      if (!_seeding && mounted) setState(() {});
    }

    final cur = reg.allParams[addr]?.currentValue;
    if (cur != null && cur.isNotEmpty) {
      _seeding = true;
      cb(cur);
      _seeding = false;
    }
    _subs[addr] = cb;
    reg.registerListener(addr, cb);
    if (query) _extraQuery.add(addr);
  }

  void _bindOverlays() {
    // Text regions 1-4 (region 1 aliases the legacy flat /text/* fields).
    for (int m = 1; m <= 4; m++) {
      final rb = 'text/region/$m';
      final i = m - 1;
      _listen('$_base/$rb/string', (a) {
        if (a.isNotEmpty && a.first is String) _txtStr[i] = a.first as String;
      }, query: true);
      _listen('$_base/$rb/pos/x', (a) {
        if (a.isNotEmpty && a.first is num)
          _txtX[i] = (a.first as num).toDouble();
      }, query: true);
      _listen('$_base/$rb/pos/y', (a) {
        if (a.isNotEmpty && a.first is num)
          _txtY[i] = (a.first as num).toDouble();
      }, query: true);
      _listen('$_base/$rb/size', (a) {
        if (a.isNotEmpty && a.first is num) {
          final v = (a.first as num).toDouble();
          if (v > 0) _txtSize[i] = v;
        }
      }, query: true);
    }

    // Sprites — tracked from the global command echoes (the sprite panel mirrors
    // its sends locally, so this canvas hears show/move/hide in-session).
    _listen('/assets/sprites/show', _onSpriteShow);
    _listen('/assets/sprites/move', _onSpriteMove);
    _listen('/assets/sprites/hide', _onSpriteHide);
    _listen('/assets/sprites/info', _onSpriteInfo);
    _listen('/assets/sprites/count', _onSpriteCount);
    // Device reset clears the on-device overlays — drop the placeholder boxes.
    _listen('/config/reset', (a) => _sprites.clear());

    // Colour-field mesh (UC block is Send-1 output only). Control points are a
    // client-side authoring layer — the device only stores the baked grid — so
    // there's nothing to read back; we allocate a neutral buffer and stream it
    // as the user paints. A short timer coalesces bakes during a drag.
    if (_full) {
      _ucR = List.filled(_ucNx * _ucNy, 1023);
      _ucG = List.filled(_ucNx * _ucNy, 1023);
      _ucB = List.filled(_ucNx * _ucNy, 1023);
      _ucTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (_ucDirty) {
          _ucDirty = false;
          _ucSend();
        }
      });
    }
  }

  void _queryOverlays() {
    if (!mounted) return;
    final net = context.read<Network>();
    for (final a in _extraQuery) net.sendOscMessage(a, const []);
    net.sendOscMessage(
        '/assets/sprites/count', const []); // repopulate catalogue
  }

  // ── sprite tracking ─────────────────────────────────────────────────────────
  void _onSpriteShow(List<Object?> a) {
    if (a.length < 5 || a.any((e) => e is! num)) return;
    final send = (a[0] as num).toInt();
    if (send != _sendIdx) return;
    final region = (a[1] as num).toInt();
    _sprites[region] = _SpriteBox(
        sprite: (a[2] as num).toInt(),
        x: (a[3] as num).toDouble(),
        y: (a[4] as num).toDouble());
  }

  void _onSpriteMove(List<Object?> a) {
    if (a.length < 4 || a.any((e) => e is! num)) return;
    if ((a[0] as num).toInt() != _sendIdx) return;
    final region = (a[1] as num).toInt();
    final b = _sprites[region];
    if (b != null) {
      b.x = (a[2] as num).toDouble();
      b.y = (a[3] as num).toDouble();
    }
  }

  void _onSpriteHide(List<Object?> a) {
    if (a.length < 2 || a.any((e) => e is! num)) return;
    if ((a[0] as num).toInt() != _sendIdx) return;
    _sprites.remove((a[1] as num).toInt());
  }

  void _onSpriteInfo(List<Object?> a) {
    // reply: [index, name, w, h]
    if (a.length < 4 || a[0] is! num || a[1] is! String) return;
    final i = (a[0] as num).toInt();
    final w = a[2] is num ? (a[2] as num).toInt() : 0;
    final h = a[3] is num ? (a[3] as num).toInt() : 0;
    _spriteInfo[i] = (name: a[1] as String, w: w, h: h);
  }

  void _onSpriteCount(List<Object?> a) {
    if (a.isEmpty || a.first is! num || !mounted) return;
    final n = (a.first as num).toInt();
    final net = context.read<Network>();
    for (int i = 0; i < n; i++) net.sendOscMessage('/assets/sprites/info', [i]);
  }

  // ── colour-field mesh helpers ────────────────────────────────────────────────
  static const double _ucAspect = _outW / _outH;

  // Bake the control points into the gain grid and flag a (throttled) send.
  void _ucBake() {
    if (_ucR.length < _ucNx * _ucNy) return;
    for (int cy = 0; cy < _ucNy; cy++) {
      for (int cx = 0; cx < _ucNx; cx++) {
        final g = _ucGainAt((cx + 0.5) / _ucNx, (cy + 0.5) / _ucNy);
        final k = cy * _ucNx + cx;
        _ucR[k] = (g[0] * 1023).round().clamp(0, 1023);
        _ucG[k] = (g[1] * 1023).round().clamp(0, 1023);
        _ucB[k] = (g[2] * 1023).round().clamp(0, 1023);
      }
    }
    _ucDirty = true;
  }

  // Per-channel gain (0..1, 1 = no effect) at a normalized frame position.
  List<double> _ucGainAt(double sx, double sy) {
    if (_ucPts.isEmpty) return const [1.0, 1.0, 1.0];
    double cr = 0, cg = 0, cb = 0, sumW = 0;
    if (_ucMode == 'A') {
      double prod = 1;
      for (final p in _ucPts) {
        final dx = (sx - p.x) * _ucAspect, dy = sy - p.y;
        final d = math.sqrt(dx * dx + dy * dy);
        final t = (d / (p.radius <= 0 ? 0.001 : p.radius)).clamp(0.0, 1.0);
        final infl = p.amount * _smoother(1 - t);
        if (infl <= 0) continue;
        prod *= (1 - infl);
        cr += p.rgb[0] * infl;
        cg += p.rgb[1] * infl;
        cb += p.rgb[2] * infl;
        sumW += infl;
      }
      if (sumW <= 1e-6) return const [1.0, 1.0, 1.0];
      final s = 1 - prod;
      return [
        1 - s * (1 - cr / sumW),
        1 - s * (1 - cg / sumW),
        1 - s * (1 - cb / sumW)
      ];
    } else {
      double sumAmt = 0;
      for (final p in _ucPts) {
        final dx = (sx - p.x) * _ucAspect, dy = sy - p.y;
        final w = 1 / (dx * dx + dy * dy + 0.0009);
        cr += p.rgb[0] * w;
        cg += p.rgb[1] * w;
        cb += p.rgb[2] * w;
        sumW += w;
        sumAmt += p.amount * w;
      }
      final s = sumAmt / sumW;
      return [
        1 - s * (1 - cr / sumW),
        1 - s * (1 - cg / sumW),
        1 - s * (1 - cb / sumW)
      ];
    }
  }

  double _smoother(double t) => t * t * (3 - 2 * t);

  // Stream the baked grid as one packet (int16 LE R,G,B per cell, row-major).
  void _ucSend() {
    if (!mounted) return;
    final n = _ucNx * _ucNy;
    final bytes = Uint8List(n * 6);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < n; i++) {
      bd.setInt16(i * 6, _ucR[i], Endian.little);
      bd.setInt16(i * 6 + 2, _ucG[i], Endian.little);
      bd.setInt16(i * 6 + 4, _ucB[i], Endian.little);
    }
    context
        .read<Network>()
        .sendOscMessage('/send/1/color/field/cells', [_ucNx, _ucNy, bytes]);
  }

  int? _hitUcPoint(Offset p) {
    for (int i = _ucPts.length - 1; i >= 0; i--) {
      final q = Offset(_ucPts[i].x * _size.width, _ucPts[i].y * _size.height);
      if ((p - q).distance < 14) return i;
    }
    return null;
  }

  void _ucStart(Offset p) {
    final hit = _hitUcPoint(p);
    if (hit != null) {
      setState(() {
        _drag = 'uc';
        _ucSel = hit;
      });
      return;
    }
    // Painting only shows if the block is on and not being overwritten by the
    // procedural basis, so on the first point turn the field on and force Flat
    // (the manual grid is the "Flat" layer). Echoes to the Color Field knobs.
    final first = _ucPts.isEmpty;
    // Drop a fresh point at the cursor, cycling its colour.
    final hue = _ucAddHue.toDouble();
    _ucAddHue = (_ucAddHue + 47) % 360;
    setState(() {
      _ucPts.add(_UcPoint(
          x: (p.dx / _size.width).clamp(0.0, 1.0),
          y: (p.dy / _size.height).clamp(0.0, 1.0),
          hue: hue));
      _ucSel = _ucPts.length - 1;
      _drag = 'uc';
    });
    if (first) {
      _send3('/send/1/color/field/fx', [0]); // Basis = Flat (manual grid)
      _send3('/send/1/color/field/enable', [1]);
    }
    _ucBake();
  }

  void _ucUpdate(Offset p) {
    if (_drag != 'uc' || _ucSel == null) return;
    final pt = _ucPts[_ucSel!];
    setState(() {
      pt.x = (p.dx / _size.width).clamp(0.0, 1.0);
      pt.y = (p.dy / _size.height).clamp(0.0, 1.0);
    });
    _ucBake();
  }

  void _ucEdit(void Function(_UcPoint) f) {
    if (_ucSel == null) return;
    setState(() => f(_ucPts[_ucSel!]));
    _ucBake();
  }

  void _ucDelete() {
    if (_ucSel == null) return;
    setState(() {
      _ucPts.removeAt(_ucSel!);
      _ucSel = null;
    });
    _ucBake();
  }

  void _ucClear() {
    setState(() {
      _ucPts.clear();
      _ucSel = null;
    });
    _ucBake();
  }

  void _ucSetMode(String m) {
    setState(() => _ucMode = m);
    _ucBake();
  }

  // Send to an absolute address (+ local echo) — used for the sprite move
  // messages, which live under the fixed /assets path regardless of this page.
  void _send3(String addr, List<Object> args) {
    context.read<Network>().sendOscMessage(addr, args);
    OscRegistry()
      ..registerAddress(addr)
      ..dispatchLocal(addr, args.cast<Object?>());
  }

  @override
  void dispose() {
    _lutPoll?.cancel();
    _ucTimer?.cancel();
    final reg = OscRegistry();
    _subs.forEach(reg.unregisterListener);
    super.dispose();
  }

  // Send + local echo (mirrors OscAddressMixin.sendOsc, so knobs update offline).
  void _send(String rel, List<Object> args) {
    final addr = '$_base/$rel';
    context.read<Network>().sendOscMessage(addr, args);
    OscRegistry()
      ..registerAddress(addr)
      ..dispatchLocal(addr, args.cast<Object?>());
  }

  // ── geometry ────────────────────────────────────────────────────────────────
  _Geo _geo() => _computeGeo(_size,
      rotDeg: rotDeg,
      cl: cl,
      cr: cr,
      ct: ct,
      cb: cb,
      sx: scaleX,
      sy: scaleY,
      px: posX,
      py: posY,
      mesh: mesh,
      n: meshN,
      keyH: keyH,
      keyV: keyV,
      shearX: shearX,
      shearY: shearY,
      barrel: barrel,
      lensX: lensX,
      lensY: lensY);

  String? _hit(Offset p) {
    final g = _geo();
    final th = math.max(14.0, _size.width * 0.03);
    if (_canRotate && (p - g.grip).distance < th) return 'rot';
    if (_full && tool == 'warp' && meshN >= 2) {
      for (int k = 0; k < g.mesh.length; k++) {
        if ((p - g.mesh[k]).distance < th) return 'w$k';
      }
    }
    if (_full && (p - g.lens).distance < th) return 'lens'; // lens-centre puck
    for (int i = 0; i < 4; i++) {
      if ((p - g.cropEdges[i]).distance < th) return 'e$i';
    }
    for (int i = 0; i < 4; i++) {
      if ((p - g.full[i]).distance < th) return 's$i';
    }
    return null;
  }

  void _apply(Offset p) {
    if (_drag == null) return;
    final g = _geo();
    final d = _drag!;
    if (d == 'rot') {
      final a =
          math.atan2(p.dy - g.center.dy, p.dx - g.center.dx) * 180 / math.pi;
      double rd = -(a + 90);
      double osc = rd + 180;
      osc = ((osc % 360) + 360) % 360;
      setState(() => rotOsc = osc);
      _send('shape/rotation', [osc]);
    } else if (d == 'body') {
      // The frame centre moves (1+scale)·size per unit position, so invert that
      // to keep the image tracking the cursor 1:1.
      final sxc = scaleX.clamp(0.05, 4.0), syc = scaleY.clamp(0.05, 4.0);
      final nx =
          (_px0 + (p.dx - _p0.dx) / (_size.width * (1 + sxc))).clamp(0.0, 1.0);
      final ny =
          (_py0 + (p.dy - _p0.dy) / (_size.height * (1 + syc))).clamp(0.0, 1.0);
      setState(() {
        posX = nx;
        posY = ny;
      });
      _send('shape/pos/x', [nx]);
      _send('shape/pos/y', [ny]);
    } else if (d.startsWith('e')) {
      final i = int.parse(d.substring(1));
      final (u, v) = _invMap(p, g);
      switch (i) {
        case 0:
          final t = v.clamp(0.0, 0.95);
          setState(() => ct = t);
          _send('shape/crop/top', [t]);
          break;
        case 1:
          final t = (1 - u).clamp(0.0, 0.95);
          setState(() => cr = t);
          _send('shape/crop/right', [t]);
          break;
        case 2:
          final t = (1 - v).clamp(0.0, 0.95);
          setState(() => cb = t);
          _send('shape/crop/bottom', [t]);
          break;
        case 3:
          final t = u.clamp(0.0, 0.95);
          setState(() => cl = t);
          _send('shape/crop/left', [t]);
          break;
      }
    } else if (d == 'lens') {
      // lens optical centre → the same lens_x / lens_y the knobs bind to, so the
      // puck, the knobs, and the canvas all stay in sync (lens_center is a
      // separate address the knobs don't listen on).
      final o = _unrot(p, g);
      final lx = (o.dx / g.fw * _outW).clamp(-960.0, 960.0);
      final ly = (o.dy / g.fh * _outH).clamp(-540.0, 540.0);
      setState(() {
        lensX = lx;
        lensY = ly;
      });
      _send('shape/warp/lens_x', [lx.round()]);
      _send('shape/warp/lens_y', [ly.round()]);
    } else if (d.startsWith('s')) {
      // scale — centre-anchored. The frame half-extent is fw/2 = size·scale/2,
      // so scale = 2·|frame-local offset| / stage size (matches _computeGeo).
      final o = _unrot(p, g);
      final nsx = (2 * o.dx.abs() / _size.width).clamp(0.05, 4.0);
      final nsy = (2 * o.dy.abs() / _size.height).clamp(0.05, 4.0);
      setState(() {
        scaleX = nsx;
        scaleY = nsy;
      });
      _send('shape/scale/x', [nsx]);
      _send('shape/scale/y', [nsy]);
    } else if (d.startsWith('w')) {
      // mesh vertex — px displacement
      final k = int.parse(d.substring(1));
      final n = meshN;
      final i = k % n, j = k ~/ n;
      Offset lp(Offset a, Offset b, double t) =>
          Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      Offset bil(List<Offset> q, double u, double v) =>
          lp(lp(q[0], q[1], u), lp(q[3], q[2], u), v);
      final base = bil(g.quad, i / (n - 1), j / (n - 1));
      final off = _unrot(p - base + g.center, g);
      final ddx = off.dx / g.fw * _outW, ddy = off.dy / g.fh * _outH;
      setState(() => mesh[k] = Offset(ddx, ddy));
      _send('shape/warp/mesh/point', [i, j, ddx.round(), ddy.round()]);
    }
  }

  void _setMeshSize(int n) {
    setState(() {
      meshN = n;
      for (var i = 0; i < mesh.length; i++) mesh[i] = Offset.zero;
    });
    _send('shape/warp/mesh/size', [n]);
  }

  // ── overlay geometry (screen-space, output-pixel → stage-local) ──────────────
  // Text/sprite boxes live in the fixed output raster (they composite at the
  // OSD, post-scale), so they map onto the stage rect, not the warped content.
  Rect _textRect(int i) {
    final lines = _txtStr[i].split('\n');
    int maxLen = 1;
    for (final l in lines) {
      if (l.length > maxLen) maxLen = l.length;
    }
    final sz = _txtSize[i] <= 0 ? 48.0 : _txtSize[i];
    final tl =
        Offset(_txtX[i] / _outW * _size.width, _txtY[i] / _outH * _size.height);
    final w = math.max(12.0, maxLen * sz * 0.55 / _outW * _size.width);
    final h = math.max(12.0, lines.length * sz * 1.2 / _outH * _size.height);
    return tl & Size(w, h);
  }

  Rect _spriteRect(_SpriteBox b) {
    final info = _spriteInfo[b.sprite];
    final w0 = (info != null && info.w > 0) ? info.w.toDouble() : 160.0;
    final h0 = (info != null && info.h > 0) ? info.h.toDouble() : 160.0;
    final tl = Offset(b.x / _outW * _size.width, b.y / _outH * _size.height);
    final w = math.max(12.0, w0 / _outW * _size.width);
    final h = math.max(12.0, h0 / _outH * _size.height);
    return tl & Size(w, h);
  }

  // ── overlay gesture routing ──────────────────────────────────────────────────
  void _panStart(Offset p) {
    switch (_overlay) {
      case 'text':
        _textStart(p);
        break;
      case 'sprites':
        _spriteStart(p);
        break;
      case 'colorField':
        _ucStart(p);
        break;
      default:
        final hit = _hit(p);
        setState(() {
          if (hit != null) {
            _drag = hit;
          } else if (tool == 'move') {
            _drag = 'body';
            _p0 = p;
            _px0 = posX;
            _py0 = posY;
          } else {
            _drag = null;
          }
        });
    }
  }

  void _panUpdate(Offset p) {
    switch (_overlay) {
      case 'text':
        _textUpdate(p);
        break;
      case 'sprites':
        _spriteUpdate(p);
        break;
      case 'colorField':
        _ucUpdate(p);
        break;
      default:
        _apply(p);
    }
  }

  void _textStart(Offset p) {
    int? hit;
    for (int i = 3; i >= 0; i--) {
      if (_txtStr[i].trim().isEmpty) continue;
      if (_textRect(i).inflate(6).contains(p)) {
        hit = i;
        break;
      }
    }
    setState(() {
      if (hit != null) {
        _drag = 't$hit';
        _p0 = p;
        _px0 = _txtX[hit];
        _py0 = _txtY[hit];
      } else {
        _drag = null;
      }
    });
    if (hit != null) _sel?.select(ShapeSel.text, hit + 1);
  }

  DateTime _lastTextSend = DateTime.fromMillisecondsSinceEpoch(0);

  void _sendTextPos(int i, double nx, double ny) {
    _send('text/region/${i + 1}/pos/x', [nx.round()]);
    _send('text/region/${i + 1}/pos/y', [ny.round()]);
  }

  void _textUpdate(Offset p) {
    if (_drag == null || !_drag!.startsWith('t')) return;
    final i = int.parse(_drag!.substring(1));
    final nx =
        (_px0 + (p.dx - _p0.dx) / _size.width * _outW).clamp(0.0, 3840.0);
    final ny =
        (_py0 + (p.dy - _p0.dy) / _size.height * _outH).clamp(0.0, 2160.0);
    // Local UI tracks the pointer every frame; the device update is throttled
    // to ~30 Hz (each send is 2 msgs + a local echo) and the final position is
    // flushed on release, so dragging stays smooth without flooding the device.
    setState(() {
      _txtX[i] = nx;
      _txtY[i] = ny;
    });
    final now = DateTime.now();
    if (now.difference(_lastTextSend).inMilliseconds >= 33) {
      _lastTextSend = now;
      _sendTextPos(i, nx, ny);
    }
  }

  void _spriteStart(Offset p) {
    int? hit;
    for (final e in _sprites.entries) {
      if (_spriteRect(e.value).inflate(6).contains(p)) {
        hit = e.key;
        break;
      }
    }
    setState(() {
      if (hit != null) {
        _drag = 'sp$hit';
        _p0 = p;
        _px0 = _sprites[hit]!.x;
        _py0 = _sprites[hit]!.y;
      } else {
        _drag = null;
      }
    });
    if (hit != null) _sel?.select(ShapeSel.sprite, hit);
  }

  void _spriteUpdate(Offset p) {
    if (_drag == null || !_drag!.startsWith('sp')) return;
    final r = int.parse(_drag!.substring(2));
    final b = _sprites[r];
    if (b == null) return;
    final nx =
        (_px0 + (p.dx - _p0.dx) / _size.width * _outW).clamp(0.0, 1920.0);
    final ny =
        (_py0 + (p.dy - _p0.dy) / _size.height * _outH).clamp(0.0, 1080.0);
    setState(() {
      b.x = nx;
      b.y = ny;
    });
    _send3('/assets/sprites/move', [_sendIdx, r, nx.round(), ny.round()]);
  }

  // Push the region occupancy the canvas already mirrors into the shared model,
  // so the editors can grey out a region held by the other kind. Called
  // post-frame (setters are no-ops when unchanged, so this is cheap).
  void _syncOccupancy() {
    final sel = _sel;
    if (sel == null) return;
    for (int r = 1; r <= 4; r++) {
      sel.setTextOccupied(r, _txtStr[r - 1].trim().isNotEmpty);
    }
    for (int r = 2; r <= 4; r++) {
      sel.setSpriteOccupied(r, _sprites.containsKey(r));
    }
  }

  // A plain tap selects whatever element is under it — across overlays, so
  // tapping a (dimmed) sprite while on the Text tab opens the Sprites tab.
  // Sprites paint above text, so hit-test them first.
  void _tapSelect(Offset p) {
    final sel = _sel;
    if (sel == null) return;
    for (final e in _sprites.entries) {
      if (_spriteRect(e.value).inflate(6).contains(p)) {
        sel.select(ShapeSel.sprite, e.key);
        return;
      }
    }
    for (int i = 3; i >= 0; i--) {
      if (_txtStr[i].trim().isEmpty) continue;
      if (_textRect(i).inflate(6).contains(p)) {
        sel.select(ShapeSel.text, i + 1);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // Rebuild (and thus repaint — shouldRepaint is always true) when the shared
    // selection changes, so the highlighted text/sprite box tracks the editor.
    context.watch<ShapeSelection>();
    // Reconcile occupancy after this frame from the state we already mirror.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncOccupancy();
    });
    // Big working area filling the left side; the 16:9 output frame is centred
    // inside it, so handles can roam into the margin and stay grabbable.
    const overlayTitles = {
      'transform': 'TRANSFORM',
      'text': 'TEXT',
      'sprites': 'SPRITES',
      'colorField': 'COLOR FIELD',
    };
    final isTransform = _overlay == 'transform';
    // This sits directly in a GridRow cell rather than inside a Panel, so it
    // has to reach the card's content edge itself — otherwise the canvas sits
    // a panel-inset to the left of every sibling panel's body.
    return Padding(
      padding: EdgeInsets.only(left: t.panelContentInset),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Fixed-height header so the canvas top stays put regardless of whether
        // the active tab shows tool buttons or a plain hint.
        SizedBox(
          height: t.u * 2.4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // This widget stands in for a Panel, so its legend is the same
              // centred caps token every real Panel title uses — it used to
              // hand-roll a near-copy (caption + letterSpacing 1.5 + its own
              // grey) and drifted from them.
              OpticalCenterText(overlayTitles[_overlay] ?? 'TRANSFORM',
                  style: t.textPanelTitle),
              // Trailing affordances float over the band, like Panel's
              // titleTrailing, so they cannot push the legend off centre.
              Align(
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  // Hint / tool affordances per overlay.
                  if (isTransform) ...[
                    _toolBtn(t, Icons.open_with, 'Move', 'move'),
                    if (_full)
                      _WarpToolButton(
                          active: tool == 'warp',
                          n: meshN,
                          onPick: (n) {
                            setState(() => tool = 'warp');
                            if (n != meshN) _setMeshSize(n);
                          }),
                  ] else if (_overlay == 'colorField') ...[
                    _ucModeBtn(t, 'A', 'Falloff'),
                    _ucModeBtn(t, 'B', 'Fill'),
                    if (_ucPts.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(left: t.sm),
                        child: GestureDetector(
                          onTap: _ucClear,
                          child: Text('Clear',
                              style: t.textCaption
                                  .copyWith(color: const Color(0xFF8A8A92))),
                        ),
                      ),
                  ] else
                    Text(_overlayHint(),
                        style: t.textCaption
                            .copyWith(color: const Color(0xFF6A6A72))),
                ]),
              ),
            ],
          ),
        ),
        SizedBox(height: t.sm),
        // Fills the whole left column (Stack so it carries no intrinsic height,
        // letting the taller knob column set the row height under IntrinsicHeight;
        // the painter self-measures and centres the 16:9 output frame inside).
        Expanded(
          child: NeumorphicInset(
            baseColor: const Color(0xFF0C0C0E),
            padding: EdgeInsets.all(t.xs),
            child: Stack(children: [
              Positioned.fill(
                child: MouseRegion(
                  onHover: (e) =>
                      setState(() => _hover = e.localPosition - _stageOffset),
                  // DragArea (not GestureDetector) so dragging a crop handle or
                  // warp point wins over the scrolling page on touch devices.
                  child: DragArea(
                    onTap: (p, _) => _tapSelect(p - _stageOffset),
                    onDragStart: (p, _) => _panStart(p - _stageOffset),
                    onDragUpdate: (p, _) => _panUpdate(p - _stageOffset),
                    onDragEnd: () {
                      // Make sure the final (possibly throttled-away) text
                      // position lands on the device.
                      final d = _drag;
                      if (d != null && d.startsWith('t')) {
                        final i = int.parse(d.substring(1));
                        _sendTextPos(i, _txtX[i], _txtY[i]);
                      }
                      setState(() => _drag = null);
                    },
                    child: CustomPaint(
                        painter: _ShapePainter(
                            this,
                            isTransform
                                ? (_drag ??
                                    (_hover == null ? null : _hit(_hover!)))
                                : null)),
                  ),
                ),
              ),
            ]),
          ),
        ),
        if (_overlay == 'colorField' && _ucSel != null) _ucInspector(t),
      ]),
    );
  }

  String _overlayHint() {
    switch (_overlay) {
      case 'text':
        return 'drag to position';
      case 'sprites':
        return _sprites.isEmpty ? 'no sprites shown' : 'drag to position';
      default:
        return '';
    }
  }

  Widget _ucModeBtn(GridTokens t, String key, String label) {
    final on = _ucMode == key;
    return Padding(
      padding: EdgeInsets.only(left: t.xs),
      child: GestureDetector(
        onTap: () => _ucSetMode(key),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
          decoration: BoxDecoration(
              color: on ? _amber : const Color(0xFF212124),
              borderRadius: BorderRadius.circular(4)),
          child: Text(label,
              style: t.textCaption.copyWith(
                  color: on ? Colors.black : const Color(0xFF8A8A92),
                  fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // Inspector strip for the selected control point: colour / amount / falloff.
  Widget _ucInspector(GridTokens t) {
    final p = _ucPts[_ucSel!];
    final swatch = HSVColor.fromAHSV(1, p.hue % 360, 0.85, 1).toColor();
    Widget slider(
        String label, double v, double min, double max, ValueChanged<double> on,
        {List<Color>? track}) {
      return Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: t.textLabel.copyWith(color: const Color(0xFF8A8A92))),
              SizedBox(
                height: 22,
                child: SliderTheme(
                  data: SliderThemeData(
                    trackHeight: track != null ? 5 : 2.5,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 6),
                    activeTrackColor:
                        track != null ? Colors.transparent : _amber,
                    inactiveTrackColor: track != null
                        ? Colors.transparent
                        : const Color(0xFF3A3A40),
                    thumbColor: Colors.white,
                  ),
                  child: Stack(alignment: Alignment.center, children: [
                    if (track != null)
                      Container(
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: LinearGradient(colors: track),
                        ),
                      ),
                    Slider(
                        value: v.clamp(min, max),
                        min: min,
                        max: max,
                        onChanged: on),
                  ]),
                ),
              ),
            ]),
      );
    }

    const hueTrack = [
      Color(0xFFFF4444),
      Color(0xFFFFDD44),
      Color(0xFF44FF66),
      Color(0xFF44DDFF),
      Color(0xFF6666FF),
      Color(0xFFFF44EE),
      Color(0xFFFF4444),
    ];
    return Padding(
      padding: EdgeInsets.only(top: t.sm),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                  color: swatch, borderRadius: BorderRadius.circular(3))),
          SizedBox(width: t.xs),
          Text('Point ${_ucSel! + 1}',
              style: t.textCaption
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          SizedBox(width: t.md),
          slider('Colour', p.hue, 0, 360, (v) => _ucEdit((q) => q.hue = v),
              track: hueTrack),
          SizedBox(width: t.md),
          slider('Amount', p.amount, 0, 1, (v) => _ucEdit((q) => q.amount = v)),
          SizedBox(width: t.md),
          slider('Falloff', p.radius, 0.05, 0.9,
              (v) => _ucEdit((q) => q.radius = v)),
          SizedBox(width: t.sm),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: Color(0xFFE08A8E)),
            visualDensity: VisualDensity.compact,
            onPressed: _ucDelete,
          ),
        ]),
      ),
    );
  }

  Widget _toolBtn(GridTokens t, IconData ic, String label, String key) =>
      Padding(
        padding: EdgeInsets.only(left: t.xs),
        child: GestureDetector(
          onTap: () => setState(() => tool = key),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
            decoration: BoxDecoration(
                color: tool == key ? _amber : const Color(0xFF212124),
                borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic,
                  size: t.u * 1.4,
                  color: tool == key ? Colors.black : const Color(0xFF8A8A92)),
              SizedBox(width: t.xs),
              Text(label,
                  style: t.textCaption.copyWith(
                      color:
                          tool == key ? Colors.black : const Color(0xFF8A8A92),
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

// A tracked, shown sprite on one of this send's OSD regions.
class _SpriteBox {
  int sprite;
  double x, y; // output-pixel top-left
  _SpriteBox({required this.sprite, required this.x, required this.y});
}

// A colour-field control point (normalized position, hue, strength, falloff).
// `rgb` (0..1, the darken target) is cached and only recomputed when the hue
// changes, so baking doesn't rebuild an HSVColor per cell per point.
class _UcPoint {
  double x, y;
  double amount = 0.7;
  double radius = 0.34;
  double _hue;
  List<double> rgb;
  _UcPoint({
    required this.x,
    required this.y,
    required double hue,
  })  : _hue = hue,
        rgb = _hueRgb(hue);
  double get hue => _hue;
  set hue(double h) {
    _hue = h;
    rgb = _hueRgb(h);
  }

  // Full-saturation HSV→RGB (0..1); manual so it doesn't depend on the Color
  // component accessors, which differ across Flutter versions.
  static List<double> _hueRgb(double h) {
    h = ((h % 360) + 360) % 360 / 60.0;
    final x = 1 - ((h % 2) - 1).abs();
    if (h < 1) return [1, x, 0];
    if (h < 2) return [x, 1, 0];
    if (h < 3) return [0, 1, x];
    if (h < 4) return [0, x, 1];
    if (h < 5) return [x, 0, 1];
    return [1, 0, x];
  }
}

// ── shared geometry (stage-local; painter + hit-test agree) ───────────────────
class _Geo {
  final Offset center;
  final double ang, fw, fh, barrel;
  final List<Offset> full, quad, cropEdges, mesh;
  final Offset grip, lens;
  _Geo(this.center, this.ang, this.fw, this.fh, this.barrel, this.full,
      this.quad, this.cropEdges, this.mesh, this.grip, this.lens);
}

_Geo _computeGeo(
  Size size, {
  required double rotDeg,
  required double cl,
  required double cr,
  required double ct,
  required double cb,
  required double sx,
  required double sy,
  required double px,
  required double py,
  required List<Offset> mesh,
  required int n,
  double keyH = 0,
  double keyV = 0,
  double shearX = 0,
  double shearY = 0,
  double barrel = 0,
  double lensX = 0,
  double lensY = 0,
}) {
  final sxc = sx.clamp(0.05, 4.0), syc = sy.clamp(0.05, 4.0);
  // Position couples with scale exactly as the device does — both the RECT path
  // (dst_x = pos·(W+scale·W)−scale·W) and the warp affine give:
  //   centre = 0.5 + (pos−0.5)·(1+scale).
  final c = size.center(Offset.zero) +
      Offset((px - 0.5) * size.width * (1 + sxc),
          (py - 0.5) * size.height * (1 + syc));
  final ang = -rotDeg * math.pi / 180;
  final ca = math.cos(ang), sa = math.sin(ang);
  final fw = size.width * sxc, fh = size.height * syc;
  Offset rot(double dx, double dy) =>
      c + Offset(dx * ca - dy * sa, dx * sa + dy * ca);
  // Keystone/shear corner offsets (output px → frame-local px), matching the
  // firmware's k[] deltas (warp_keystone_matrix).
  final kh = keyH / _outW * fw, kv = keyV / _outH * fh;
  final shx = shearX / _outW * fw, shy = shearY / _outH * fh;
  final full = [
    rot(-fw / 2 + kh - shx, -fh / 2 + kv - shy), // TL
    rot(fw / 2 - kh - shx, -fh / 2 + shy), // TR
    rot(fw / 2 + shx, fh / 2 + shy), // BR
    rot(-fw / 2 + shx, fh / 2 - kv - shy), // BL
  ];
  Offset lerp(Offset a, Offset b, double t) =>
      Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  Offset bil(List<Offset> q, double u, double v) =>
      lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v);
  final quad = [
    bil(full, cl, ct),
    bil(full, 1 - cr, ct),
    bil(full, 1 - cr, 1 - cb),
    bil(full, cl, 1 - cb)
  ];
  final cropEdges = [
    lerp(quad[0], quad[1], .5),
    lerp(quad[1], quad[2], .5),
    lerp(quad[2], quad[3], .5),
    lerp(quad[3], quad[0], .5)
  ];
  final topFull = lerp(full[0], full[1], .5);
  final dir = topFull - c;
  final grip = topFull +
      (dir.distance == 0 ? const Offset(0, -1) : dir / dir.distance) * 26;
  final lens = rot(lensX / _outW * fw, lensY / _outH * fh);
  final mp = <Offset>[];
  if (n >= 2) {
    for (int j = 0; j < n; j++) {
      for (int i = 0; i < n; i++) {
        final b = bil(quad, i / (n - 1), j / (n - 1));
        final o = mesh[j * n + i];
        final dx = o.dx / _outW * fw, dy = o.dy / _outH * fh;
        mp.add(b + Offset(dx * ca - dy * sa, dx * sa + dy * ca));
      }
    }
  }
  return _Geo(c, ang, fw, fh, barrel, full, quad, cropEdges, mp, grip, lens);
}

(double, double) _invMap(Offset p, _Geo g) {
  final d = p - g.center;
  final lx = d.dx * math.cos(g.ang) + d.dy * math.sin(g.ang);
  final ly = -d.dx * math.sin(g.ang) + d.dy * math.cos(g.ang);
  return (lx / g.fw + 0.5, ly / g.fh + 0.5);
}

Offset _unrot(Offset p, _Geo g) {
  final d = p - g.center;
  return Offset(d.dx * math.cos(g.ang) + d.dy * math.sin(g.ang),
      -d.dx * math.sin(g.ang) + d.dy * math.cos(g.ang));
}

// ── painter ───────────────────────────────────────────────────────────────────
class _ShapePainter extends CustomPainter {
  final _ShapeCanvasState s;
  final String? hot;
  _ShapePainter(this.s, this.hot);
  @override
  void paint(Canvas canvas, Size size) {
    // Self-measure: fit a 16:9 output frame inside the full paint area and store
    // it for the gesture layer (avoids a LayoutBuilder, which can't live under
    // IntrinsicHeight — needed so the canvas fills the whole left column).
    double w = size.width, h = w * 9 / 16;
    if (h > size.height) {
      h = size.height;
      w = h * 16 / 9;
    }
    s._size = Size(w, h);
    s._stageOffset = Offset((size.width - w) / 2, (size.height - h) / 2);

    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF08080A));
    canvas.save();
    canvas.translate(s._stageOffset.dx, s._stageOffset.dy);
    final ss = s._size;
    final r = Offset.zero & ss;
    canvas.drawRect(r, Paint()..color = const Color(0xFF0A0A0C));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i < 16; i++)
      canvas.drawLine(Offset(ss.width * i / 16, 0),
          Offset(ss.width * i / 16, ss.height), grid);
    for (int i = 1; i < 9; i++)
      canvas.drawLine(Offset(0, ss.height * i / 9),
          Offset(ss.width, ss.height * i / 9), grid);
    canvas.drawRect(
        r.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18));

    final g = s._geo();
    Offset lerp(Offset a, Offset b, double t) =>
        Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    final warping = s._full && s.tool == 'warp';

    // Nominal (un-warped) output frame — faint white reference rectangle.
    canvas.drawPath(
        Path()..addPolygon(g.full, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18));

    // Content = the real device deformation (forward LUT: keystone/barrel/lens/
    // field/mesh, live-animated), or the parametric cropped quad until it lands.
    // Skipped under the colour-field mesh, which owns the whole output raster.
    if (s._overlay != 'colorField') {
      final lut = s._lut;
      final ln = s._lutN;
      final hasLut = lut != null && ln >= 2;
      Offset lp(int i, int j) => Offset(
          lut![j * ln + i].dx * ss.width, lut[j * ln + i].dy * ss.height);
      List<Offset> boundary;
      if (hasLut) {
        boundary = <Offset>[];
        for (int i = 0; i < ln; i++) boundary.add(lp(i, 0));
        for (int j = 1; j < ln; j++) boundary.add(lp(ln - 1, j));
        for (int i = ln - 2; i >= 0; i--) boundary.add(lp(i, ln - 1));
        for (int j = ln - 2; j >= 1; j--) boundary.add(lp(0, j));
      } else {
        boundary = g.quad;
      }
      final bp = Path()..addPolygon(boundary, true);
      canvas.drawPath(bp, Paint()..color = _amber.withValues(alpha: 0.06));
      canvas.save();
      canvas.clipPath(bp);
      final hatch = Paint()
        ..color = _amber.withValues(alpha: 0.10)
        ..strokeWidth = 1;
      for (double d = -ss.height; d < ss.width; d += 10)
        canvas.drawLine(Offset(d, 0), Offset(d + ss.height, ss.height), hatch);
      canvas.restore();
      if (!warping) {
        if (hasLut) {
          // Interior deformation grid straight from the device.
          final gl = Paint()
            ..color = _amber.withValues(alpha: 0.20)
            ..strokeWidth = 0.75;
          for (int j = 0; j < ln; j++) {
            for (int i = 0; i < ln; i++) {
              if (i < ln - 1) canvas.drawLine(lp(i, j), lp(i + 1, j), gl);
              if (j < ln - 1) canvas.drawLine(lp(i, j), lp(i, j + 1), gl);
            }
          }
        } else {
          final thirds = Paint()
            ..color = _amber.withValues(alpha: 0.22)
            ..strokeWidth = 0.75;
          for (int i = 1; i < 3; i++) {
            canvas.drawLine(lerp(g.quad[0], g.quad[1], i / 3),
                lerp(g.quad[3], g.quad[2], i / 3), thirds);
            canvas.drawLine(lerp(g.quad[0], g.quad[3], i / 3),
                lerp(g.quad[1], g.quad[2], i / 3), thirds);
          }
        }
      }
      canvas.drawPath(
          bp,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = _amber);
    } // end content boundary

    // The colour-field mesh owns the whole canvas. On every other tab, show the
    // geometry handles + text + sprite placeholders together, so the user always
    // sees where everything is; only the active tab's overlay is at full
    // strength (and clickable — gestures route to it alone), the rest are dimmed.
    if (s._overlay == 'colorField') {
      _paintUcMesh(canvas, ss);
    } else {
      final lb = Offset(-s._stageOffset.dx, -s._stageOffset.dy) & size;
      double alphaFor(String o) => s._overlay == o ? 1.0 : 0.26;

      // ── geometry handles (active on Transform / Warp) ──
      canvas.saveLayer(
          lb,
          Paint()
            ..color = Colors.white.withValues(alpha: alphaFor('transform')));
      final aa = warping ? 0.5 : 1.0;
      // scale corners (blue circles)
      for (int i = 0; i < 4; i++) {
        final on = hot == 's$i';
        canvas.drawCircle(
            g.full[i],
            on ? 8 : 6,
            Paint()
              ..color =
                  (on ? Colors.white : _blue).withValues(alpha: on ? 1 : aa));
      }
      // crop bars — oriented along the frame edges
      for (int i = 0; i < 4; i++) {
        final on = hot == 'e$i';
        final edge = g.quad[(i + 1) % 4] - g.quad[i];
        final ang = math.atan2(edge.dy, edge.dx);
        canvas.save();
        canvas.translate(g.cropEdges[i].dx, g.cropEdges[i].dy);
        canvas.rotate(ang);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset.zero,
                    width: on ? 20 : 16,
                    height: on ? 7 : 6),
                const Radius.circular(2)),
            Paint()
              ..color =
                  (on ? Colors.white : _amber).withValues(alpha: on ? 1 : aa));
        canvas.restore();
      }
      // warp mesh — visible whenever a mesh exists (editable only in warp tool)
      if (g.mesh.isNotEmpty) {
        final n = s.meshN;
        final line = Paint()
          ..color = _teal.withValues(alpha: 0.55)
          ..strokeWidth = 1;
        for (int j = 0; j < n; j++) {
          for (int i = 0; i < n; i++) {
            final p = g.mesh[j * n + i];
            if (i < n - 1) canvas.drawLine(p, g.mesh[j * n + i + 1], line);
            if (j < n - 1) canvas.drawLine(p, g.mesh[(j + 1) * n + i], line);
          }
        }
        for (int k = 0; k < g.mesh.length; k++) {
          final on = hot == 'w$k';
          canvas.drawCircle(g.mesh[k], on ? 6 : 4,
              Paint()..color = on ? Colors.white : _teal);
        }
      }
      // lens optical-centre puck (Send 1) — green dot, drag to set lens X/Y
      if (s._full) {
        final on = hot == 'lens';
        canvas.drawCircle(
            g.lens,
            on ? 13 : 11,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = on ? Colors.white : _green);
        canvas.drawCircle(g.lens, 3.5, Paint()..color = _green);
      }
      // rotation grip (Send 1)
      if (s._canRotate) {
        final topFull = lerp(g.full[0], g.full[1], .5);
        canvas.drawLine(
            topFull,
            g.grip,
            Paint()
              ..color = _amber
              ..strokeWidth = 1.5);
        canvas.drawCircle(
            g.grip,
            hot == 'rot' ? 7 : 5,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = hot == 'rot' ? Colors.white : _amber);
        canvas.drawCircle(g.grip, hot == 'rot' ? 7 : 5,
            Paint()..color = const Color(0xFF0A0A0C));
      }
      canvas.restore();

      // ── text placeholders (active on Text) ──
      canvas.saveLayer(lb,
          Paint()..color = Colors.white.withValues(alpha: alphaFor('text')));
      _paintText(canvas, ss);
      canvas.restore();

      // ── sprite placeholders (active on Sprites) ──
      canvas.saveLayer(lb,
          Paint()..color = Colors.white.withValues(alpha: alphaFor('sprites')));
      _paintSprites(canvas, ss);
      canvas.restore();
    }
    canvas.restore();
  }

  // Draw a stage-local label chip at the box's top-left corner.
  void _label(Canvas canvas, Rect r, String text, Color c) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style:
              TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(24.0, r.width - 4));
    tp.paint(canvas, r.topLeft + const Offset(3, 2));
  }

  // Text-region placeholders — output-raster boxes with the region's text.
  void _paintText(Canvas canvas, Size ss) {
    for (int i = 0; i < 4; i++) {
      if (s._txtStr[i].trim().isEmpty) continue;
      final r = s._textRect(i);
      final sel = s._drag == 't$i' ||
          (s._sel?.kind == ShapeSel.text && s._sel?.region == i + 1);
      final c = sel ? Colors.white : _teal;
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.10));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 2 : 1.5
            ..color = c);
      final first = s._txtStr[i].split('\n').first;
      _label(canvas, r, 'T${i + 1}  $first', c);
    }
  }

  // Sprite placeholders — boxes sized to the sprite bitmap when known.
  void _paintSprites(Canvas canvas, Size ss) {
    for (final e in s._sprites.entries) {
      final r = s._spriteRect(e.value);
      final sel = s._drag == 'sp${e.key}' ||
          (s._sel?.kind == ShapeSel.sprite && s._sel?.region == e.key);
      final c = sel ? Colors.white : _green;
      canvas.drawRect(r, Paint()..color = c.withValues(alpha: 0.08));
      canvas.drawRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = sel ? 2 : 1.5
            ..color = c);
      // Diagonals read as an image placeholder.
      final x = Paint()
        ..color = c.withValues(alpha: 0.35)
        ..strokeWidth = 1;
      canvas.drawLine(r.topLeft, r.bottomRight, x);
      canvas.drawLine(r.topRight, r.bottomLeft, x);
      final info = s._spriteInfo[e.value.sprite];
      _label(canvas, r,
          'R${e.key}  ${info?.name ?? 'sprite ${e.value.sprite}'}', c);
    }
  }

  // Colour-field mesh — the baked UC grid (each cell = light it lets through)
  // plus the draggable control points on top.
  void _paintUcMesh(Canvas canvas, Size ss) {
    final nx = s._ucNx, ny = s._ucNy;
    if (nx < 1 || ny < 1 || s._ucG.length < nx * ny) return;
    final cw = ss.width / nx, ch = ss.height / ny;
    // Preview against a soft neutral "video" so both darkening and colour tint
    // read: displayed cell = base · gain.
    for (int cy = 0; cy < ny; cy++) {
      for (int cx = 0; cx < nx; cx++) {
        final k = cy * nx + cx;
        final r = (200 * s._ucR[k] / 1023).round();
        final g = (204 * s._ucG[k] / 1023).round();
        final b = (210 * s._ucB[k] / 1023).round();
        canvas.drawRect(Rect.fromLTWH(cx * cw, cy * ch, cw + 0.6, ch + 0.6),
            Paint()..color = Color.fromARGB(255, r, g, b));
      }
    }
    final gl = Paint()
      ..color = Colors.black.withValues(alpha: 0.10)
      ..strokeWidth = 0.75;
    for (int cx = 1; cx < nx; cx++) {
      canvas.drawLine(Offset(cx * cw, 0), Offset(cx * cw, ss.height), gl);
    }
    for (int cy = 1; cy < ny; cy++) {
      canvas.drawLine(Offset(0, cy * ch), Offset(ss.width, cy * ch), gl);
    }
    canvas.drawRect(
        Offset.zero & ss,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18));

    // Control points.
    for (int i = 0; i < s._ucPts.length; i++) {
      final p = s._ucPts[i];
      final c = HSVColor.fromAHSV(1, p.hue % 360, 0.85, 1).toColor();
      final ctr = Offset(p.x * ss.width, p.y * ss.height);
      final sel = s._ucSel == i;
      if (sel) {
        // Falloff extent — an ellipse (x compressed by the frame aspect, since
        // the bake measures distance in aspect-corrected units).
        canvas.drawOval(
            Rect.fromCenter(
                center: ctr,
                width: 2 * p.radius / (_outW / _outH) * ss.width,
                height: 2 * p.radius * ss.height),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = c.withValues(alpha: 0.6));
      }
      canvas.drawCircle(ctr, sel ? 8 : 6, Paint()..color = c);
      canvas.drawCircle(
          ctr,
          sel ? 8 : 6,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = sel ? Colors.white : const Color(0x99000000));
      canvas.drawCircle(ctr, 2, Paint()..color = const Color(0x99000000));
    }
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) => true;
}

// ── Warp tool button with press-drag mesh-size menu ───────────────────────────
class _WarpToolButton extends StatefulWidget {
  final bool active;
  final int n;
  final ValueChanged<int> onPick;
  const _WarpToolButton(
      {required this.active, required this.n, required this.onPick});
  @override
  State<_WarpToolButton> createState() => _WarpToolButtonState();
}

class _WarpToolButtonState extends State<_WarpToolButton> {
  static const sizes = [2, 3, 4, 5, 6, 8];
  final _key = GlobalKey();
  OverlayEntry? _entry;
  int _hoverIdx = -1;
  Rect _menu = Rect.zero;
  final double _ih = 32;

  void _open() {
    final n = widget.n < 2 ? 4 : widget.n;
    widget.onPick(n); // activates warp with current/default N
    final box = _key.currentContext!.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero);
    _menu = Rect.fromLTWH(tl.dx, tl.dy + box.size.height + 4,
        math.max(box.size.width, 56), sizes.length * _ih);
    _hoverIdx = sizes.indexOf(n);
    _entry = OverlayEntry(builder: (_) => _build());
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _hoverIdx = -1;
  }

  int _at(Offset g) {
    if (!_menu.inflate(8).contains(g)) return -1;
    final i = ((g.dy - _menu.top) / _ih).floor();
    return (i >= 0 && i < sizes.length) ? i : -1;
  }

  Widget _build() {
    final t = GridProvider.of(context);
    return Positioned(
        left: _menu.left,
        top: _menu.top,
        width: _menu.width,
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
                color: const Color(0xFF212124),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 14)
                ]),
            clipBehavior: Clip.antiAlias,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (int i = 0; i < sizes.length; i++)
                Container(
                    height: _ih,
                    width: double.infinity,
                    alignment: Alignment.center,
                    color: i == _hoverIdx
                        ? _amber
                        : (sizes[i] == widget.n
                            ? _amber.withValues(alpha: 0.18)
                            : Colors.transparent),
                    child: Text('${sizes[i]}×${sizes[i]}',
                        style: t.textLabel.copyWith(
                            color: i == _hoverIdx ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w700))),
            ]),
          ),
        ));
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final on = widget.active;
    return Padding(
        padding: EdgeInsets.only(left: t.xs),
        child: Listener(
          onPointerDown: (_) => _open(),
          onPointerMove: (e) {
            final i = _at(e.position);
            if (i != _hoverIdx) {
              _hoverIdx = i;
              _entry?.markNeedsBuild();
            }
          },
          onPointerUp: (_) {
            if (_hoverIdx >= 0) widget.onPick(sizes[_hoverIdx]);
            _close();
          },
          child: Container(
            key: _key,
            padding:
                EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
            decoration: BoxDecoration(
                color: on ? _amber : const Color(0xFF212124),
                borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.grid_on,
                  size: t.u * 1.4,
                  color: on ? Colors.black : const Color(0xFF8A8A92)),
              SizedBox(width: t.xs),
              Text('Warp',
                  style: t.textCaption.copyWith(
                      color: on ? Colors.black : const Color(0xFF8A8A92),
                      fontWeight: FontWeight.w700)),
              if (widget.n >= 2) ...[
                SizedBox(width: t.xs * 0.8),
                Text('${widget.n}',
                    style: t.textCaption.copyWith(
                        color: on ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w700))
              ],
              Icon(Icons.arrow_drop_down,
                  size: t.u * 1.4,
                  color: on ? Colors.black : const Color(0xFF8A8A92)),
            ]),
          ),
        ));
  }
}
