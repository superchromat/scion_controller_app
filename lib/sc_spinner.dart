import 'package:flutter/material.dart';

/// The SC wordmark (from superchromat.com/sc.svg) as a self-drawing spinner.
///
/// It traces in a deliberate order: starting at the tip of the C (top-right),
/// right-to-left across the top of the C then the S, down the S's left side and
/// left-to-right across its middle bar, then — at the branch where the S and C
/// meet — the bottom of the S and the bottom of the C are drawn simultaneously.
class ScSpinner extends StatefulWidget {
  final double width;
  final Color color;
  final double strokeWidth;
  final Duration period;

  const ScSpinner({
    super.key,
    this.width = 64,
    this.color = const Color(0xFFF0B830),
    this.strokeWidth = 4,
    this.period = const Duration(milliseconds: 2200),
  });

  @override
  State<ScSpinner> createState() => _ScSpinnerState();
}

class _ScSpinnerState extends State<ScSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.width * ScMarkPainter.viewH / ScMarkPainter.viewW,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          painter: ScMarkPainter(
            progress: _c.value,
            color: widget.color,
            strokeWidth: widget.strokeWidth,
          ),
        ),
      ),
    );
  }
}

/// Paints the SC mark drawn up to [progress] (0..1 = one draw+fade cycle).
class ScMarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  const ScMarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  // Panel viewBox. The mark (authored at x:5..85, y:5..45) is drawn with a
  // +5,+5 offset so it's centred with even padding inside the plate.
  static const double viewW = 100;
  static const double viewH = 60;

  // Fraction of the draw during which the main trace (tip → branch) is drawn;
  // the remainder draws the two branches simultaneously.
  static const double _mainT = 0.66;
  // Fraction of the cycle spent drawing (the tail fades over the rest).
  static const double _drawEnd = 0.80;

  static final Path _main = _buildMain();
  static final Path _branchS = _buildBranchS();
  static final Path _branchC = _buildBranchC();
  static final Path _full = Path()
    ..addPath(_main, Offset.zero)
    ..addPath(_branchS, Offset.zero)
    ..addPath(_branchC, Offset.zero);

  // Widths / blurs in SVG units, so everything scales with the mark.
  static const double _grooveW = 8.5;
  static const double _amberW = 4.0;

  static void _a(Path p, double x, double y, bool clockwise) =>
      p.arcToPoint(Offset(x, y),
          radius: const Radius.circular(10), clockwise: clockwise);

  // Main trace: tip of C (top-right) → across the top → down the S → middle bar
  // → branch point (45,35). Reversed arcs vs. the source path flip clockwise.
  static Path _buildMain() {
    final p = Path()..moveTo(85, 15);
    _a(p, 75, 5, false); // C top-right corner
    p.lineTo(55, 5); // top of C
    _a(p, 45, 15, false); // centre notch (right)
    _a(p, 35, 5, false); // centre notch (left)
    p.lineTo(15, 5); // top of S
    _a(p, 5, 15, false); // S top-left corner
    _a(p, 15, 25, false); // S left curve, down
    p.lineTo(35, 25); // S middle bar
    _a(p, 45, 35, true); // down to the branch
    return p;
  }

  // Bottom of the S, from the branch.
  static Path _buildBranchS() {
    final p = Path()..moveTo(45, 35);
    _a(p, 35, 45, true);
    p.lineTo(15, 45);
    _a(p, 5, 35, true);
    return p;
  }

  // Bottom of the C, from the branch.
  static Path _buildBranchC() {
    final p = Path()..moveTo(45, 35);
    _a(p, 55, 45, false);
    p.lineTo(75, 45);
    _a(p, 85, 35, false);
    return p;
  }

  static Path _extract(Path src, double frac) {
    if (frac <= 0) return Path();
    if (frac >= 1) return src;
    final out = Path();
    for (final m in src.computeMetrics()) {
      out.addPath(m.extractPath(0, m.length * frac), Offset.zero);
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / viewW;
    // draw-on for the first _drawEnd of the cycle, then fade the finished mark.
    double drawT;
    double opacity;
    if (progress <= _drawEnd) {
      drawT = progress / _drawEnd;
      opacity = 1.0;
    } else {
      drawT = 1.0;
      opacity = 1.0 - (progress - _drawEnd) / (1 - _drawEnd);
    }

    canvas.save();
    canvas.scale(s);
    _paintPanel(canvas);
    canvas.translate(5, 5); // centre the mark within the padded plate
    _paintGroove(canvas);
    _paintAmber(canvas, drawT, opacity.clamp(0.0, 1.0));
    canvas.restore();
  }

  // Grey neumorphic plate that hosts the recessed SC slot.
  void _paintPanel(Canvas canvas) {
    final rect = Rect.fromLTWH(0, 0, viewW, viewH);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(12));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.6),
          radius: 1.2,
          colors: [Color(0xFF48484B), Color(0xFF3A3A3D), Color(0xFF313134)],
          stops: [0.0, 0.6, 1.0],
        ).createShader(rect),
    );
    // top highlight + bottom shadow so the plate reads as raised.
    canvas.drawRRect(
      rrect.deflate(0.6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x22000000)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(rect),
    );
  }

  // The SC slot cut into the plate: a dark recessed channel with a top-left
  // inner shadow and a bottom-right lip highlight (pressed-in / inset).
  void _paintGroove(Canvas canvas) {
    Paint stroke(Color c, double w, {double blur = 0}) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur) : null;

    // recessed floor
    canvas.drawPath(_full, stroke(const Color(0xFF2C2C30), _grooveW));
    // top-left inner shadow
    canvas.save();
    canvas.translate(-0.7, -0.7);
    canvas.drawPath(_full,
        stroke(Colors.black.withValues(alpha: 0.55), _grooveW, blur: 1.1));
    canvas.restore();
    // bottom-right lip highlight
    canvas.save();
    canvas.translate(0.8, 0.8);
    canvas.drawPath(
        _full,
        stroke(const Color(0xFF5C5C61).withValues(alpha: 0.65), _grooveW,
            blur: 1.1));
    canvas.restore();
    // re-darken the channel bottom (bevels bleed inward)
    canvas.drawPath(_full, stroke(const Color(0xFF242427), _grooveW - 3.2));
  }

  // The amber, traced in order, reading as light glowing up through the slot.
  void _paintAmber(Canvas canvas, double drawT, double opacity) {
    final bool fading = opacity < 1.0;
    if (fading) {
      canvas.saveLayer(
          null, Paint()..color = Color.fromRGBO(255, 255, 255, opacity));
    }

    final glow = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _amberW + 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.4);
    final core = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _amberW
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    void drawSeg(Path p, double frac) {
      final seg = _extract(p, frac);
      canvas.drawPath(seg, glow);
      canvas.drawPath(seg, core);
    }

    final mainFrac = (drawT / _mainT).clamp(0.0, 1.0);
    drawSeg(_main, mainFrac);
    if (drawT > _mainT) {
      final branchFrac = ((drawT - _mainT) / (1 - _mainT)).clamp(0.0, 1.0);
      drawSeg(_branchS, branchFrac);
      drawSeg(_branchC, branchFrac);
    }

    if (fading) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ScMarkPainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.strokeWidth != strokeWidth;
}
