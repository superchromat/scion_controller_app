import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Charts for the Setup page's calibration card (calibration_section.dart),
/// drawn from a self-calibration run's samples and fit report.

/// One self-cal sample, in normalised full-range YCbCr (Cb/Cr about 0).
class CalSample {
  final bool validation;
  final List<double> src; // Y Cb Cr shown
  final List<double> meas; // Y Cb Cr measured at the 3D LUT's input (raw loop)
  const CalSample(this.validation, this.src, this.meas);
}

/// The fit report: chosen model (1 linear, 2 quadratic) and rms error in
/// 12-bit codes per [model][set: 0 train, 1 validation][Y, Cb, Cr].
class CalFitReport {
  final int chosen;
  final List<List<List<double>>> rms;
  const CalFitReport(this.chosen, this.rms);
}

// ---- painters --------------------------------------------------------------------

const _gridColor = Color(0xFF34343A);
const _axisColor = Color(0xFF53525A);
const _chanColors = [Color(0xFFE8E8EC), Color(0xFF5B8DEF), Color(0xFFE46F6F)];

void _label(Canvas c, String s, Offset at, TextStyle style, {bool right = false, bool center = false}) {
  final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  var o = at;
  if (right) o = o.translate(-tp.width, 0);
  if (center) o = o.translate(-tp.width / 2, 0);
  tp.paint(c, o.translate(0, -tp.height / 2));
}

/// Grouped bars: for Y, Cb, Cr, the linear and quadratic models' training
/// (faint) and validation (solid) rms. The chosen model is outlined.
class CalFitBarsPainter extends CustomPainter {
  final CalFitReport r;
  final TextStyle text;
  CalFitBarsPainter(this.r, this.text);

  @override
  void paint(Canvas c, Size s) {
    final left = 26.0, bottom = 18.0;
    final w = s.width - left, h = s.height - bottom;
    var top = 2.0;
    for (final m in r.rms) {
      for (final set in m) {
        for (final v in set) {
          if (v.isFinite) top = math.max(top, v);
        }
      }
    }
    final ymax = (top * 1.15).ceilToDouble().clamp(4.0, 64.0);
    double y(double v) => h - (v / ymax) * h;
    final grid = Paint()..color = _gridColor;
    final step = ymax <= 8 ? 1.0 : ymax <= 20 ? 2.0 : 5.0;
    for (var v = 0.0; v <= ymax + 1e-6; v += step) {
      c.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), grid);
      _label(c, v.toStringAsFixed(0), Offset(left - 4, y(v)), text, right: true);
    }
    const names = ['Y', 'Cb', 'Cr'];
    final group = w / 3;
    final bw = group / 6;
    for (var ch = 0; ch < 3; ch++) {
      final gx = left + ch * group + group / 6;
      var k = 0;
      for (var m = 0; m < 2; m++) {
        for (var set = 0; set < 2; set++) {
          final v = r.rms[m][set][ch];
          final x = gx + k * bw;
          final rect = Rect.fromLTRB(x + 1, y(v.isFinite ? v : 0), x + bw - 1, h);
          final base = m == 0 ? const Color(0xFF8C8C96) : const Color(0xFF3BDEFF);
          c.drawRect(rect, Paint()..color = set == 0 ? base.withValues(alpha: 0.35) : base);
          if (m == r.chosen - 1 && set == 1) {
            c.drawRect(rect.inflate(1.5), Paint()
              ..style = PaintingStyle.stroke
              ..color = Colors.white
              ..strokeWidth = 1);
          }
          k++;
        }
      }
      _label(c, names[ch], Offset(gx + 2 * bw, h + bottom / 2 + 2), text, center: true);
    }
    _label(c, 'linear', Offset(s.width, 6), text.copyWith(color: const Color(0xFF8C8C96)), right: true);
    _label(c, 'quadratic', Offset(s.width, 20), text.copyWith(color: const Color(0xFF3BDEFF)), right: true);
  }

  @override
  bool shouldRepaint(CalFitBarsPainter o) => o.r != r;
}

Color _ycbcrToColor(List<double> s) {
  final y = s[0], cb = s[1], cr = s[2];
  final r = y + 1.5748 * cr, g = y - 0.187324 * cb - 0.468124 * cr, b = y + 1.8556 * cb;
  int q(double v) => (v.clamp(0.0, 1.0) * 255).round();
  return Color.fromARGB(255, q(r), q(g), q(b));
}

