// lut_io.dart — .cube 3D LUT import/export for the Color page.
//
// IMPORT: parse a Resolve-style .cube (any grid size), trilinearly resample
// to the hardware's 17x17x17 grid, pack as the firmware's NOR blob
// ("LUT3" + state + name + 17^3 x RGB u16 little-endian, R fastest,
// 12-bit 0..4080), upload via the nor transport and /send/1/color/lut3d/apply.
//
// EXPORT: compose the device's colour pipeline into a single 33^3 .cube by
// evaluating the same maths the firmware runs, in hardware order:
//   RGB -> YCbCr (BT.709) -> picture-knob CSC (contrast/hue/sat/brightness,
//   vendor mdindst.c formula) -> RGB -> per-channel 1D LUTs (monotone-cubic
//   through the 16 control points, exact port of build_lut) -> grade 3D
//   (exact port of grade_write_banks) -> out.
// Domain: normalized full-range RGB in/out. Neutral knobs = exact identity
// through the CSC leg by construction (forward matrix = inverse of the
// same base matrix the knob deltas modify).

import 'dart:math' as math;
import 'dart:typed_data';

// ------------------------------------------------------------- .cube IO ----

class CubeLut {
  final int n;
  final Float64List data; // n^3 * 3, R fastest, [0,1]
  final String title;
  CubeLut(this.n, this.data, [this.title = '']);

