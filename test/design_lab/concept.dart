// CONCEPT: "Signal Desk" — the signal is the interface.
//
// A Send-1 surface reconceived around the live image. The processed frame is
// the central canvas with direct-manipulation overlays (crop handles, colour-
// field puck, text anchor, safe area). The signal chain is a column of small
// multiples. The Tone instrument reads grade + posterize against ONE live luma
// histogram. Neumorphic depth encodes state, not decoration.
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:SCION_Controller/grid.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/panel.dart';
import 'package:SCION_Controller/rotary_knob.dart';
import 'blocks.dart';

/// Interactive prototype state shared across the Send-1 desk. Not wired to OSC —
/// it makes the layout a real UX test: selecting a stage swaps the instrument,
/// and the Geometry controls drive the canvas live.
class _DeskModel extends ChangeNotifier {
  String stage = 'tone'; // selected chain stage
  String tool = 'move'; // selected canvas tool: move | warp | field
  double rotDeg = 12;
  double scaleX = 1, scaleY = 1;
  double posX = 0.5, posY = 0.5;
  double cl = 0.12, cr = 0.06, ct = 0.10, cb = 0.08;
  double fieldU = 0.68,
      fieldV = 0.42; // colour-field puck, in source-local coords
  int warpN = 4; // WARP LUT mesh resolution (N×N vertices), adjustable
  List<Offset> warp =
      List<Offset>.filled(4 * 4, Offset.zero); // normalized offsets
  int warpRev =
      0; // bumps on any warp change (in-place list can't be diffed by ref)
  // Per-corner keystone: a corner "freed" by double-click drags independently
  // (perspective/shear); locked corners scale symmetrically.
  final List<Offset> cornerWarp = List<Offset>.filled(4, Offset.zero);
  final Set<int> freeCorners = <int>{};
  void selectStage(String s) {
    stage = s;
    notifyListeners();
  }

  void selectTool(String s) {
    tool = s;
    notifyListeners();
  }

  void setWarp(int i, Offset off) {
    warp[i] = Offset(off.dx.clamp(-0.4, 0.4), off.dy.clamp(-0.4, 0.4));
    warpRev++;
    notifyListeners();
  }

  void setWarpN(int n) {
    n = n.clamp(2, 8);
    if (n == warpN) return;
    warpN = n;
    warp = List<Offset>.filled(
        n * n, Offset.zero); // resample would preserve work; reset for now
    warpRev++;
    notifyListeners();
  }

  void resetWarp() {
    for (var i = 0; i < warp.length; i++) {
      warp[i] = Offset.zero;
    }
    warpRev++;
    notifyListeners();
  }

  void toggleFreeCorner(int i) {
    if (freeCorners.contains(i)) {
      freeCorners.remove(i);
      cornerWarp[i] = Offset.zero;
    } else {
      freeCorners.add(i);
    }
    warpRev++;
    notifyListeners();
  }

  void setCornerWarp(int i, Offset off) {
    cornerWarp[i] = Offset(off.dx.clamp(-0.6, 0.6), off.dy.clamp(-0.6, 0.6));
    warpRev++;
    notifyListeners();
  }

  void setRot(double d) {
    rotDeg = d.clamp(-180, 180);
    notifyListeners();
  }

  void nudgeRot(double d) {
    rotDeg = (rotDeg + d).clamp(-180, 180);
    notifyListeners();
  }

  void setScale({double? x, double? y}) {
    if (x != null) scaleX = x.clamp(0.1, 2);
    if (y != null) scaleY = y.clamp(0.1, 2);
    notifyListeners();
  }

  void setPos({double? x, double? y}) {
    if (x != null) posX = x.clamp(0, 1);
    if (y != null) posY = y.clamp(0, 1);
    notifyListeners();
  }

  void setField({double? u, double? v}) {
    if (u != null) fieldU = u.clamp(0, 1);
    if (v != null) fieldV = v.clamp(0, 1);
    notifyListeners();
  }

  void setCrop({double? l, double? r, double? t, double? b}) {
    if (l != null) cl = l.clamp(0, 0.45);
    if (r != null) cr = r.clamp(0, 0.45);
    if (t != null) ct = t.clamp(0, 0.45);
    if (b != null) cb = b.clamp(0, 0.45);
    notifyListeners();
  }
}

/// Shared geometry: the transform's on-canvas points, computed identically for
/// the painter and the hit-tester so handles land exactly where they're drawn.
class _GeoLayout {
  final Offset center;
  final double ang, fw, fh;
  final List<Offset> full; // TL,TR,BR,BL — source frame corners (SCALE handles)
  final List<Offset> quad; // TL,TR,BR,BL — retained content after crop
  final List<Offset>
      cropEdges; // top,right,bottom,left midpoints (CROP handles)
  final List<Offset> mesh; // N×N deformed WARP vertices (canvas space)
  final Offset grip, puck;
  _GeoLayout(this.center, this.ang, this.fw, this.fh, this.full, this.quad,
      this.cropEdges, this.mesh, this.grip, this.puck);
}

_GeoLayout _computeGeo(
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
  required double fu,
  required double fv,
  List<Offset>? warp,
  int n = 4,
  List<Offset>? cornerWarp,
}) {
  final base = size.center(Offset.zero);
  final c = base +
      Offset((px - 0.5) * size.width * 0.5, (py - 0.5) * size.height * 0.5);
  final ang = -rotDeg * math.pi / 180;
  final ca = math.cos(ang), sa = math.sin(ang);
  final fw = size.width * 0.5 * sx, fh = size.height * 0.62 * sy;
  Offset rot(double dx, double dy) =>
      c + Offset(dx * ca - dy * sa, dx * sa + dy * ca);
  // full frame corners, each optionally displaced (keystone) by cornerWarp
  Offset corner(int i, double bx, double by) {
    var p = rot(bx, by);
    final o = (cornerWarp != null && cornerWarp.length == 4)
        ? cornerWarp[i]
        : Offset.zero;
    if (o != Offset.zero) {
      final dx = o.dx * fw, dy = o.dy * fh;
      p += Offset(dx * ca - dy * sa, dx * sa + dy * ca);
    }
    return p;
  }

  final full = [
    corner(0, -fw / 2, -fh / 2),
    corner(1, fw / 2, -fh / 2),
    corner(2, fw / 2, fh / 2),
    corner(3, -fw / 2, fh / 2)
  ];
  Offset lerp(Offset a, Offset b, double t) =>
      Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
  Offset bilerp(List<Offset> q, double u, double v) =>
      lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v);
  final quad = [
    bilerp(full, cl, ct),
    bilerp(full, 1 - cr, ct),
    bilerp(full, 1 - cr, 1 - cb),
    bilerp(full, cl, 1 - cb)
  ];
  final cropEdges = [
    lerp(quad[0], quad[1], 0.5),
    lerp(quad[1], quad[2], 0.5),
    lerp(quad[2], quad[3], 0.5),
    lerp(quad[3], quad[0], 0.5)
  ];
  // rotation grip anchored to the FULL frame's top edge (crop-independent)
  final topFull = lerp(full[0], full[1], 0.5);
  final dir = topFull - c;
  final grip = topFull +
      (dir.distance == 0 ? const Offset(0, -1) : dir / dir.distance) * 26;
  // WARP mesh: grid over the cropped content, displaced by warp offsets (local, rotated)
  final mesh = <Offset>[];
  for (int j = 0; j < n; j++) {
    for (int i = 0; i < n; i++) {
      final baseP = bilerp(quad, i / (n - 1), j / (n - 1));
      final off = (warp != null && warp.length == n * n)
          ? warp[j * n + i]
          : Offset.zero;
      final dx = off.dx * fw, dy = off.dy * fh; // local displacement
      mesh.add(baseP + Offset(dx * ca - dy * sa, dx * sa + dy * ca));
    }
  }
  return _GeoLayout(
      c, ang, fw, fh, full, quad, cropEdges, mesh, grip, bilerp(full, fu, fv));
}

/// Inverse-map a canvas point into the source frame's [0,1] local (u,v).
(double, double) _invMap(Offset p, _GeoLayout g) {
  final d = p - g.center;
  final lx = d.dx * math.cos(g.ang) + d.dy * math.sin(g.ang);
  final ly = -d.dx * math.sin(g.ang) + d.dy * math.cos(g.ang);
  return (lx / g.fw + 0.5, ly / g.fh + 0.5);
}

