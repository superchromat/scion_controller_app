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
import 'grid.dart';
import 'labeled_card.dart';
import 'network.dart';
import 'osc_registry.dart';
import 'osc_widget_binding.dart';

const _amber = Color(0xFFF0B830);
const _blue = Color(0xFF9AA6FF);
const _teal = Color(0xFF66E0C0);
const _green = Color(0xFF56C271);

// Output raster the canvas maps into (px). Keystone corners + mesh points are
// sent in these coordinates.
const double _outW = 1920, _outH = 1080;
const int _warpMeshMax = 9;

class ShapeCanvas extends StatefulWidget {
  final int? pageNumber; // null/1 = Send 1 (full rig); 2/3 = reduced; Return uses 2 under /output
  const ShapeCanvas({super.key, this.pageNumber});
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
  double keyH = 0, keyV = 0, shearX = 0, shearY = 0; // keystone/shear px (output)
  double barrel = 0;                                 // lens k2 x1000 (<0 barrel)
  double lensX = 0, lensY = 0;                       // lens optical centre px (output)
  int meshN = 0;
  final List<Offset> mesh = List<Offset>.filled(_warpMeshMax * _warpMeshMax, Offset.zero); // px

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

  // ── ui state ───────────────────────────────────────────────────────────────
  String tool = 'move'; // move | warp
  String? _drag;
  double _px0 = 0, _py0 = 0;
  Offset _p0 = Offset.zero;
  Size _size = Size.zero;
  Offset _stageOffset = Offset.zero;
  Offset? _hover;

  bool get _full => widget.pageNumber == null || widget.pageNumber == 1;
  bool get _canRotate => _full; // rotation/keystone/warp are Send-1 only
  double get rotDeg => rotOsc - 180; // degrees from identity