  /// Trilinear sample at r,g,b in [0,1].
  (double, double, double) sample(double r, double g, double b) {
    double cl(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    final fr = cl(r) * (n - 1), fg = cl(g) * (n - 1), fb = cl(b) * (n - 1);
    final r0 = fr.floor().clamp(0, n - 2),
        g0 = fg.floor().clamp(0, n - 2),
        b0 = fb.floor().clamp(0, n - 2);
    final tr = fr - r0, tg = fg - g0, tb = fb - b0;
    double at(int ri, int gi, int bi, int c) =>
        data[((bi * n + gi) * n + ri) * 3 + c];
    final out = List<double>.filled(3, 0);
    for (var c = 0; c < 3; c++) {
      final c00 = at(r0, g0, b0, c) * (1 - tr) + at(r0 + 1, g0, b0, c) * tr;
      final c10 =
          at(r0, g0 + 1, b0, c) * (1 - tr) + at(r0 + 1, g0 + 1, b0, c) * tr;
      final c01 =
          at(r0, g0, b0 + 1, c) * (1 - tr) + at(r0 + 1, g0, b0 + 1, c) * tr;
      final c11 = at(r0, g0 + 1, b0 + 1, c) * (1 - tr) +
          at(r0 + 1, g0 + 1, b0 + 1, c) * tr;
      final c0 = c00 * (1 - tg) + c10 * tg;
      final c1 = c01 * (1 - tg) + c11 * tg;
      out[c] = c0 * (1 - tb) + c1 * tb;
    }
    return (out[0], out[1], out[2]);
  }

  static CubeLut parse(String text) {
    var n = 0;
    var title = '';
    final vals = <double>[];
    var dmin = 0.0, dmax = 1.0;
    for (final raw in text.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final up = line.toUpperCase();
      if (up.startsWith('TITLE')) {
        final m = RegExp(r'"(.*)"').firstMatch(line);
        title = m?.group(1) ?? '';
      } else if (up.startsWith('LUT_3D_SIZE')) {
        n = int.parse(line.split(RegExp(r'\s+')).last);
      } else if (up.startsWith('LUT_1D_SIZE')) {
        throw const FormatException('1D .cube files are not supported');
      } else if (up.startsWith('DOMAIN_MIN')) {
        dmin = double.parse(line.split(RegExp(r'\s+'))[1]);
      } else if (up.startsWith('DOMAIN_MAX')) {
        dmax = double.parse(line.split(RegExp(r'\s+'))[1]);
      } else if (RegExp(r'^[-\d.]').hasMatch(line)) {
        for (final t in line.split(RegExp(r'\s+'))) {
          vals.add(double.parse(t));
        }
      }
    }
    if (n < 2 || vals.length != n * n * n * 3) {
      throw FormatException(
          'bad .cube: size $n, ${vals.length} values (want ${n * n * n * 3})');
    }
    final scale = (dmax - dmin) == 0 ? 1.0 : 1.0 / (dmax - dmin);
    final d = Float64List(vals.length);
    for (var i = 0; i < vals.length; i++) {
      d[i] = (vals[i] - dmin) * scale;
    }
    return CubeLut(n, d, title);
  }

  String format() {
    final sb = StringBuffer();
    sb.writeln('# Exported by SCION Controller');
    if (title.isNotEmpty) sb.writeln('TITLE "$title"');
    sb.writeln('LUT_3D_SIZE $n');
    for (var i = 0; i < n * n * n; i++) {
      sb.writeln('${data[i * 3].toStringAsFixed(6)} '
          '${data[i * 3 + 1].toStringAsFixed(6)} '
          '${data[i * 3 + 2].toStringAsFixed(6)}');
    }
    return sb.toString();
  }
}

/// Resample any CubeLut to the firmware's 17^3 NOR blob.
Uint8List packLut3dBlob(CubeLut lut, String name) {
  const n = 17;
  final out = BytesBuilder();
  final hdr = Uint8List(40);
  hdr.setRange(0, 4, 'LUT3'.codeUnits);
  ByteData.sublistView(hdr).setUint32(4, 0xFFFFFFFF, Endian.little); // active
  final nb = name.codeUnits.take(31).toList();
  hdr.setRange(8, 8 + nb.length, nb);
  out.add(hdr);
  final body = ByteData(n * n * n * 3 * 2);
  var o = 0;
  for (var bi = 0; bi < n; bi++) {
    for (var gi = 0; gi < n; gi++) {
      for (var ri = 0; ri < n; ri++) {
        final (r, g, b) = lut.sample(ri / (n - 1), gi / (n - 1), bi / (n - 1));
        for (final v in [r, g, b]) {
          final q = (v.clamp(0.0, 1.0) * 4095.0).round();
          body.setUint16(o, q, Endian.little);
          o += 2;
        }
      }
    }
  }
  out.add(body.buffer.asUint8List());
  return out.toBytes();
}

// -------------------------------------------------- firmware maths ports ----

/// Monotone-cubic 1D curve through control points — exact port of the
/// firmware's build_lut() (osc_handlers.c), including the Fritsch-Carlson
/// tangent limiting.
class Lut1D {
  final List<double> xs, ys, tangents;
  Lut1D._(this.xs, this.ys, this.tangents);