/// Unrotate a canvas point to the frame's local pixel offset from centre.
Offset _unrot(Offset p, _GeoLayout g) {
  final d = p - g.center;
  return Offset(d.dx * math.cos(g.ang) + d.dy * math.sin(g.ang),
      -d.dx * math.sin(g.ang) + d.dy * math.cos(g.ang));
}

/// An interactive knob bound to external state (two-way): drag turns it and
/// fires [onChanged]; [value] flows back in. Reuses the real RotaryKnob.
class _IKnob extends StatelessWidget {
  final String label;
  final double value, min, max;
  final ValueChanged<double> onChanged;
  final bool bipolar;
  final double? size;
  final String fmt;
  final double
      def; // default/neutral — draws the detent + is the double-tap reset target
  const _IKnob(this.label, this.value, this.min, this.max, this.onChanged,
      {this.bipolar = false, this.fmt = '%.2f', this.def = 0})
      : size = null;
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      RotaryKnob(
        value: value,
        minValue: min,
        maxValue: max,
        isBipolar: bipolar,
        size: size ?? t.knobSm,
        format: fmt,
        onChanged: onChanged,
        defaultValue: def,
        neutralValue: def,
      ),
      SizedBox(height: t.xs * 0.8),
      Text(label, style: t.textLabel.copyWith(color: _dim)),
    ]);
  }
}

// One shared set of posterize thresholds (normalized luma) used by BOTH the
// histogram tick overlay and the band strip, so the "one tonal axis" claim is
// literally true in the pixels.
const List<double> _posterTh = [
  0.10,
  0.18,
  0.26,
  0.34,
  0.42,
  0.5,
  0.58,
  0.66,
  0.74,
  0.82,
  0.90
];

const _bg = Color(0xFF141416);
const _panel = Color(0xFF212124);
const _ink = Color(0xFFE8E8EA);
const _amber = Color(0xFFF0B830);
const _green = Color(0xFF56C271);
const _dim = Color(0xFF8A8A92);

// ─────────────────────────────────────────────────────────────────────────────
class SignalDesk extends StatelessWidget {
  const SignalDesk({super.key});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => _DeskModel(),
        child: const _SignalDeskBody(),
      );
}

class _SignalDeskBody extends StatelessWidget {
  const _SignalDeskBody();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final stage = context.watch<_DeskModel>().stage;
    Widget instrument;
    switch (stage) {
      case 'geometry':
        instrument = const _GeometryInstrument();
      case 'tone':
        instrument = const _ToneInstrument();
      default:
        instrument = _PlaceholderInstrument(stage);
    }
    return Container(
      color: _bg,
      padding: EdgeInsets.all(t.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StatusStrip(),
          SizedBox(height: t.md),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: t.u * 16, child: const _SignalChain()),
                SizedBox(width: t.md),
                Expanded(flex: 5, child: const _HeroCanvas()),
                SizedBox(width: t.md),
                Expanded(flex: 3, child: instrument),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder for stages whose instrument isn't built in this prototype.
class _PlaceholderInstrument extends StatelessWidget {
  final String stage;
  const _PlaceholderInstrument(this.stage);
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return LabeledCard(
      title: '${stage[0].toUpperCase()}${stage.substring(1)}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: t.lg * 2),
        child: Center(
          child: Text('instrument not built in this prototype',
              style: t.textLabel.copyWith(color: _dim)),
        ),
      ),
    );
  }
}

/// Geometry instrument — interactive knobs bound to the shared model; turning
/// them moves the crop/rotation live on the canvas.
class _GeometryInstrument extends StatelessWidget {
  const _GeometryInstrument();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final m = context.watch<_DeskModel>();
    return LabeledCard(
      title: 'Geometry',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const LabSectionHeader('Transform'),
            SizedBox(height: t.sm),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _IKnob('Scale X', m.scaleX, 0.1, 2, (v) => m.setScale(x: v),
                  def: 1),
              _IKnob('Scale Y', m.scaleY, 0.1, 2, (v) => m.setScale(y: v),
                  def: 1),
              _IKnob('Pos X', m.posX, 0, 1, (v) => m.setPos(x: v), def: 0.5),
              _IKnob('Pos Y', m.posY, 0, 1, (v) => m.setPos(y: v), def: 0.5),
              _IKnob('Rotate', m.rotDeg, -180, 180, m.setRot,
                  bipolar: true, fmt: '%.0f', def: 0),
            ]),
            SizedBox(height: t.md),
            const LabSectionHeader('Crop'),
            SizedBox(height: t.sm),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _IKnob('Left', m.cl, 0, 0.45, (v) => m.setCrop(l: v), def: 0),
              _IKnob('Right', m.cr, 0, 0.45, (v) => m.setCrop(r: v), def: 0),
              _IKnob('Top', m.ct, 0, 0.45, (v) => m.setCrop(t: v), def: 0),
              _IKnob('Bottom', m.cb, 0, 0.45, (v) => m.setCrop(b: v), def: 0),
            ]),
            SizedBox(height: t.md),
            Text(
                'Canvas: outer corners scale (double-click a corner to free it for keystone/shear) · inner bars crop · grip rotates. Tools: Move · Warp (press-drag for mesh size) · Field.',
                style: t.textCaption.copyWith(color: _dim)),
          ]),
    );
  }
}

// ── top status strip: visibility of system status ────────────────────────────
class _StatusStrip extends StatelessWidget {
  const _StatusStrip();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    Widget stat(String k, String v, {Color c = _ink}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$k ', style: t.textCaption.copyWith(color: _dim)),
          Text(v, style: t.textValue.copyWith(color: c, fontSize: t.u * 1.2)),
        ]);
    return Row(children: [
      Text('SCION',
          style: t.textTitle
              .copyWith(fontWeight: FontWeight.w700, letterSpacing: 2)),
      SizedBox(width: t.xs),
      Text('SEND 1',
          style: t.textTitle.copyWith(color: _amber, letterSpacing: 2)),
      SizedBox(width: t.lg),
      Container(
        padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.6),
        decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(3)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: t.xs,
              height: t.xs,
              decoration:
                  const BoxDecoration(color: _green, shape: BoxShape.circle)),
          SizedBox(width: t.xs),
          Text('LOCKED',
              style: t.textCaption.copyWith(color: _green, letterSpacing: 1.5)),
        ]),
      ),
      SizedBox(width: t.lg),
      stat('IN', 'HDMI 1 · 3840×2160p60'), // real: /input status
      SizedBox(width: t.lg),
      stat('OUT', '1920×1080p59.94',
          c: _green), // real: /output/resolution + /framerate
      const Spacer(),
    ]);
  }
}

// ── left: the signal chain as vertical small multiples ───────────────────────
class _SignalChain extends StatelessWidget {
  const _SignalChain();
  // hasPreview: the device can only thumbnail a flat framebuffer. Once Send 1
  // rotates/warps (GEOMETRY), every downstream stage is 2D-mapped → no preview,
  // so those nodes show the transform schematically instead of faking pixels.
  static const stages = [
    ('INPUT', 'HDMI 1', 0, false, true),
    ('GEOMETRY', 'scale · rot · crop', 1, false, false),
    ('TONE', 'grade · poster', 2, true, false), // active
    ('TEXTURE', 'blur · grain', 3, false, false),
    ('GENERATE', 'field · text', 4, false, false),
    ('OUTPUT', 'return', 5, false, false),
  ];
  static String keyOf(String label) => label.toLowerCase();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final m = context.watch<_DeskModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('SIGNAL CHAIN',
          style: t.textCaption.copyWith(letterSpacing: 1.5, color: _dim)),
      SizedBox(height: t.sm),
      Expanded(
        child: Column(
          children: [
            for (final s in stages)
              Expanded(
                  child: Padding(
                padding: EdgeInsets.only(bottom: t.xs),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () =>
                      context.read<_DeskModel>().selectStage(keyOf(s.$1)),
                  child: _ChainNode(
                      label: s.$1,
                      sub: s.$2,
                      stage: s.$3,
                      active: m.stage == keyOf(s.$1),
                      hasPreview: s.$5),
                ),
              )),
          ],
        ),
      ),
    ]);
  }
}

