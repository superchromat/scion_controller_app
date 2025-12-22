import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';

class ColorspaceWheelPage extends StatefulWidget {
  const ColorspaceWheelPage({super.key});

  @override
  State<ColorspaceWheelPage> createState() => _ColorspaceWheelPageState();
}

class _ColorspaceWheelPageState extends State<ColorspaceWheelPage> {
  // RGB values for each channel (columns of inverse matrix)
  List<double> _ch1 = [1, 0, 0]; // Red
  List<double> _ch2 = [0, 1, 0]; // Green
  List<double> _ch3 = [0, 0, 1]; // Blue

  @override
  Widget build(BuildContext context) {
    final matrix = _computeInverseMatrix();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Colorspace Matrix Editor', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 16),

          // Three wheels in a row
          Row(
            children: [
              _buildWheel('Channel 1', _ch1, (v) => setState(() => _ch1 = v), _ch2, _ch3, 0),
              const SizedBox(width: 16),
              _buildWheel('Channel 2', _ch2, (v) => setState(() => _ch2 = v), _ch1, _ch3, 1),
              const SizedBox(width: 16),
              _buildWheel('Channel 3', _ch3, (v) => setState(() => _ch3 = v), _ch1, _ch2, 2),
            ],
          ),

          const SizedBox(height: 24),

          // Matrix display
          Row(
            children: [
              _buildMatrixCard('Primaries (M)', [_ch1, _ch2, _ch3]),
              const SizedBox(width: 16),
              if (matrix != null)
                _buildMatrixCard('Transform (M⁻¹)', matrix)
              else
                const Text('Singular matrix', style: TextStyle(color: Colors.red)),
            ],
          ),

          const SizedBox(height: 16),

          // Presets
          Row(
            children: [
              OutlinedButton(
                onPressed: () => setState(() {
                  _ch1 = [1, 0, 0];
                  _ch2 = [0, 1, 0];
                  _ch3 = [0, 0, 1];
                }),
                child: const Text('RGB'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _ch1 = [1, 1, 1];
                  _ch2 = [0, -0.394, 2.032];
                  _ch3 = [1.14, -0.581, 0];
                }),
                child: const Text('YUV 601'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWheel(String label, List<double> rgb, ValueChanged<List<double>> onChanged,
      List<double> other1, List<double> other2, int wheelIndex) {
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 8),
        GestureDetector(
          onPanUpdate: (d) => _handleWheelDrag(d.localPosition, onChanged),
          onTapDown: (d) => _handleWheelDrag(d.localPosition, onChanged),
          child: CustomPaint(
            size: const Size(150, 150),
            painter: _WheelPainter(rgb, other1, other2, wheelIndex),
          ),
        ),
        const SizedBox(height: 4),
        Text('R:${rgb[0].toStringAsFixed(2)} G:${rgb[1].toStringAsFixed(2)} B:${rgb[2].toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
      ],
    );
  }

  void _handleWheelDrag(Offset pos, ValueChanged<List<double>> onChanged) {
    const size = 150.0;
    final center = Offset(size / 2, size / 2);
    final offset = pos - center;
    final radius = size / 2;

    final angle = atan2(offset.dy, offset.dx);
    final dist = (offset.distance / radius).clamp(0.0, 1.0);

    // Scale: r=0.5 is sRGB boundary, r=1.0 is 2x extrapolation
    final scaledDist = dist * 2.0;

    // Convert angle to hue: SweepGradient starts at 0 rad (3 o'clock) = red (0°)
    final hue = (angle * 180 / pi + 360) % 360;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    // Interpolate/extrapolate from white [1,1,1] toward hue
    final r = 1.0 + (hueColor.r - 1.0) * scaledDist;
    final g = 1.0 + (hueColor.g - 1.0) * scaledDist;
    final b = 1.0 + (hueColor.b - 1.0) * scaledDist;

    onChanged([r, g, b]);
  }

  Widget _buildMatrixCard(String title, List<List<double>> m) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A3C),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var row in m)
            Text(
              row.map((v) => v.toStringAsFixed(3).padLeft(7)).join(' '),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
        ],
      ),
    );
  }

  List<List<double>>? _computeInverseMatrix() {
    // Matrix M has primaries as columns
    final m = [
      [_ch1[0], _ch2[0], _ch3[0]],
      [_ch1[1], _ch2[1], _ch3[1]],
      [_ch1[2], _ch2[2], _ch3[2]],
    ];

    final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    if (det.abs() < 1e-10) return null;

    final adj = [
      [m[1][1]*m[2][2] - m[1][2]*m[2][1], m[0][2]*m[2][1] - m[0][1]*m[2][2], m[0][1]*m[1][2] - m[0][2]*m[1][1]],
      [m[1][2]*m[2][0] - m[1][0]*m[2][2], m[0][0]*m[2][2] - m[0][2]*m[2][0], m[0][2]*m[1][0] - m[0][0]*m[1][2]],
      [m[1][0]*m[2][1] - m[1][1]*m[2][0], m[0][1]*m[2][0] - m[0][0]*m[2][1], m[0][0]*m[1][1] - m[0][1]*m[1][0]],
    ];

    return adj.map((row) => row.map((v) => v / det).toList()).toList();
  }
}