  factory Lut1D.fromPoints(List<(double, double)> raw) {
    var pts = [
      for (final (x, y) in raw)
        if (x >= 0 && y >= 0) (x, y)
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    if (pts.length < 2) pts = [(0.0, 0.0), (1.0, 1.0)];
    final count = pts.length;
    final xs = [for (final p in pts) p.$1];
    final ys = [for (final p in pts) p.$2];
    final slope = List<double>.filled(count - 1, 0);
    for (var i = 0; i < count - 1; i++) {
      var dx = xs[i + 1] - xs[i];
      if (dx == 0) dx = 1e-6;
      slope[i] = (ys[i + 1] - ys[i]) / dx;
    }
    final tan = List<double>.filled(count, 0);
    tan[0] = slope[0];
    for (var i = 1; i < count - 1; i++) {
      final mPrev = slope[i - 1], mNext = slope[i];
      tan[i] = (mPrev * mNext <= 0) ? 0 : (mPrev + mNext) / 2;
    }
    tan[count - 1] = slope[count - 2];
    for (var i = 0; i < count - 1; i++) {
      if (slope[i] == 0) {
        tan[i] = 0;
        tan[i + 1] = 0;
      } else {
        final a = tan[i] / slope[i], b = tan[i + 1] / slope[i];
        final s = a * a + b * b;
        if (s > 9) {
          final tau = 3 / math.sqrt(s);
          tan[i] = tau * a * slope[i];
          tan[i + 1] = tau * b * slope[i];
        }
      }
    }
    return Lut1D._(xs, ys, tan);
  }

  double eval(double x) {
    final count = xs.length;
    double y;
    if (x <= xs[0]) {
      y = ys[0];
    } else if (x >= xs[count - 1]) {
      y = ys[count - 1];
    } else {
      var k = 0;
      while (k < count - 2 && xs[k + 1] < x) {
        k++;
      }
      final h = xs[k + 1] - xs[k];
      final t = (x - xs[k]) / h;
      final m = (ys[k + 1] - ys[k]) / h;
      if (tangents[k] == m && tangents[k + 1] == m) {
        y = ys[k] + (ys[k + 1] - ys[k]) * t;
      } else {
        final h00 = 2 * t * t * t - 3 * t * t + 1;
        final h10 = t * t * t - 2 * t * t + t;
        final h01 = -2 * t * t * t + 3 * t * t;
        final h11 = t * t * t - t * t;
        y = h00 * ys[k] +
            h10 * h * tangents[k] +
            h01 * ys[k + 1] +
            h11 * h * tangents[k + 1];
      }
    }
    return y.clamp(0.0, 1.0);
  }
}

class GradeZone {
  final double shiftX, shiftY, lift, contrast, saturation, level, blend;
  const GradeZone(this.shiftX, this.shiftY, this.lift, this.contrast,
      this.saturation, this.level, this.blend);
  bool get isDefault =>
      shiftX == 0 &&
      shiftY == 0 &&
      lift == 0 &&
      contrast == 0.5 &&
      saturation == 0.5;
}

/// Exact port of the firmware's grade grid-point evaluation
/// (grade_write_banks in osc_handlers.c).
(double, double, double) gradeEval(
    double r, double g, double b, List<GradeZone> zones) {
  final y709 = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  double smooth(double yv, double level, double blend) {
    if (blend < 0.001) return yv < level ? 0 : 1;
    var t = (yv - (level - blend * 0.5)) / blend;
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return t * t * (3 - 2 * t);
  }

  final tS = smooth(y709, zones[0].level, zones[0].blend);
  final tM = smooth(y709, zones[1].level, zones[1].blend);
  final wSh = 1 - tS;
  final wHi = tM;
  var wMid = 1 - wSh - wHi;
  if (wMid < 0) wMid = 0;
  final weights = [wSh, wMid, wHi];
  const mids = [0.25, 0.5, 0.75];
  var rr = r, gg = g, bb = b;
  for (var z = 0; z < 3; z++) {
    final w = weights[z];
    final zn = zones[z];
    rr += zn.lift * w;
    gg += zn.lift * w;
    bb += zn.lift * w;
    rr += zn.shiftX * w * 0.5;
    bb += zn.shiftY * w * 0.5;
    gg -= (zn.shiftX + zn.shiftY) * w * 0.25;
    final cf = 1 + (zn.contrast - 0.5) * 2 * w;
    rr = mids[z] + (rr - mids[z]) * cf;
    gg = mids[z] + (gg - mids[z]) * cf;
    bb = mids[z] + (bb - mids[z]) * cf;
    final gray = (rr + gg + bb) / 3;
    final sf = 1 + (zn.saturation - 0.5) * 2 * w;
    rr = gray + (rr - gray) * sf;
    gg = gray + (gg - gray) * sf;
    bb = gray + (bb - gray) * sf;
  }
  return (rr.clamp(0.0, 1.0), gg.clamp(0.0, 1.0), bb.clamp(0.0, 1.0));
}

// -------------------------------------------------------- knob CSC stage ----

/// The picture knobs modify the destination YCbCr->RGB CSC (vendor
/// mdindst.c). The forward leg here converts RGB to YCbCr with the exact
/// inverse of the same base matrix, so neutral knobs compose to identity.
///
/// Base: BT.709 full-swing normalized (Kr=.2126, Kb=.0722). knob mapping
/// (osc_handlers.c): contrastB = contrast*255, hueB = (hue+180)/360*255,
/// satB = saturation*255, brightB = brightness*255; vendor formula:
/// contrastF = B/128, satF = B/128, hueRad = pi*(B-128)/384,
/// Y offset = (B-128)*8 on a 12-bit signal.
class PictureKnobs {
  final double brightness, contrast, saturation, hue; // config-domain values
  const PictureKnobs(this.brightness, this.contrast, this.saturation, this.hue);
  bool get isNeutral =>
      (brightness - 0.5).abs() < 1e-4 &&
      (contrast - 0.5).abs() < 1e-4 &&
      (saturation - 0.5).abs() < 1e-4 &&
      hue.abs() < 1e-4;