class _ChainNode extends StatelessWidget {
  final String label, sub;
  final int stage;
  final bool active;
  final bool hasPreview;
  const _ChainNode(
      {required this.label,
      required this.sub,
      required this.stage,
      required this.active,
      this.hasPreview = false});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? _panel : const Color(0xFF191919),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: active
                ? _amber.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.05),
            width: active ? 1.2 : 1),
        boxShadow: active
            ? [
                BoxShadow(
                    color: _amber.withValues(alpha: 0.10),
                    blurRadius: 12,
                    spreadRadius: 1)
              ]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(t.xs),
        child: Row(children: [
          // stage preview: a real device thumbnail only where the framebuffer
          // is flat; a schematic transform glyph where it's 2D-mapped.
          SizedBox(
            width: t.u * 5.4,
            height: t.u * 3.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: hasPreview
                  ? CustomPaint(
                      painter: _FramePainter(stage: stage, pixel: true))
                  : CustomPaint(
                      painter: _ChainSchematicPainter(active: active)),
            ),
          ),
          SizedBox(width: t.sm),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textLabel.copyWith(
                        color: active ? _amber : _ink,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textCaption.copyWith(color: _dim)),
              ])),
        ]),
      ),
    );
  }
}

/// Schematic stand-in for a stage with no live preview (2D-mapped framebuffer):
/// a small rotated + cropped quad on a dotted stage — the transform, not a fake.
class _ChainSchematicPainter extends CustomPainter {
  final bool active;
  _ChainSchematicPainter({required this.active});
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF0E0E10));
    // dotted frame bounds
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.12);
    for (double x = 2; x < size.width; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, 2, 1.4, 1.4), dot);
      canvas.drawRect(Rect.fromLTWH(x, size.height - 3, 1.4, 1.4), dot);
    }
    final c = size.center(Offset.zero);
    final col = active ? _amber : const Color(0xFF6A6A72);
    final ang = -12 * math.pi / 180;
    Offset rot(double dx, double dy) =>
        c +
        Offset(dx * math.cos(ang) - dy * math.sin(ang),
            dx * math.sin(ang) + dy * math.cos(ang));
    final w = size.width * 0.34, h = size.height * 0.42;
    final quad = [rot(-w, -h), rot(w, -h), rot(w, h), rot(-w, h)];
    canvas.drawPath(
        Path()..addPolygon(quad, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = col.withValues(alpha: 0.9));
    canvas.drawLine(
        quad[0],
        quad[2],
        Paint()
          ..color = col.withValues(alpha: 0.25)
          ..strokeWidth = 0.75);
  }

  @override
  bool shouldRepaint(covariant _ChainSchematicPainter old) =>
      old.active != active;
}

// ── center: hero canvas with direct-manipulation overlays ────────────────────
class _HeroCanvas extends StatelessWidget {
  const _HeroCanvas();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final m = context.watch<_DeskModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('PROGRAM',
            style: t.textCaption.copyWith(letterSpacing: 1.5, color: _dim)),
        const Spacer(),
        _tool(context, t, Icons.open_with, 'Move', 'move', m.tool),
        const _WarpToolButton(),
        _tool(context, t, Icons.gradient, 'Field', 'field', m.tool),
      ]),
      SizedBox(height: t.sm),
      Expanded(
        child: NeumorphicInset(
          baseColor: const Color(0xFF0C0C0E),
          padding: EdgeInsets.all(t.xs),
          // Send 1 is rotated/warped, so the device returns no thumbnail. The
          // geometry IS the interface — drag the handles directly:
          //  · corner squares → crop that corner   · grip on the stalk → rotate
          //  · green puck → colour-field centre     · Move tool + body → position
          child: const _GeometryCanvas(),
        ),
      ),
    ]);
  }

  Widget _tool(BuildContext context, GridTokens t, IconData ic, String label,
          String key, String selected) =>
      Padding(
        padding: EdgeInsets.only(left: t.xs),
        child: GestureDetector(
          onTap: () => context.read<_DeskModel>().selectTool(key),
          child: Container(
            padding:
                EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
            decoration: BoxDecoration(
              color: key == selected ? _amber : _panel,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ic,
                  size: t.u * 1.4,
                  color: key == selected ? Colors.black : _dim),
              SizedBox(width: t.xs),
              Text(label,
                  style: t.textCaption.copyWith(
                      color: key == selected ? Colors.black : _dim,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );
}

/// Warp tool button with a press-drag mesh-size menu. Press → selects Warp and
/// pops a menu with the current N highlighted; release keeps it, or drag down
/// onto another size and release to change the mesh resolution.
class _WarpToolButton extends StatefulWidget {
  const _WarpToolButton();
  @override
  State<_WarpToolButton> createState() => _WarpToolButtonState();
}

class _WarpToolButtonState extends State<_WarpToolButton> {
  static const sizes = [2, 3, 4, 5, 6, 8];
  final _key = GlobalKey();
  OverlayEntry? _entry;
  int _hover = -1;
  Rect _menuRect = Rect.zero;
  final double _itemH = 32;

  void _open(_DeskModel m) {
    m.selectTool('warp');
    final box = _key.currentContext!.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero);
    final w = math.max(box.size.width, 56.0);
    _menuRect = Rect.fromLTWH(
        tl.dx, tl.dy + box.size.height + 4, w, sizes.length * _itemH);
    _hover = sizes.indexOf(m.warpN);
    _entry = OverlayEntry(builder: (_) => _menu(m));
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _hover = -1;
  }

  int _indexAt(Offset g) {
    if (!_menuRect.inflate(8).contains(g)) return -1;
    final i = ((g.dy - _menuRect.top) / _itemH).floor();
    return (i >= 0 && i < sizes.length) ? i : -1;
  }

  Widget _menu(_DeskModel m) {
    final t = GridProvider.of(context);
    return Positioned(
      left: _menuRect.left,
      top: _menuRect.top,
      width: _menuRect.width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF212124),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45), blurRadius: 14)
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < sizes.length; i++)
              Container(
                height: _itemH,
                width: double.infinity,
                alignment: Alignment.center,
                color: i == _hover
                    ? _amber
                    : (sizes[i] == m.warpN
                        ? _amber.withValues(alpha: 0.18)
                        : Colors.transparent),
                child: Text('${sizes[i]}×${sizes[i]}',
                    style: t.textLabel.copyWith(
                        color: i == _hover ? Colors.black : _ink,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    final m = context.watch<_DeskModel>();
    final on = m.tool == 'warp';
    return Padding(
      padding: EdgeInsets.only(left: t.xs),
      child: Listener(
        onPointerDown: (_) => _open(m),
        onPointerMove: (e) {
          final i = _indexAt(e.position);
          if (i != _hover) {
            _hover = i;
            _entry?.markNeedsBuild();
          }
        },
        onPointerUp: (_) {
          if (_hover >= 0) m.setWarpN(sizes[_hover]);
          _close();
        },
        child: Container(
          key: _key,
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.8),
          decoration: BoxDecoration(
              color: on ? _amber : _panel,
              borderRadius: BorderRadius.circular(4)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.grid_on,
                size: t.u * 1.4, color: on ? Colors.black : _dim),
            SizedBox(width: t.xs),
            Text('Warp',
                style: t.textCaption.copyWith(
                    color: on ? Colors.black : _dim,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: t.xs * 0.8),
            Text('${m.warpN}',
                style: t.textCaption.copyWith(
                    color: on ? Colors.black : _ink,
                    fontWeight: FontWeight.w700)),
            Icon(Icons.arrow_drop_down,
                size: t.u * 1.4, color: on ? Colors.black : _dim),
          ]),
        ),
      ),
    );
  }
}