/// Cb/Cr plane: each sent colour (ring, in its own colour) joined to what came
/// back through the loop before correction (dot), the difference magnified. Shows the loop's raw
/// saturation and hue error, the thing the 3D LUT undoes.
class CalVectorscopePainter extends CustomPainter {
  final List<CalSample> samples;
  final TextStyle text;
  final double gain;
  CalVectorscopePainter(this.samples, this.text, {this.gain = 5});

  @override
  void paint(Canvas c, Size s) {
    final r = math.min(s.width, s.height) / 2 - 4;
    final o = Offset(s.width / 2, s.height / 2);
    Offset p(double cb, double cr) => o + Offset(cb / 0.55 * r, -cr / 0.55 * r);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..color = _gridColor;
    c.drawCircle(o, 0.5 / 0.55 * r, grid);
    c.drawCircle(o, 0.25 / 0.55 * r, grid);
    c.drawLine(o.translate(-r, 0), o.translate(r, 0), Paint()..color = _axisColor);
    c.drawLine(o.translate(0, -r), o.translate(0, r), Paint()..color = _axisColor);
    _label(c, 'Cb', o.translate(r - 2, -8), text, right: true);
    _label(c, 'Cr', o.translate(4, -r + 6), text);
    for (final sm in samples) {
      // The loop's raw error is a few percent at most: drawn at [gain] times so
      // its direction and size can be seen.
      final a = p(sm.src[1], sm.src[2]);
      final b = p(sm.src[1] + gain * (sm.meas[1] - sm.src[1]), sm.src[2] + gain * (sm.meas[2] - sm.src[2]));
      final col = _ycbcrToColor(sm.src);
      c.drawLine(a, b, Paint()
        ..color = col.withValues(alpha: 0.6)
        ..strokeWidth = 1);
      c.drawCircle(a, 2.6, Paint()
        ..style = PaintingStyle.stroke
        ..color = col
        ..strokeWidth = 1);
      c.drawCircle(b, 1.4, Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
  }

  @override
  bool shouldRepaint(CalVectorscopePainter o) => !identical(o.samples, samples);
}

/// What the correction leaves: per sample, measured minus the fitted forward
/// model of what was sent, in 12-bit codes, against the sent luma. Validation
/// samples (never used by the fit) solid, training faint.
class CalResidualPainter extends CustomPainter {
  final List<CalSample> samples;
  final List<List<double>>? model;
  final TextStyle text;
  CalResidualPainter(this.samples, this.model, this.text);

  static List<double> _terms(List<double> s) {
    final y = s[0], cb = s[1], cr = s[2];
    return [y, cb, cr, cb * cb, cr * cr, y * y, cb * cr, y * cb, y * cr, 1];
  }

  @override
  void paint(Canvas c, Size s) {
    final left = 26.0, bottom = 16.0;
    final w = s.width - left, h = s.height - bottom;
    const lim = 16.0; // codes, either side
    double y(double v) => h / 2 - (v.clamp(-lim, lim) / lim) * (h / 2);
    double x(double luma) => left + luma.clamp(0.0, 1.0) * w;
    final grid = Paint()..color = _gridColor;
    for (final v in const [-16.0, -8.0, 0.0, 8.0, 16.0]) {
      c.drawLine(Offset(left, y(v)), Offset(s.width, y(v)), v == 0 ? (Paint()..color = _axisColor) : grid);
      _label(c, v.toStringAsFixed(0), Offset(left - 4, y(v)), text, right: true);
    }
    _label(c, 'black', Offset(left, h + bottom / 2 + 2), text);
    _label(c, 'white', Offset(s.width, h + bottom / 2 + 2), text, right: true);
    final m = model;
    if (m == null) return;
    for (final sm in samples) {
      final t = _terms(sm.src);
      for (var k = 0; k < 3; k++) {
        var f = 0.0;
        for (var j = 0; j < 10; j++) {
          f += m[k][j] * t[j];
        }
        final e = (sm.meas[k] - f) * 4095;
        final col = _chanColors[k].withValues(alpha: sm.validation ? 0.95 : 0.3);
        c.drawCircle(Offset(x(sm.src[0]) + (k - 1) * 1.6, y(e)), sm.validation ? 1.7 : 1.2, Paint()..color = col);
      }
    }
  }

  @override
  bool shouldRepaint(CalResidualPainter o) => !identical(o.samples, samples) || !identical(o.model, model);
}