  (double, double, double) apply(double r, double g, double b) {
    const kr = 0.2126, kb = 0.0722, kg = 1 - kr - kb;
    // forward RGB -> YCbCr (full swing, Cb/Cr centered at 0)
    final y = kr * r + kg * g + kb * b;
    final cb = (b - y) / (2 * (1 - kb));
    final cr = (r - y) / (2 * (1 - kr));

    final cB = (contrast * 255) / 128.0;
    final sB = (saturation * 255) / 128.0;
    final hRad = math.pi * ((hue + 180.0) / 360.0 * 255.0 - 128.0) / 384.0;
    final bOff = ((brightness * 255) - 128.0) * 8.0 / 4096.0;

    final y2 = (y + bOff) * cB;
    final cosH = math.cos(hRad), sinH = math.sin(hRad);
    // vendor: [cb'] = ( cb*cos + cr*sin )*sat ; [cr'] = ( cr*cos - cb*sin )*sat
    final cb2 = (cb * cosH + cr * sinH) * sB;
    final cr2 = (cr * cosH - cb * sinH) * sB;

    // inverse: YCbCr -> RGB
    final r2 = y2 + 2 * (1 - kr) * cr2;
    final b2 = y2 + 2 * (1 - kb) * cb2;
    final g2 = (y2 - kr * r2 - kb * b2) / kg;
    return (
      r2.clamp(0.0, 1.0),
      g2.clamp(0.0, 1.0),
      b2.clamp(0.0, 1.0),
    );
  }
}

// ------------------------------------------------------------- composer ----

/// Compose the whole colour page into an n^3 .cube.
/// Hardware order: knob CSC -> 1D LUTs -> grade 3D LUT.
CubeLut composeColorCube({
  required PictureKnobs knobs,
  required Lut1D lutR,
  required Lut1D lutG,
  required Lut1D lutB,
  required List<GradeZone> grade,
  int n = 33,
  String title = 'SCION color page',
}) {
  final data = Float64List(n * n * n * 3);
  final gradeDefault = grade.every((z) => z.isDefault);
  var o = 0;
  for (var bi = 0; bi < n; bi++) {
    for (var gi = 0; gi < n; gi++) {
      for (var ri = 0; ri < n; ri++) {
        var r = ri / (n - 1.0), g = gi / (n - 1.0), b = bi / (n - 1.0);
        if (!knobs.isNeutral) (r, g, b) = knobs.apply(r, g, b);
        r = lutR.eval(r);
        g = lutG.eval(g);
        b = lutB.eval(b);
        if (!gradeDefault) (r, g, b) = gradeEval(r, g, b, grade);
        data[o++] = r;
        data[o++] = g;
        data[o++] = b;
      }
    }
  }
  return CubeLut(n, data, title);
}