// ── right: Tone instrument — grade + posterize on one live histogram ─────────
class _ToneInstrument extends StatelessWidget {
  const _ToneInstrument();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return LabeledCard(
      title: 'Tone',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── ONE tonal axis, stacked so grade-curve, histogram and posterize
            //    all read against the same 0..255 luma domain ──────────────────
            Text('LUMA  ·  256-bin histogram (WFM)  +  grade curve',
                style: t.textCaption.copyWith(letterSpacing: 1.0, color: _dim)),
            SizedBox(height: t.xs),
            SizedBox(
                height: t.u * 6.6,
                child: CustomPaint(
                    painter: _HistogramPainter(), size: Size.infinite)),
            // posterize band strip pinned to the SAME width/axis, directly below
            SizedBox(height: t.xs * 0.6),
            SizedBox(
                height: t.u * 2.6,
                child: CustomPaint(
                    painter: _BandStripPainter(), size: Size.infinite)),
            SizedBox(height: t.xs),
            _axisRuler(t),
            SizedBox(height: t.md),
            // ── 3-D engine ownership: grade wheels and an imported .cube LUT are
            //    the SAME hardware transform, mutually exclusive. Make it visible.
            const _EngineMode(),
            SizedBox(height: t.md),
            // ── grade — three tone zones, each a wheel + Contrast + Sat ─────────
            const LabSectionHeader('Grade · zones'),
            SizedBox(height: t.xs),
            Row(children: [
              Expanded(
                  child: _GradeZone(
                      name: 'Shadows',
                      angle: 2.4,
                      mag: 0.5,
                      con: 0.55,
                      sat: 0.6)),
              SizedBox(width: t.sm),
              Expanded(
                  child: _GradeZone(
                      name: 'Midtones',
                      angle: 0.6,
                      mag: 0.28,
                      con: 0.5,
                      sat: 0.5)),
              SizedBox(width: t.sm),
              Expanded(
                  child: _GradeZone(
                      name: 'Highlights',
                      angle: -1.1,
                      mag: 0.7,
                      con: 0.6,
                      sat: 0.45)),
            ]),
            SizedBox(height: t.sm),
            // master picture trio — global, distinct from the per-zone Con/Sat
            KnobPanel('Master',
                const [('Contrast', 0.55), ('Saturation', 0.62), ('Hue', 0.5)],
                bipolar: true, knobSize: t.knobSm),
            SizedBox(height: t.sm),
            // posterize strip above is the primary control (drag thresholds); the
            // per-band type/colour inspector appears on band-select, not always-on.
          ]),
    );
  }

  Widget _axisRuler(GridTokens t) => Row(children: [
        for (final l in const ['0', '', '64', '', '128', '', '192', '', '255'])
          Expanded(
              child: Text(l,
                  textAlign: l == '0'
                      ? TextAlign.left
                      : (l == '255' ? TextAlign.right : TextAlign.center),
                  style: t.textCaption
                      .copyWith(color: _dim, fontSize: t.u * 0.75))),
      ]);
}

/// The 3-D engine ownership indicator: grade wheels and an imported .cube LUT
/// occupy the SAME hardware transform and are mutually exclusive (firmware gates
/// the grade engine while a LUT is active). This makes that ownership visible —
/// the single most important tone-pipeline fact the current UI never states.
class _EngineMode extends StatelessWidget {
  const _EngineMode();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    Widget pill(String label, bool active) => Container(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.7),
          decoration: BoxDecoration(
            color: active ? _amber.withValues(alpha: 0.14) : _panel,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: active ? _amber : Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: t.xs,
                height: t.xs,
                decoration: BoxDecoration(
                    color: active ? _amber : _dim, shape: BoxShape.circle)),
            SizedBox(width: t.xs),
            Text(label,
                style: t.textCaption.copyWith(
                    color: active ? _amber : _dim,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5)),
          ]),
        );
    Widget btn(String label) => Container(
          padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.7),
          decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
          child: Text(label, style: t.textCaption.copyWith(color: _ink)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('3-D ENGINE',
          style: t.textCaption.copyWith(letterSpacing: 1.5, color: _dim)),
      SizedBox(height: t.xs),
      Row(children: [
        pill('Grade', true),
        Padding(
            padding: EdgeInsets.symmetric(horizontal: t.xs),
            child: Text('⇄', style: t.textLabel.copyWith(color: _dim))),
        pill('.cube', false),
        const Spacer(),
        btn('Load…'),
        SizedBox(width: t.xs),
        btn('Export'),
      ]),
      SizedBox(height: t.xs * 0.6),
      Text('grade wheels own the transform — load a .cube to override',
          style: t.textCaption.copyWith(color: _dim, fontSize: t.u * 0.78)),
    ]);
  }
}

/// One grade tone-zone: colour wheel (shift x/y + lift) + Contrast + Sat knobs —
/// the full GradeZone from grade_wheels.dart, not a bare trackball.
class _GradeZone extends StatelessWidget {
  final String name;
  final double angle, mag, con, sat;
  const _GradeZone(
      {required this.name,
      required this.angle,
      required this.mag,
      required this.con,
      required this.sat});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return NeumorphicInset(
      baseColor: const Color(0xFF252527),
      padding: EdgeInsets.all(t.xs),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(name.toUpperCase(),
            style: t.textCaption.copyWith(
                color: _dim, letterSpacing: 0.8, fontSize: t.u * 0.82)),
        SizedBox(height: t.xs),
        SizedBox(
            width: t.u * 3.9,
            height: t.u * 3.9,
            child: CustomPaint(painter: _TrackballPainter(angle, mag))),
        SizedBox(height: t.xs),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          LabKnob('Con', value: con, size: t.knobSm * 0.82),
          LabKnob('Sat', value: sat, size: t.knobSm * 0.82),
        ]),
      ]),
    );
  }
}

class _TrackballPainter extends CustomPainter {
  final double angle, mag;
  _TrackballPainter(this.angle, this.mag);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    // recessed well
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0xFF1C1C20), Color(0xFF0E0E10)],
          ).createShader(Rect.fromCircle(center: c, radius: r)));
    // thin chromatic rim — muted, low alpha
    canvas.drawCircle(
        c,
        r - 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..shader = const SweepGradient(colors: [
            Color(0xFFB05858),
            Color(0xFFB0A050),
            Color(0xFF58B070),
            Color(0xFF50A0B0),
            Color(0xFF6858B0),
            Color(0xFFB058A0),
            Color(0xFFB05858),
          ]).createShader(Rect.fromCircle(center: c, radius: r))
          ..color = Colors.white.withValues(alpha: 0.5));
    // inner ring guide
    canvas.drawCircle(
        c,
        r * 0.62,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = Colors.white.withValues(alpha: 0.10));
    // centre reference
    canvas.drawCircle(
        c, 1.5, Paint()..color = Colors.white.withValues(alpha: 0.25));
    // position node + connecting line
    final node = c + Offset(math.cos(angle), math.sin(angle)) * r * 0.62 * mag;
    canvas.drawLine(
        c,
        node,
        Paint()
          ..color = _amber.withValues(alpha: 0.6)
          ..strokeWidth = 1);
    canvas.drawCircle(node, r * 0.14, Paint()..color = Colors.white);
    canvas.drawCircle(
        node,
        r * 0.14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _amber);
  }

  @override
  bool shouldRepaint(covariant _TrackballPainter old) =>
      old.angle != angle || old.mag != mag;
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────────────────────

/// A plausible video still — synthwave sunset — that visibly TRANSFORMS per
/// pipeline stage so the small multiples read as the image at each stage
/// (macro→micro). Each stage applies a bold, glanceable signature.
class _FramePainter extends CustomPainter {
  final int stage;
  final bool pixel; // render at true device thumbnail resolution (64×32)
  _FramePainter({required this.stage, this.pixel = false});

  static const int _tw = 64, _th = 32; // matches firmware THUMB_W/THUMB_H

