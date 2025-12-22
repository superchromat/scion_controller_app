import 'package:flutter/material.dart';
import 'color_wheel.dart';

class ColorspaceWheelPage extends StatefulWidget {
  const ColorspaceWheelPage({super.key});

  @override
  State<ColorspaceWheelPage> createState() => _ColorspaceWheelPageState();
}

class _ColorspaceWheelPageState extends State<ColorspaceWheelPage> {
  List<double> _ch1 = [1, 0, 0];
  List<double> _ch2 = [0, 1, 0];
  List<double> _ch3 = [0, 0, 1];

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
    const size = 150.0;
    return Column(
      children: [
        Text(label),
        const SizedBox(height: 8),
        GestureDetector(
          onPanUpdate: (d) => onChanged(wheelPositionToRgb(d.localPosition, size)),
          onTapDown: (d) => onChanged(wheelPositionToRgb(d.localPosition, size)),
          child: CustomPaint(
            size: const Size(size, size),
            painter: ColorWheelPainter(rgb, other1, other2, wheelIndex),
          ),
        ),
        const SizedBox(height: 4),
        Text('R:${rgb[0].toStringAsFixed(2)} G:${rgb[1].toStringAsFixed(2)} B:${rgb[2].toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
      ],
    );
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