  String _base = '';
  bool _wired = false;
  final Map<String, void Function(List<Object?>)> _subs = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_wired) return;
    _wired = true;
    final segs = OscPathSegment.resolvePath(context);
    _base = segs.isEmpty ? '' : '/${segs.join('/')}';
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
        if (_lutDirty || _animating) { _lutDirty = false; _requestLut(); }
      });
      // Seed the first LUT once the widget is mounted / connected.
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestLut());
    }
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
    }
    _subs[resetAddr] = onReset;
    OscRegistry().registerListener(resetAddr, onReset);
  }

  void _bindD(String rel, void Function(double) set) {
    final addr = '$_base/$rel';
    final reg = OscRegistry()..registerAddress(addr);
    final cur = reg.allParams[addr]?.currentValue;
    if (cur != null && cur.isNotEmpty && cur.first is num) set((cur.first as num).toDouble());
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
    if (cur != null && cur.isNotEmpty && cur.first is num) set((cur.first as num).toInt());
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
      final pts = List<Offset>.generate(n * n, (k) => Offset(
          bd.getInt16(k * 4, Endian.little) / 4096.0,
          bd.getInt16(k * 4 + 2, Endian.little) / 4096.0));
      if (!mounted) return;
      setState(() { _lutN = n; _lut = pts; });
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
            mesh[k] = Offset(vals[k * 2].toDouble(), vals[k * 2 + 1].toDouble());
          }
        }
      });
    }
    _subs[addr] = cb;
    reg.registerListener(addr, cb);
  }

  @override
  void dispose() {
    _lutPoll?.cancel();
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
      rotDeg: rotDeg, cl: cl, cr: cr, ct: ct, cb: cb,
      sx: scaleX, sy: scaleY, px: posX, py: posY, mesh: mesh, n: meshN,
      keyH: keyH, keyV: keyV, shearX: shearX, shearY: shearY,
      barrel: barrel, lensX: lensX, lensY: lensY);

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
      final a = math.atan2(p.dy - g.center.dy, p.dx - g.center.dx) * 180 / math.pi;
      double rd = -(a + 90);
      double osc = rd + 180;
      osc = ((osc % 360) + 360) % 360;
      setState(() => rotOsc = osc);
      _send('shape/rotation', [osc]);
    } else if (d == 'body') {
      final nx = (_px0 + (p.dx - _p0.dx) / _size.width).clamp(0.0, 1.0);
      final ny = (_py0 + (p.dy - _p0.dy) / _size.height).clamp(0.0, 1.0);
      setState(() { posX = nx; posY = ny; });
      _send('shape/pos/x', [nx]);
      _send('shape/pos/y', [ny]);
    } else if (d.startsWith('e')) {
      final i = int.parse(d.substring(1));
      final (u, v) = _invMap(p, g);
      switch (i) {
        case 0: final t = v.clamp(0.0, 0.95); setState(() => ct = t); _send('shape/crop/top', [t]); break;
        case 1: final t = (1 - u).clamp(0.0, 0.95); setState(() => cr = t); _send('shape/crop/right', [t]); break;
        case 2: final t = (1 - v).clamp(0.0, 0.95); setState(() => cb = t); _send('shape/crop/bottom', [t]); break;
        case 3: final t = u.clamp(0.0, 0.95); setState(() => cl = t); _send('shape/crop/left', [t]); break;
      }
    } else if (d == 'lens') {
      // lens optical centre → the same lens_x / lens_y the knobs bind to, so the
      // puck, the knobs, and the canvas all stay in sync (lens_center is a
      // separate address the knobs don't listen on).
      final o = _unrot(p, g);
      final lx = (o.dx / g.fw * _outW).clamp(-960.0, 960.0);
      final ly = (o.dy / g.fh * _outH).clamp(-540.0, 540.0);
      setState(() { lensX = lx; lensY = ly; });
      _send('shape/warp/lens_x', [lx.round()]);
      _send('shape/warp/lens_y', [ly.round()]);
    } else if (d.startsWith('s')) {
      // scale — centre-anchored. The frame half-extent is fw/2 = size·scale/2,
      // so scale = 2·|frame-local offset| / stage size (matches _computeGeo).
      final o = _unrot(p, g);
      final nsx = (2 * o.dx.abs() / _size.width).clamp(0.05, 4.0);
      final nsy = (2 * o.dy.abs() / _size.height).clamp(0.05, 4.0);
      setState(() { scaleX = nsx; scaleY = nsy; });
      _send('shape/scale/x', [nsx]);
      _send('shape/scale/y', [nsy]);
    } else if (d.startsWith('w')) {
      // mesh vertex — px displacement
      final k = int.parse(d.substring(1));
      final n = meshN;
      final i = k % n, j = k ~/ n;
      Offset lp(Offset a, Offset b, double t) => Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      Offset bil(List<Offset> q, double u, double v) => lp(lp(q[0], q[1], u), lp(q[3], q[2], u), v);
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

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    // Big working area filling the left side; the 16:9 output frame is centred
    // inside it, so handles can roam into the margin and stay grabbable.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('TRANSFORM', style: t.textCaption.copyWith(letterSpacing: 1.5, color: const Color(0xFF8A8A92))),
        const Spacer(),
        _toolBtn(t, Icons.open_with, 'Move', 'move'),
        if (_full) _WarpToolButton(active: tool == 'warp', n: meshN, onPick: (n) { setState(() => tool = 'warp'); if (n != meshN) _setMeshSize(n); }),
      ]),
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
                onHover: (e) => setState(() => _hover = e.localPosition - _stageOffset),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (dg) {
                    final p = dg.localPosition - _stageOffset;
                    final hit = _hit(p);
                    setState(() {
                      if (hit != null) { _drag = hit; }
                      else if (tool == 'move') { _drag = 'body'; _p0 = p; _px0 = posX; _py0 = posY; }
                      else { _drag = null; }
                    });
                  },
                  onPanUpdate: (dg) => _apply(dg.localPosition - _stageOffset),
                  onPanEnd: (_) => setState(() => _drag = null),
                  child: CustomPaint(painter: _ShapePainter(this, _drag ?? (_hover == null ? null : _hit(_hover!)))),
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _toolBtn(GridTokens t, IconData ic, String label, String key) => Padding(
        padding: EdgeInsets.only(left: t.xs),
        child: GestureDetector(
          onTap: () => setState(() => tool = key),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
            decoration: BoxDecoration(color: tool == key ? _amber : const Color(0xFF212124), borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic, size: t.u * 1.4, color: tool == key ? Colors.black : const Color(0xFF8A8A92)),
              SizedBox(width: t.xs),
              Text(label, style: t.textCaption.copyWith(color: tool == key ? Colors.black : const Color(0xFF8A8A92), fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

// ── shared geometry (stage-local; painter + hit-test agree) ───────────────────
class _Geo {
  final Offset center;
  final double ang, fw, fh, barrel;
  final List<Offset> full, quad, cropEdges, mesh;
  final Offset grip, lens;
  _Geo(this.center, this.ang, this.fw, this.fh, this.barrel, this.full, this.quad,
      this.cropEdges, this.mesh, this.grip, this.lens);
}

_Geo _computeGeo(Size size, {
  required double rotDeg, required double cl, required double cr, required double ct, required double cb,
  required double sx, required double sy, required double px, required double py,
  required List<Offset> mesh, required int n,
  double keyH = 0, double keyV = 0, double shearX = 0, double shearY = 0,
  double barrel = 0, double lensX = 0, double lensY = 0,
}) {
  final c = size.center(Offset.zero) + Offset((px - 0.5) * size.width * 0.5, (py - 0.5) * size.height * 0.5);
  final ang = -rotDeg * math.pi / 180;
  final ca = math.cos(ang), sa = math.sin(ang);
  final fw = size.width * sx.clamp(0.05, 4.0), fh = size.height * sy.clamp(0.05, 4.0);
  Offset rot(double dx, double dy) => c + Offset(dx * ca - dy * sa, dx * sa + dy * ca);
  // Keystone/shear corner offsets (output px → frame-local px), matching the
  // firmware's k[] deltas (warp_keystone_matrix).
  final kh = keyH / _outW * fw, kv = keyV / _outH * fh;
  final shx = shearX / _outW * fw, shy = shearY / _outH * fh;
  final full = [
    rot(-fw / 2 + kh - shx, -fh / 2 + kv - shy), // TL
    rot(fw / 2 - kh - shx, -fh / 2 + shy),        // TR
    rot(fw / 2 + shx, fh / 2 + shy),              // BR
    rot(-fw / 2 + shx, fh / 2 - kv - shy),        // BL
  ];
  Offset lerp(Offset a, Offset b, double t) => Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  Offset bil(List<Offset> q, double u, double v) => lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v);
  final quad = [bil(full, cl, ct), bil(full, 1 - cr, ct), bil(full, 1 - cr, 1 - cb), bil(full, cl, 1 - cb)];
  final cropEdges = [lerp(quad[0], quad[1], .5), lerp(quad[1], quad[2], .5), lerp(quad[2], quad[3], .5), lerp(quad[3], quad[0], .5)];
  final topFull = lerp(full[0], full[1], .5);
  final dir = topFull - c;
  final grip = topFull + (dir.distance == 0 ? const Offset(0, -1) : dir / dir.distance) * 26;
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
  return Offset(d.dx * math.cos(g.ang) + d.dy * math.sin(g.ang), -d.dx * math.sin(g.ang) + d.dy * math.cos(g.ang));
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
    if (h > size.height) { h = size.height; w = h * 16 / 9; }
    s._size = Size(w, h);
    s._stageOffset = Offset((size.width - w) / 2, (size.height - h) / 2);

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF08080A));
    canvas.save();
    canvas.translate(s._stageOffset.dx, s._stageOffset.dy);
    final ss = s._size;
    final r = Offset.zero & ss;
    canvas.drawRect(r, Paint()..color = const Color(0xFF0A0A0C));
    final grid = Paint()..color = Colors.white.withValues(alpha: 0.05)..strokeWidth = 1;
    for (int i = 1; i < 16; i++) canvas.drawLine(Offset(ss.width * i / 16, 0), Offset(ss.width * i / 16, ss.height), grid);
    for (int i = 1; i < 9; i++) canvas.drawLine(Offset(0, ss.height * i / 9), Offset(ss.width, ss.height * i / 9), grid);
    canvas.drawRect(r.deflate(1), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.18));

    final g = s._geo();
    Offset lerp(Offset a, Offset b, double t) => Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    final warping = s._full && s.tool == 'warp';

    // Nominal (un-warped) output frame — faint white reference rectangle.
    canvas.drawPath(Path()..addPolygon(g.full, true), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.18));

    // Content = the real device deformation (forward LUT: keystone/barrel/lens/
    // field/mesh, live-animated), or the parametric cropped quad until it lands.
    final lut = s._lut;
    final ln = s._lutN;
    final hasLut = lut != null && ln >= 2;
    Offset lp(int i, int j) => Offset(lut![j * ln + i].dx * ss.width, lut[j * ln + i].dy * ss.height);
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
    final hatch = Paint()..color = _amber.withValues(alpha: 0.10)..strokeWidth = 1;
    for (double d = -ss.height; d < ss.width; d += 10) canvas.drawLine(Offset(d, 0), Offset(d + ss.height, ss.height), hatch);
    canvas.restore();
    if (!warping) {
      if (hasLut) {
        // Interior deformation grid straight from the device.
        final gl = Paint()..color = _amber.withValues(alpha: 0.20)..strokeWidth = 0.75;
        for (int j = 0; j < ln; j++) {
          for (int i = 0; i < ln; i++) {
            if (i < ln - 1) canvas.drawLine(lp(i, j), lp(i + 1, j), gl);
            if (j < ln - 1) canvas.drawLine(lp(i, j), lp(i, j + 1), gl);
          }
        }
      } else {
        final thirds = Paint()..color = _amber.withValues(alpha: 0.22)..strokeWidth = 0.75;
        for (int i = 1; i < 3; i++) {
          canvas.drawLine(lerp(g.quad[0], g.quad[1], i / 3), lerp(g.quad[3], g.quad[2], i / 3), thirds);
          canvas.drawLine(lerp(g.quad[0], g.quad[3], i / 3), lerp(g.quad[1], g.quad[2], i / 3), thirds);
        }
      }
    }
    canvas.drawPath(bp, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = _amber);
    final aa = warping ? 0.5 : 1.0;
    // scale corners (blue circles)
    for (int i = 0; i < 4; i++) {
      final on = hot == 's$i';
      canvas.drawCircle(g.full[i], on ? 8 : 6, Paint()..color = (on ? Colors.white : _blue).withValues(alpha: on ? 1 : aa));
    }
    // crop bars — oriented along the frame edges
    for (int i = 0; i < 4; i++) {
      final on = hot == 'e$i';
      final edge = g.quad[(i + 1) % 4] - g.quad[i];
      final ang = math.atan2(edge.dy, edge.dx);
      canvas.save(); canvas.translate(g.cropEdges[i].dx, g.cropEdges[i].dy); canvas.rotate(ang);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: on ? 20 : 16, height: on ? 7 : 6), const Radius.circular(2)),
          Paint()..color = (on ? Colors.white : _amber).withValues(alpha: on ? 1 : aa));
      canvas.restore();
    }
    // warp mesh
    if (warping && g.mesh.isNotEmpty) {
      final n = s.meshN;
      final line = Paint()..color = _teal.withValues(alpha: 0.55)..strokeWidth = 1;
      for (int j = 0; j < n; j++) {
        for (int i = 0; i < n; i++) {
          final p = g.mesh[j * n + i];
          if (i < n - 1) canvas.drawLine(p, g.mesh[j * n + i + 1], line);
          if (j < n - 1) canvas.drawLine(p, g.mesh[(j + 1) * n + i], line);
        }
      }
      for (int k = 0; k < g.mesh.length; k++) {
        final on = hot == 'w$k';
        canvas.drawCircle(g.mesh[k], on ? 6 : 4, Paint()..color = on ? Colors.white : _teal);
      }
    }
    // lens optical-centre puck (Send 1) — green dot, drag to set lens X/Y
    if (s._full) {
      final on = hot == 'lens';
      canvas.drawCircle(g.lens, on ? 13 : 11, Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = on ? Colors.white : _green);
      canvas.drawCircle(g.lens, 3.5, Paint()..color = _green);
    }
    // rotation grip (Send 1)
    if (s._canRotate) {
      final topFull = lerp(g.full[0], g.full[1], .5);
      canvas.drawLine(topFull, g.grip, Paint()..color = _amber..strokeWidth = 1.5);
      canvas.drawCircle(g.grip, hot == 'rot' ? 7 : 5, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = hot == 'rot' ? Colors.white : _amber);
      canvas.drawCircle(g.grip, hot == 'rot' ? 7 : 5, Paint()..color = const Color(0xFF0A0A0C));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ShapePainter old) => true;
}