  void _scene(Canvas canvas, Size size, {double sunY = 0.60}) {
    final r = Offset.zero & size;
    canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF2A1A4A),
              Color(0xFF7A2E6A),
              Color(0xFFE86A4A),
              Color(0xFFF0B060)
            ],
            stops: [0, 0.42, 0.66, 0.78],
          ).createShader(r));
    final sunC = Offset(size.width * 0.5, size.height * sunY);
    final sunR = size.height * 0.30;
    canvas.drawCircle(
        sunC,
        sunR,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFE27A), Color(0xFFFF7050)],
          ).createShader(Rect.fromCircle(center: sunC, radius: sunR)));
    final gap = Paint()..color = const Color(0xFF7A2E6A).withValues(alpha: 0.9);
    for (double y = sunC.dy; y < sunC.dy + sunR; y += size.height * 0.05) {
      canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, size.height * 0.02 + 0.6), gap);
    }
    final horizon = size.height * (sunY + 0.06);
    canvas.drawRect(Rect.fromLTRB(0, horizon, size.width, size.height),
        Paint()..color = const Color(0xFF150A20));
    final grid = Paint()
      ..color = const Color(0xFF7A5AE0).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    final vp = Offset(size.width * 0.5, horizon);
    for (int i = -6; i <= 6; i++) {
      canvas.drawLine(
          Offset(size.width * 0.5 + i * size.width * 0.16, size.height),
          vp,
          grid);
    }
    for (int i = 1; i <= 5; i++) {
      final y = horizon + math.pow(i / 5.0, 2.2) * (size.height - horizon);
      canvas.drawLine(
          Offset(0, y.toDouble()), Offset(size.width, y.toDouble()), grid);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (pixel) {
      // Honest render: rasterize the scene at the TRUE 64×32 the device sends,
      // then nearest-neighbour upscale so on-screen blocks == device pixels.
      final rec = ui.PictureRecorder();
      final c2 = Canvas(rec);
      _render(c2, Size(_tw.toDouble(), _th.toDouble()));
      final img = rec.endRecording().toImageSync(_tw, _th);
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, _tw.toDouble(), _th.toDouble()),
        Offset.zero & size,
        Paint()..filterQuality = FilterQuality.none,
      );
      img.dispose();
      return;
    }
    _render(canvas, size);
  }

  void _render(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.clipRect(r);
    switch (stage) {
      case 0: // INPUT — raw 4K source, letterboxed to show over-scan
        _scene(canvas, size);
        canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.08),
            Paint()..color = Colors.black);
        canvas.drawRect(
            Rect.fromLTWH(
                0, size.height * 0.92, size.width, size.height * 0.08),
            Paint()..color = Colors.black);
      case 1: // GEOMETRY — reframed: scaled + rotated, tighter crop
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.rotate(-0.09);
        canvas.scale(1.35);
        canvas.translate(-size.width / 2, -size.height / 2);
        _scene(canvas, size);
        canvas.restore();
        canvas.drawRect(
            r.deflate(2),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = _amber);
      case 2: // TONE — posterized / false-colour contour of the luma
        _posterized(canvas, size);
      case 3: // TEXTURE — soft blur + heavy grain (blocky low-freq wash)
        _blurred(canvas, size);
      case 4: // GENERATE — colour-field rings + text glyph composited
        _scene(canvas, size);
        for (int i = 1; i <= 3; i++) {
          canvas.drawCircle(
              Offset(size.width * 0.66, size.height * 0.4),
              size.height * 0.12 * i,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5
                ..color = _green.withValues(alpha: 0.7 - i * 0.12));
        }
        final tp = TextPainter(
            text: TextSpan(
                text: 'Aa',
                style: TextStyle(
                    color: Colors.white,
                    fontFamily: 'DINPro',
                    fontWeight: FontWeight.w700,
                    fontSize: size.height * 0.34)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(size.width * 0.10, size.height * 0.14));
      default: // OUTPUT — final graded, punchy contrast + vignette
        _scene(canvas, size);
        canvas.drawRect(
            r,
            Paint()
              ..blendMode = BlendMode.overlay
              ..color = Colors.black.withValues(alpha: 0.22));
        canvas.drawRect(
            r,
            Paint()
              ..shader = RadialGradient(colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.4)
              ], stops: const [
                0.55,
                1
              ]).createShader(r));
    }
  }

  void _posterized(Canvas canvas, Size size) {
    // Draw the scene into an offscreen picture, then quantize by luma into
    // false-colour horizontal contour bands so it reads as posterize at a glance.
    _scene(canvas, size);
    const bands = [
      Color(0xFF201048),
      Color(0xFF5A2A70),
      Color(0xFFC03E58),
      Color(0xFFE86A4A),
      Color(0xFFF0B050),
      Color(0xFFF0E080),
    ];
    // overlay stepped translucent bands keyed to vertical luma gradient of scene
    for (int i = 0; i < bands.length; i++) {
      final y0 = size.height * i / bands.length;
      final y1 = size.height * (i + 1) / bands.length;
      canvas.drawRect(
          Rect.fromLTRB(0, y0, size.width, y1),
          Paint()
            ..blendMode = BlendMode.hardLight
            ..color = bands[i].withValues(alpha: 0.5));
    }
  }

  void _blurred(Canvas canvas, Size size) {
    _scene(canvas, size);
    // fake blur: overlay big soft translucent blocks sampling the palette
    final blocks = Paint()..blendMode = BlendMode.softLight;
    final cols = [
      const Color(0xFFE86A4A),
      const Color(0xFF7A2E6A),
      const Color(0xFFF0B060)
    ];
    final rnd = math.Random(9);
    for (int i = 0; i < 10; i++) {
      blocks.color = cols[i % 3].withValues(alpha: 0.25);
      final w = size.width * (0.3 + rnd.nextDouble() * 0.4);
      canvas.drawRect(
          Rect.fromLTWH(rnd.nextDouble() * size.width - w / 2,
              rnd.nextDouble() * size.height, w, w * 0.5),
          blocks);
    }
    canvas.drawRect(Offset.zero & size,
        Paint()..color = Colors.white.withValues(alpha: 0.04));
    final g = Paint();
    for (int i = 0; i < 180; i++) {
      g.color = Colors.white.withValues(alpha: rnd.nextDouble() * 0.10);
      canvas.drawRect(
          Rect.fromLTWH(rnd.nextDouble() * size.width,
              rnd.nextDouble() * size.height, 1.2, 1.2),
          g);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.stage != stage;
}

/// The geometry stage: when no thumbnail exists (rotated/warped send), the
/// transform itself is the interface — a manipulable, warped, cropped quad on a
/// neutral reference stage, with every handle present and an honest "no live
/// preview" state. Pixels are a confidence layer we simply don't have here.
class _GeometryStagePainter extends CustomPainter {
  final double rotDeg, cl, cr, ct, cb, sx, sy, px, py, fu, fv;
  final String tool;
  final String? hot; // handle under the cursor / being dragged
  final List<Offset> warp;
  final int warpN, warpRev;
  final List<Offset> cornerWarp;
  final Set<int> freeCorners;
  final Size stageSize; // the 16:9 output-frame rect inside the full canvas
  final Offset stageOffset; // its top-left within the full interactive area
  _GeometryStagePainter({
    required this.rotDeg,
    required this.cl,
    required this.cr,
    required this.ct,
    required this.cb,
    required this.sx,
    required this.sy,
    required this.px,
    required this.py,
    required this.fu,
    required this.fv,
    required this.tool,
    required this.warp,
    required this.warpN,
    required this.warpRev,
    required this.cornerWarp,
    required this.freeCorners,
    required this.stageSize,
    required this.stageOffset,
    this.hot,
  });
  @override
  void paint(Canvas canvas, Size size) {
    // The whole panel is the interactive area (darker margin); the 16:9 output
    // frame is drawn inside it, so handles that leave the frame still show.
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF08080A));
    canvas.save();
    canvas.translate(stageOffset.dx, stageOffset.dy);
    final ss = stageSize;
    final r = Offset.zero & ss;
    canvas.drawRect(r, Paint()..color = const Color(0xFF0A0A0C));
    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (int i = 1; i < 16; i++) {
      canvas.drawLine(Offset(ss.width * i / 16, 0),
          Offset(ss.width * i / 16, ss.height), grid);
    }
    for (int i = 1; i < 9; i++) {
      canvas.drawLine(Offset(0, ss.height * i / 9),
          Offset(ss.width, ss.height * i / 9), grid);
    }
    canvas.drawRect(
        r.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18));

    final g = _computeGeo(ss,
        rotDeg: rotDeg,
        cl: cl,
        cr: cr,
        ct: ct,
        cb: cb,
        sx: sx,
        sy: sy,
        px: px,
        py: py,
        fu: fu,
        fv: fv,
        warp: warp,
        n: warpN,
        cornerWarp: cornerWarp);
    Offset lerp(Offset a, Offset b, double t) =>
        Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
    final warping = tool == 'warp';

    // ghost = full source frame (SCALE handles at its corners)
    canvas.drawPath(
        Path()..addPolygon(g.full, true),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: 0.18));

    // retained content quad
    final qp = Path()..addPolygon(g.quad, true);
    canvas.drawPath(qp, Paint()..color = _amber.withValues(alpha: 0.06));
    canvas.save();
    canvas.clipPath(qp);
    final hatch = Paint()
      ..color = _amber.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (double d = -size.height; d < size.width; d += 10) {
      canvas.drawLine(
          Offset(d, 0), Offset(d + size.height, size.height), hatch);
    }
    canvas.restore();
    canvas.drawPath(
        qp,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _amber);

    // thirds inside quad (skip while warping to keep the mesh legible)
    if (!warping) {
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
    // Affine control points stay visible in every mode (incl. WARP) so the
    // frame transform is still legible/reachable while sculpting the mesh; they
    // dim slightly under WARP so the teal mesh reads as the focus.
    final aa = warping ? 0.5 : 1.0;
    // SCALE handles — outer frame corners. A "freed" corner (keystone) shows
    // as a diamond and drags independently; locked corners scale (circle).
    for (int i = 0; i < 4; i++) {
      final on = hot == 's$i' || hot == 'k$i';
      final free = freeCorners.contains(i);
      final col = (on
              ? Colors.white
              : (free ? const Color(0xFFF0B830) : const Color(0xFF9AA6FF)))
          .withValues(alpha: on ? 1 : aa);
      if (free) {
        final s = on ? 9.0 : 7.0;
        canvas.save();
        canvas.translate(g.full[i].dx, g.full[i].dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: s, height: s),
            Paint()..color = col);
        canvas.restore();
      } else {
        canvas.drawCircle(g.full[i], on ? 8 : 6, Paint()..color = col);
      }
    }
    // CROP handles — bars centred on each content edge, oriented ALONG that
    // edge so they stay parallel to the (rotated / skewed) orange frame.
    for (int i = 0; i < 4; i++) {
      final on = hot == 'e$i';
      final edge = g.quad[(i + 1) % 4] - g.quad[i]; // this crop handle's edge
      final ang = math.atan2(edge.dy, edge.dx);
      final len = on ? 20.0 : 16.0, thick = on ? 7.0 : 6.0;
      canvas.save();
      canvas.translate(g.cropEdges[i].dx, g.cropEdges[i].dy);
      canvas.rotate(ang);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(center: Offset.zero, width: len, height: thick),
              const Radius.circular(2)),
          Paint()
            ..color =
                (on ? Colors.white : _amber).withValues(alpha: on ? 1 : aa));
      canvas.restore();
    }
    // colour-field puck — only under the Field tool (its own concern)
    if (tool == 'field') {
      canvas.drawCircle(
          g.puck,
          hot == 'field' ? 13 : 11,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = hot == 'field' ? Colors.white : _green);
      canvas.drawCircle(g.puck, 3.5, Paint()..color = _green);
    }
    // WARP mesh drawn on top so its teal vertices sit above the affine points
    if (warping) _drawWarpMesh(canvas, g);

    // rotation grip — anchored to the FULL frame top (crop-independent)
    final topFull = lerp(g.full[0], g.full[1], 0.5);
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
    canvas.drawCircle(
        g.grip, hot == 'rot' ? 7 : 5, Paint()..color = const Color(0xFF0A0A0C));
    canvas.restore();
  }

  void _drawWarpMesh(Canvas canvas, _GeoLayout g) {
    final n = warpN;
    final line = Paint()
      ..color = const Color(0xFF66E0C0).withValues(alpha: 0.55)
      ..strokeWidth = 1;
    // mesh grid lines connecting deformed vertices
    for (int j = 0; j < n; j++) {
      for (int i = 0; i < n; i++) {
        final p = g.mesh[j * n + i];
        if (i < n - 1) canvas.drawLine(p, g.mesh[j * n + i + 1], line);
        if (j < n - 1) canvas.drawLine(p, g.mesh[(j + 1) * n + i], line);
      }
    }
    // vertex handles
    for (int k = 0; k < g.mesh.length; k++) {
      final on = hot == 'w$k';
      canvas.drawCircle(g.mesh[k], on ? 6 : 4,
          Paint()..color = on ? Colors.white : const Color(0xFF66E0C0));
    }
  }

  @override
  bool shouldRepaint(covariant _GeometryStagePainter o) =>
      o.rotDeg != rotDeg ||
      o.cl != cl ||
      o.cr != cr ||
      o.ct != ct ||
      o.cb != cb ||
      o.sx != sx ||
      o.sy != sy ||
      o.px != px ||
      o.py != py ||
      o.fu != fu ||
      o.fv != fv ||
      o.hot != hot ||
      o.tool != tool ||
      o.warpRev != warpRev ||
      o.stageSize != stageSize ||
      o.stageOffset != stageOffset;
}