class _WheelPainter extends CustomPainter {
  final List<double> selected;
  final List<double> otherPrimary1;
  final List<double> otherPrimary2;
  final int wheelIndex; // 0, 1, or 2

  _WheelPainter(this.selected, this.otherPrimary1, this.otherPrimary2, this.wheelIndex);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final srgbRadius = radius * 0.5; // sRGB boundary at half radius
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Sweep gradient for hues
    final hueColors = [
      const Color(0xFFFF0000), // 0° Red
      const Color(0xFFFFFF00), // 60° Yellow
      const Color(0xFF00FF00), // 120° Green
      const Color(0xFF00FFFF), // 180° Cyan
      const Color(0xFF0000FF), // 240° Blue
      const Color(0xFFFF00FF), // 300° Magenta
      const Color(0xFFFF0000), // 360° Red
    ];

    final huePaint = Paint()
      ..shader = SweepGradient(colors: hueColors).createShader(rect);
    canvas.drawCircle(center, radius, huePaint);

    // Radial gradient for saturation (white center fading out)
    final satPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(rect);
    canvas.drawCircle(center, radius, satPaint);

    // Draw sRGB boundary circle
    canvas.drawCircle(
      center,
      srgbRadius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Draw condition number isolines
    _drawIsolines(canvas, center, radius, srgbRadius);

    // Draw selection indicator
    // Convert RGB back to wheel position
    final r = selected[0], g = selected[1], b = selected[2];

    // Find the direction from white and distance
    final dr = r - 1.0, dg = g - 1.0, db = b - 1.0;
    final distFromWhite = sqrt(dr * dr + dg * dg + db * db);

    Offset selPos;
    if (distFromWhite < 0.001) {
      selPos = center;
    } else {
      // Find hue by matching direction from white (works for extended gamut)
      final len = distFromWhite;
      final ndr = dr / len, ndg = dg / len, ndb = db / len;

      double bestHue = 0;
      double bestDot = -2;
      for (double h = 0; h < 360; h += 2) {
        final hc = HSVColor.fromAHSV(1, h, 1, 1).toColor();
        final hdr = hc.r - 1.0, hdg = hc.g - 1.0, hdb = hc.b - 1.0;
        final hlen = sqrt(hdr * hdr + hdg * hdg + hdb * hdb);
        if (hlen < 0.001) continue;
        final dot = ndr * (hdr / hlen) + ndg * (hdg / hlen) + ndb * (hdb / hlen);
        if (dot > bestDot) {
          bestDot = dot;
          bestHue = h;
        }
      }

      final angle = bestHue * pi / 180;

      // Get the hue color to calculate proper distance
      final hueColor = HSVColor.fromAHSV(1, bestHue, 1, 1).toColor();
      final hdr = hueColor.r - 1.0, hdg = hueColor.g - 1.0, hdb = hueColor.b - 1.0;
      final hueDist = sqrt(hdr * hdr + hdg * hdg + hdb * hdb);

      // scaledDist = distFromWhite / hueDist, wheelDist = scaledDist / 2
      final wheelDist = hueDist > 0.001 ? (distFromWhite / hueDist / 2.0) * radius : 0.0;
      selPos = center + Offset(cos(angle) * wheelDist, sin(angle) * wheelDist);
    }

    final selColor = Color.fromRGBO(
      (r.clamp(0, 1) * 255).round(),
      (g.clamp(0, 1) * 255).round(),
      (b.clamp(0, 1) * 255).round(),
      1,
    );
    canvas.drawCircle(selPos, 8, Paint()..color = selColor);
    canvas.drawCircle(selPos, 8, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  void _drawIsolines(Canvas canvas, Offset center, double radius, double srgbRadius) {
    // Brute force per-pixel computation
    const step = 2.0; // 2px steps for ~5600 samples

    for (double x = -radius; x <= radius; x += step) {
      for (double y = -radius; y <= radius; y += step) {
        final dist = sqrt(x * x + y * y);
        if (dist > radius + step || dist < 3) continue;
        final clampedDist = dist.clamp(0.0, radius);

        final angle = atan2(y, x);
        final normalizedRadius = clampedDist / radius;
        final kappa = _conditionNumberAt(angle, normalizedRadius, srgbRadius);

        final logKappa = log(kappa.clamp(1, 10000)) / ln10;
        final opacity = ((logKappa - 0.5) / 2.5).clamp(0.0, 0.6);

        if (opacity > 0.01) {
          canvas.drawRect(
            Rect.fromLTWH(center.dx + x - step/2, center.dy + y - step/2, step, step),
            Paint()..color = Colors.black.withValues(alpha: opacity),
          );
        }
      }
    }
  }

  double _conditionNumberAt(double angle, double normalizedRadius, double srgbRadius) {
    // Convert wheel position to RGB
    final scaledDist = normalizedRadius * 2.0;
    final hue = (angle * 180 / pi + 360) % 360;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    final r = 1.0 + (hueColor.r - 1.0) * scaledDist;
    final g = 1.0 + (hueColor.g - 1.0) * scaledDist;
    final b = 1.0 + (hueColor.b - 1.0) * scaledDist;

    final testPrimary = [r, g, b];

    // Build matrix with this primary and the other two
    List<List<double>> matrix;
    if (wheelIndex == 0) {
      matrix = [
        [testPrimary[0], otherPrimary1[0], otherPrimary2[0]],
        [testPrimary[1], otherPrimary1[1], otherPrimary2[1]],
        [testPrimary[2], otherPrimary1[2], otherPrimary2[2]],
      ];
    } else if (wheelIndex == 1) {
      matrix = [
        [otherPrimary1[0], testPrimary[0], otherPrimary2[0]],
        [otherPrimary1[1], testPrimary[1], otherPrimary2[1]],
        [otherPrimary1[2], testPrimary[2], otherPrimary2[2]],
      ];
    } else {
      matrix = [
        [otherPrimary1[0], otherPrimary2[0], testPrimary[0]],
        [otherPrimary1[1], otherPrimary2[1], testPrimary[1]],
        [otherPrimary1[2], otherPrimary2[2], testPrimary[2]],
      ];
    }

    return _computeConditionNumber(matrix);
  }

  double _computeConditionNumber(List<List<double>> m) {
    // Use ||M||_F * ||M^-1||_F as condition number estimate
    // First compute Frobenius norm of M
    double frobM = 0;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        frobM += m[i][j] * m[i][j];
      }
    }
    frobM = sqrt(frobM);

    // Compute determinant
    final det = m[0][0] * (m[1][1] * m[2][2] - m[1][2] * m[2][1]) -
                m[0][1] * (m[1][0] * m[2][2] - m[1][2] * m[2][0]) +
                m[0][2] * (m[1][0] * m[2][1] - m[1][1] * m[2][0]);

    if (det.abs() < 1e-10) return double.infinity;

    // Compute adjugate (for inverse)
    final adj = [
      [m[1][1]*m[2][2] - m[1][2]*m[2][1], m[0][2]*m[2][1] - m[0][1]*m[2][2], m[0][1]*m[1][2] - m[0][2]*m[1][1]],
      [m[1][2]*m[2][0] - m[1][0]*m[2][2], m[0][0]*m[2][2] - m[0][2]*m[2][0], m[0][2]*m[1][0] - m[0][0]*m[1][2]],
      [m[1][0]*m[2][1] - m[1][1]*m[2][0], m[0][1]*m[2][0] - m[0][0]*m[2][1], m[0][0]*m[1][1] - m[0][1]*m[1][0]],
    ];

    // Frobenius norm of inverse = ||adj||_F / |det|
    double frobAdj = 0;
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        frobAdj += adj[i][j] * adj[i][j];
      }
    }
    final frobInv = sqrt(frobAdj) / det.abs();

    return frobM * frobInv;
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => true;
}