// ── Warp tool button with press-drag mesh-size menu ───────────────────────────
class _WarpToolButton extends StatefulWidget {
  final bool active;
  final int n;
  final ValueChanged<int> onPick;
  const _WarpToolButton({required this.active, required this.n, required this.onPick});
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
    _menu = Rect.fromLTWH(tl.dx, tl.dy + box.size.height + 4, math.max(box.size.width, 56), sizes.length * _ih);
    _hoverIdx = sizes.indexOf(n);
    _entry = OverlayEntry(builder: (_) => _build());
    Overlay.of(context).insert(_entry!);
  }

  void _close() { _entry?.remove(); _entry = null; _hoverIdx = -1; }
  int _at(Offset g) {
    if (!_menu.inflate(8).contains(g)) return -1;
    final i = ((g.dy - _menu.top) / _ih).floor();
    return (i >= 0 && i < sizes.length) ? i : -1;
  }

  Widget _build() {
    final t = GridProvider.of(context);
    return Positioned(left: _menu.left, top: _menu.top, width: _menu.width, child: Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(color: const Color(0xFF212124), borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14)]),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < sizes.length; i++)
            Container(height: _ih, width: double.infinity, alignment: Alignment.center,
                color: i == _hoverIdx ? _amber : (sizes[i] == widget.n ? _amber.withValues(alpha: 0.18) : Colors.transparent),
                child: Text('${sizes[i]}×${sizes[i]}', style: t.textLabel.copyWith(color: i == _hoverIdx ? Colors.black : Colors.white, fontWeight: FontWeight.w600))),
        ]),
      ),
    ));
  }

  @override
  void dispose() { _entry?.remove(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final on = widget.active;
    return Padding(padding: EdgeInsets.only(left: t.xs), child: Listener(
      onPointerDown: (_) => _open(),
      onPointerMove: (e) { final i = _at(e.position); if (i != _hoverIdx) { _hoverIdx = i; _entry?.markNeedsBuild(); } },
      onPointerUp: (_) { if (_hoverIdx >= 0) widget.onPick(sizes[_hoverIdx]); _close(); },
      child: Container(key: _key, padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
        decoration: BoxDecoration(color: on ? _amber : const Color(0xFF212124), borderRadius: BorderRadius.circular(4)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.grid_on, size: t.u * 1.4, color: on ? Colors.black : const Color(0xFF8A8A92)),
          SizedBox(width: t.xs),
          Text('Warp', style: t.textCaption.copyWith(color: on ? Colors.black : const Color(0xFF8A8A92), fontWeight: FontWeight.w600)),
          if (widget.n >= 2) ...[SizedBox(width: t.xs * 0.8), Text('${widget.n}', style: t.textCaption.copyWith(color: on ? Colors.black : Colors.white, fontWeight: FontWeight.w700))],
          Icon(Icons.arrow_drop_down, size: t.u * 1.4, color: on ? Colors.black : const Color(0xFF8A8A92)),
        ]),
      ),
    ));
  }
}