/// Direct-manipulation geometry canvas: hit-tests the handles and drags each to
/// its own parameter. A body-drag depends on the selected tool.
class _GeometryCanvas extends StatefulWidget {
  const _GeometryCanvas();
  @override
  State<_GeometryCanvas> createState() => _GeometryCanvasState();
}

class _GeometryCanvasState extends State<_GeometryCanvas> {
  String?
      _drag; // 's0'..'s3' scale, 'e0'..'e3' crop, 'rot', 'field', 'w0'.. warp, 'body'
  double _px0 = 0, _py0 = 0;
  Offset _p0 = Offset.zero;
  Size _size = Size.zero; // stage (16:9) size
  Offset _stageOffset = Offset.zero; // stage top-left within the full panel
  Offset? _lastHover;

  _GeoLayout _geo(_DeskModel m) => _computeGeo(_size,
      rotDeg: m.rotDeg,
      cl: m.cl,
      cr: m.cr,
      ct: m.ct,
      cb: m.cb,
      sx: m.scaleX,
      sy: m.scaleY,
      px: m.posX,
      py: m.posY,
      fu: m.fieldU,
      fv: m.fieldV,
      warp: m.warp,
      n: m.warpN,
      cornerWarp: m.cornerWarp);

  String? _hitTest(_DeskModel m, Offset p) {
    final g = _geo(m);
    final thresh = math.max(14.0, _size.width * 0.028);
    if ((p - g.grip).distance < thresh) return 'rot';
    // In WARP mode the mesh vertices win first, but the affine handles below are
    // still visible and reachable (fall through).
    if (m.tool == 'warp') {
      for (int k = 0; k < g.mesh.length; k++) {
        if ((p - g.mesh[k]).distance < thresh) return 'w$k';
      }
    }
    if (m.tool == 'field' && (p - g.puck).distance < thresh) return 'field';
    for (int i = 0; i < 4; i++) {
      if ((p - g.cropEdges[i]).distance < thresh) {
        return 'e$i'; // crop (inner edges)
      }
    }
    for (int i = 0; i < 4; i++) {
      if ((p - g.full[i]).distance < thresh) {
        return 's$i'; // scale (outer corners)
      }
    }
    return null;
  }

  void _apply(_DeskModel m, Offset p) {
    if (_drag == null) return;
    final g = _geo(m);
    final d = _drag!;
    if (d == 'rot') {
      final a =
          math.atan2(p.dy - g.center.dy, p.dx - g.center.dx) * 180 / math.pi;
      m.setRot(-(a + 90));
    } else if (d == 'field') {
      final (u, v) = _invMap(p, g);
      m.setField(u: u, v: v);
    } else if (d == 'body') {
      m.setPos(
          x: _px0 + (p.dx - _p0.dx) / _size.width,
          y: _py0 + (p.dy - _p0.dy) / _size.height);
    } else if (d.startsWith('e')) {
      // crop via inner edge handle
      final i = int.parse(d.substring(1));
      final (u, v) = _invMap(p, g);
      switch (i) {
        case 0:
          m.setCrop(t: v);
// top
        case 1:
          m.setCrop(r: 1 - u);
// right
        case 2:
          m.setCrop(b: 1 - v);
// bottom
        case 3:
          m.setCrop(l: u);
// left
      }
    } else if (d.startsWith('s')) {
      // scale via outer frame corner — centre-anchored
      final o = _unrot(p, g); // frame-local pixels from centre
      m.setScale(
          x: 4 * o.dx.abs() / _size.width,
          y: 2 * o.dy.abs() / (_size.height * 0.62));
    } else if (d.startsWith('k')) {
      // keystone — freed corner drags independently: offset from its BASE
      // (undisplaced) corner, in local frame fractions.
      final i = int.parse(d.substring(1));
      final baseGeo = _computeGeo(_size,
          rotDeg: m.rotDeg,
          cl: m.cl,
          cr: m.cr,
          ct: m.ct,
          cb: m.cb,
          sx: m.scaleX,
          sy: m.scaleY,
          px: m.posX,
          py: m.posY,
          fu: m.fieldU,
          fv: m.fieldV); // no cornerWarp
      final off = _unrot(p - baseGeo.full[i] + g.center, g);
      m.setCornerWarp(i, Offset(off.dx / g.fw, off.dy / g.fh));
    } else if (d.startsWith('w')) {
      // warp vertex — store offset from its grid base, in local frame fractions
      final k = int.parse(d.substring(1));
      final n = m.warpN;
      final i = k % n, j = k ~/ n;
      Offset lerp(Offset a, Offset b, double t) =>
          Offset(a.dx + (b.dx - a.dx) * t, a.dy + (b.dy - a.dy) * t);
      Offset bil(List<Offset> q, double u, double v) =>
          lerp(lerp(q[0], q[1], u), lerp(q[3], q[2], u), v);
      final base = bil(g.quad, i / (n - 1), j / (n - 1));
      final off =
          _unrot(p - base + g.center, g); // displacement in local pixels
      m.setWarp(k, Offset(off.dx / g.fw, off.dy / g.fh));
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.watch<_DeskModel>();
    return LayoutBuilder(builder: (context, box) {
      // The interactive/paint area is the WHOLE panel; the 16:9 output frame is
      // centred inside it, so handles that leave the frame stay visible + grabbable.
      final fullW = box.maxWidth, fullH = box.maxHeight;
      double w = fullW, h = w * 9 / 16;
      if (h > fullH) {
        h = fullH;
        w = h * 16 / 9;
      }
      _size = Size(w, h);
      _stageOffset = Offset((fullW - w) / 2, (fullH - h) / 2);
      // pointer → stage-local coords
      Offset s(Offset p) => p - _stageOffset;
      final hot = _drag ?? _hitTest(m, _lastHover ?? const Offset(-1e6, -1e6));
      return SizedBox(
        width: fullW,
        height: fullH,
        child: MouseRegion(
          onHover: (e) => setState(() => _lastHover = s(e.localPosition)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // double-click a scale corner to free it for keystone/shear (and back)
            onDoubleTapDown: (dg) {
              final hit = _hitTest(m, s(dg.localPosition));
              if (hit != null && hit.startsWith('s')) {
                m.toggleFreeCorner(int.parse(hit.substring(1)));
              }
            },
            onDoubleTap: () {},
            onPanStart: (dg) {
              final p = s(dg.localPosition);
              final hit = _hitTest(m, p);
              setState(() {
                if (hit != null &&
                    hit.startsWith('s') &&
                    m.freeCorners.contains(int.parse(hit.substring(1)))) {
                  _drag =
                      'k${hit.substring(1)}'; // freed corner → keystone drag
                } else if (hit != null) {
                  _drag = hit;
                } else if (m.tool == 'move') {
                  _drag = 'body';
                  _p0 = p;
                  _px0 = m.posX;
                  _py0 = m.posY;
                } else {
                  _drag = null;
                }
              });
            },
            onPanUpdate: (dg) => _apply(m, s(dg.localPosition)),
            onPanEnd: (_) => setState(() => _drag = null),
            child: CustomPaint(
              size: Size(fullW, fullH),
              painter: _GeometryStagePainter(
                  rotDeg: m.rotDeg,
                  cl: m.cl,
                  cr: m.cr,
                  ct: m.ct,
                  cb: m.cb,
                  sx: m.scaleX,
                  sy: m.scaleY,
                  px: m.posX,
                  py: m.posY,
                  fu: m.fieldU,
                  fv: m.fieldV,
                  tool: m.tool,
                  warp: m.warp,
                  warpN: m.warpN,
                  warpRev: m.warpRev,
                  cornerWarp: m.cornerWarp,
                  freeCorners: m.freeCorners,
                  stageSize: _size,
                  stageOffset: _stageOffset,
                  hot: hot),
            ),
          ),
        ),
      );
    });
  }
}

/// Live luma histogram with grade curve + posterize thresholds on one axis.
class _HistogramPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = const Color(0xFF0E0E10));
    // histogram bars — a plausible bimodal luma distribution
    final rnd = math.Random(11);
    final n = 96;
    for (int i = 0; i < n; i++) {
      final x = i / n;
      final env = math.exp(-math.pow((x - 0.32) * 3.4, 2)) * 0.9 +
          math.exp(-math.pow((x - 0.78) * 4.2, 2)) * 0.7;
      final h = (env + rnd.nextDouble() * 0.06) * size.height * 0.92;
      final bx = x * size.width;
      canvas.drawRect(Rect.fromLTWH(bx, size.height - h, size.width / n - 1, h),
          Paint()..color = _dim.withValues(alpha: 0.55));
    }
    // grade transfer curve (S-curve) over the same axis
    final curve = Path();
    for (int i = 0; i <= 64; i++) {
      final x = i / 64.0;
      // gentle S
      final y = 0.5 - 0.5 * math.cos(math.pi * _smooth(x, 0.55));
      final px = x * size.width;
      final py = size.height - y * size.height;
      i == 0 ? curve.moveTo(px, py) : curve.lineTo(px, py);
    }
    canvas.drawPath(
        curve,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _amber);
    // posterize thresholds as vertical ticks on the SAME axis as the strip below
    for (final x in _posterTh) {
      canvas.drawLine(
          Offset(x * size.width, 0),
          Offset(x * size.width, size.height),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.22)
            ..strokeWidth = 1);
    }
  }

  double _smooth(double x, double k) =>
      math.pow(x, 1 / (1.6)) * (1 - k) + x * k;
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Posterize band strip (16 bands, false-colour) pinned to the luma axis.
class _BandStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final th = [0.0, ..._posterTh, 1.0];
    const colors = [
      Color(0xFF101018),
      Color(0xFF2A2050),
      Color(0xFF5A2A70),
      Color(0xFF8A2E6A),
      Color(0xFFC03E58),
      Color(0xFFE86A4A),
      Color(0xFFF0A050),
      Color(0xFFF0D060),
      Color(0xFFE0E080),
      Color(0xFFB8E0A0),
      Color(0xFF80D0C0),
      Color(0xFFC0E0F0),
    ];
    for (int i = 0; i < th.length - 1; i++) {
      final x0 = th[i] * size.width, x1 = th[i + 1] * size.width;
      canvas.drawRect(Rect.fromLTRB(x0, 0, x1, size.height),
          Paint()..color = colors[i % colors.length]);
    }
    // dividers with nubs
    final dp = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    for (int i = 1; i < th.length - 1; i++) {
      final x = th[i] * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), dp);
      canvas.drawCircle(Offset(x, size.height - 4), 2.5, dp);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _Sparkline extends StatelessWidget {
  final int seed;
  final Color color;
  const _Sparkline({required this.seed, required this.color});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SparkPainter(seed, color));
}

class _SparkPainter extends CustomPainter {
  final int seed;
  final Color color;
  _SparkPainter(this.seed, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final p = Path();
    final n = 40;
    for (int i = 0; i < n; i++) {
      final x = i / (n - 1) * size.width;
      final y = size.height * (0.5 + (rnd.nextDouble() - 0.5) * 0.5);
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = color.withValues(alpha: 0.8));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ═════════════════════════════════════════════════════════════════════════════
// CONCEPT: "Capture Desk" — the SAME language on the Return surface.
//
// Return has a different toolset (capture/ADC, not creative), so the language
// adapts: the canvas shows the CAPTURED frame, the direct-manipulation overlay
// is the DE window (detected active area) + sync markers instead of crop/field,
// and the right instrument is a signal SCOPE (waveform + vectorscope) over the
// ADC + sync controls. Consistent shell, surface-specific instruments.
// ═════════════════════════════════════════════════════════════════════════════
class CaptureDesk extends StatelessWidget {
  const CaptureDesk({super.key});
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Container(
      color: _bg,
      padding: EdgeInsets.all(t.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _CaptureStatus(),
        SizedBox(height: t.md),
        Expanded(
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: t.u * 16, child: const _CaptureChain()),
          SizedBox(width: t.md),
          Expanded(flex: 5, child: const _CaptureCanvas()),
          SizedBox(width: t.md),
          Expanded(flex: 3, child: const _CaptureInstrument()),
        ])),
      ]),
    );
  }
}

class _CaptureStatus extends StatelessWidget {
  const _CaptureStatus();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    Widget stat(String k, String v, {Color c = _ink}) =>
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$k ', style: t.textCaption.copyWith(color: _dim)),
          Text(v, style: t.textValue.copyWith(color: c, fontSize: t.u * 1.2)),
        ]);
    return Row(children: [
      Text('SCION',
          style: t.textTitle
              .copyWith(fontWeight: FontWeight.w700, letterSpacing: 2)),
      SizedBox(width: t.xs),
      Text('RETURN',
          style: t.textTitle
              .copyWith(color: const Color(0xFF5AB0E0), letterSpacing: 2)),
      SizedBox(width: t.lg),
      Container(
        padding: EdgeInsets.symmetric(horizontal: t.sm, vertical: t.xs * 0.6),
        decoration: BoxDecoration(
            color: _green.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(3)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: t.xs,
              height: t.xs,
              decoration:
                  const BoxDecoration(color: _green, shape: BoxShape.circle)),
          SizedBox(width: t.xs),
          Text('SYNC LOCKED',
              style: t.textCaption.copyWith(color: _green, letterSpacing: 1.5)),
        ]),
      ),
      SizedBox(width: t.lg),
      stat('CAPTURE', '1920×1080p59.94'),
      SizedBox(width: t.lg),
      stat('DE', '1920×1080 @ 192,41', c: const Color(0xFF5AB0E0)),
      const Spacer(),
      SizedBox(
          width: t.u * 10,
          height: t.u * 2.2,
          child: const _Sparkline(seed: 4, color: Color(0xFF5AB0E0))),
      SizedBox(width: t.sm),
      stat('AGC', '1.53×'),
    ]);
  }
}

class _CaptureChain extends StatelessWidget {
  const _CaptureChain();
  static const stages = [
    ('SIGNAL IN', 'ADV7842', 0, false),
    ('SYNC · DE', 'lock · window', 1, true),
    ('ADC', 'AA · AGC', 3, false),
    ('COLOR', 'space · depth', 5, false),
    ('FORMAT', 'YUV 4:2:2 10b', 4, false),
  ];
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('CAPTURE CHAIN',
          style: t.textCaption.copyWith(letterSpacing: 1.5, color: _dim)),
      SizedBox(height: t.sm),
      Expanded(
          child: Column(children: [
        for (final s in stages)
          Expanded(
              child: Padding(
            padding: EdgeInsets.only(bottom: t.xs),
            child:
                _ChainNode(label: s.$1, sub: s.$2, stage: s.$3, active: s.$4),
          )),
      ])),
    ]);
  }
}

class _CaptureCanvas extends StatelessWidget {
  const _CaptureCanvas();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('CAPTURED SIGNAL',
            style: t.textCaption.copyWith(letterSpacing: 1.5, color: _dim)),
        const Spacer(),
        Text('drag DE edges to set active area',
            style: t.textCaption.copyWith(color: _dim)),
      ]),
      SizedBox(height: t.sm),
      Expanded(
          child: NeumorphicInset(
        baseColor: const Color(0xFF0C0C0E),
        padding: EdgeInsets.all(t.xs),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _FramePainter(stage: 0, pixel: true)),
              CustomPaint(painter: _DeWindowPainter()),
            ]),
          ),
        ),
      )),
    ]);
  }
}

/// DE-window (active area) overlay — cyan, edge-centred handles + sync ticks.
class _DeWindowPainter extends CustomPainter {
  static const _cyan = Color(0xFF5AB0E0);
  @override
  void paint(Canvas canvas, Size size) {
    final de = Rect.fromLTRB(size.width * 0.05, size.height * 0.06,
        size.width * 0.95, size.height * 0.95);
    // dim outside the detected active area
    final dim = Path()
      ..addRect(Offset.zero & size)
      ..addRect(de)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = Colors.black.withValues(alpha: 0.5));
    canvas.drawRect(
        de,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _cyan);
    // edge-centred handles (DE is set per-edge, not per-corner)
    final hp = Paint()..color = _cyan;
    for (final c in [
      de.centerLeft,
      de.centerRight,
      de.topCenter,
      de.bottomCenter
    ]) {
      canvas.drawRect(Rect.fromCenter(center: c, width: 9, height: 9), hp);
    }
    // H/V sync position ticks along top + left rulers
    final tick = Paint()
      ..color = _cyan.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (int i = 0; i <= 16; i++) {
      final x = de.left + de.width * i / 16;
      canvas.drawLine(
          Offset(x, de.top), Offset(x, de.top + (i % 4 == 0 ? 7 : 4)), tick);
    }
    // label
    final tp = TextPainter(
        text: TextSpan(
            text: '1920 × 1080  active',
            style: TextStyle(
                color: _cyan,
                fontFamily: 'DINPro',
                fontSize: size.height * 0.035)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(de.left + 6, de.top + 5));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CaptureInstrument extends StatelessWidget {
  const _CaptureInstrument();
  @override
  Widget build(BuildContext context) {
    final t = GridProvider.of(context);
    return LabeledCard(
      title: 'Signal',
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const LabSectionHeader('Scope'),
            SizedBox(height: t.xs),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  flex: 3,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                            height: t.u * 6.5,
                            child: CustomPaint(
                                painter: _WaveformPainter(),
                                size: Size.infinite)),
                        SizedBox(height: t.xs * 0.5),
                        Text('WAVEFORM · luma',
                            style: t.textCaption
                                .copyWith(color: _dim, fontSize: t.u * 0.8)),
                      ])),
              SizedBox(width: t.sm),
              Expanded(
                  flex: 2,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                            aspectRatio: 1,
                            child: CustomPaint(painter: _VectorscopePainter())),
                        SizedBox(height: t.xs * 0.5),
                        Text('VECTOR',
                            style: t.textCaption
                                .copyWith(color: _dim, fontSize: t.u * 0.8)),
                      ])),
            ]),
            SizedBox(height: t.md),
            // DE window — the active-area numerics that pair with the on-image
            // overlay. Per-edge, because that's how DE detection is set.
            const LabSectionHeader('DE Window · active area'),
            SizedBox(height: t.xs),
            Panel(
                child: Column(children: [
              Row(children: [
                Expanded(child: _deField(t, 'LEFT', '192')),
                Expanded(child: _deField(t, 'RIGHT', '2112')),
                Expanded(child: _deField(t, 'WIDTH', '1920', accent: true)),
              ]),
              SizedBox(height: t.sm),
              Row(children: [
                Expanded(child: _deField(t, 'TOP', '41')),
                Expanded(child: _deField(t, 'BOTTOM', '1121')),
                Expanded(child: _deField(t, 'HEIGHT', '1080', accent: true)),
              ]),
            ])),
            SizedBox(height: t.md),
            const LabSectionHeader('Sync Adjust'),
            SizedBox(height: t.xs),
            KnobPanel(
                null,
                const [
                  ('H Phase', 0.5),
                  ('V Phase', 0.5),
                  ('LLC Phase', 0.3),
                  ('Coast', 0.4)
                ],
                bipolar: true,
                knobSize: t.knobSm),
          ]),
    );
  }

  Widget _deField(GridTokens t, String label, String value,
          {bool accent = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: t.textCaption.copyWith(
                  color: _dim, fontSize: t.u * 0.8, letterSpacing: 1)),
          SizedBox(height: t.xs * 0.4),
          Text(value,
              style: t.textValue.copyWith(
                  color: accent ? const Color(0xFF5AB0E0) : _ink,
                  fontSize: t.u * 1.7,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

/// Video waveform monitor — luma trace across the raster.
class _WaveformPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()..color = const Color(0xFF0A0E0A));
    // IRE graticule
    final g = Paint()
      ..color = const Color(0xFF2A3A2A)
      ..strokeWidth = 0.75;
    for (int i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), g);
    }
    // trace — green phosphor
    final rnd = math.Random(21);
    final trace = Paint()
      ..color = _green.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (int x = 0; x < size.width; x += 2) {
      final fx = x / size.width;
      final base = 0.5 - 0.5 * math.cos(math.pi * fx * 2) * 0.6;
      for (int s = 0; s < 3; s++) {
        final y = (base + (rnd.nextDouble() - 0.5) * 0.5).clamp(0.03, 0.97) *
            size.height;
        canvas.drawPoints(
            ui.PointMode.points, [Offset(x.toDouble(), y)], trace);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Vectorscope — chroma distribution with colour targets.
class _VectorscopePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF0A0E0A));
    canvas.drawCircle(
        c,
        r - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.75
          ..color = const Color(0xFF2A3A2A));
    canvas.drawCircle(
        c,
        r * 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = const Color(0xFF2A3A2A));
    // colour target boxes (R,Yl,G,Cy,B,Mg)
    const targets = [
      Color(0xFFE05A5A),
      Color(0xFFE0D050),
      Color(0xFF5AD070),
      Color(0xFF50C0D0),
      Color(0xFF6060E0),
      Color(0xFFD060C0)
    ];
    for (int i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * r * 0.72;
      canvas.drawRect(
          Rect.fromCenter(center: p, width: 4, height: 4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.75
            ..color = targets[i].withValues(alpha: 0.7));
    }
    // signal blob
    final rnd = math.Random(5);
    final dot = Paint()..color = _green.withValues(alpha: 0.4);
    for (int i = 0; i < 220; i++) {
      final a = rnd.nextDouble() * 2 * math.pi;
      final rr = rnd.nextDouble() * r * 0.55 * (0.3 + rnd.nextDouble());
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * rr, 0.8, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
