import 'package:flutter/material.dart';
import 'monotonic_spline.dart';

Color getChannelColor(String channel) {
  switch (channel) {
    case 'R':
      return Colors.red;
    case 'G':
      return Colors.green;
    case 'B':
      return Colors.blue;
    default:
      return Colors.white;
  }
}

class LUTPainter extends CustomPainter {
  final Map<String, List<Offset>> controlPoints;
  final Map<String, MonotonicSpline?> splines;
  final String selectedChannel;
  final int? highlightedIndex;
  final double insetPadding;

  LUTPainter({
    required this.controlPoints,
    required this.splines,
    required this.selectedChannel,
    required this.highlightedIndex,
    required this.insetPadding,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintGridMinor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.25;

    final paintGridMajor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.5;

    final paintOther = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintSelected = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final paintPoint = Paint()
      ..color = const Color(0xFF3678F4)
      ..style = PaintingStyle.fill;

    final paintSelectedPoint = Paint()
      ..color = const Color(0xFF3BDEFF)
      ..style = PaintingStyle.fill;

    final w = size.width - 2 * insetPadding;
    final h = size.height - 2 * insetPadding;

    canvas.translate(insetPadding, insetPadding);

    // Draw grid
    for (double i = 0; i <= 1; i += 0.05) {
      canvas.drawLine(Offset(i * w, 0), Offset(i * w, h), paintGridMinor);
      canvas.drawLine(Offset(0, i * h), Offset(w, i * h), paintGridMinor);
    }
    for (double i = 0; i <= 1; i += 0.2) {
      canvas.drawLine(Offset(i * w, 0), Offset(i * w, h), paintGridMajor);
      canvas.drawLine(Offset(0, i * h), Offset(w, i * h), paintGridMajor);
    }

    // Draw all unselected curves first
    for (var c in ['B', 'G', 'R', 'Y']) {
      if (c == selectedChannel) continue; // skip selected
      final spline = splines[c];
      if (spline == null) continue;

      final path = Path();
      for (int i = 0; i <= 100; i++) {
        final t = i / 100;
        final x = t;
        final y = spline.evaluate(x).clamp(0.0, 1.0);
        final pos = Offset(x * w, (1.0 - y) * h);

        if (i == 0) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      paintOther.color = getChannelColor(c).withOpacity(0.5);
      canvas.drawPath(path, paintOther);
    }

    // Draw selected curve last (thick and bright)
    final selectedSpline = splines[selectedChannel];
    if (selectedSpline != null) {
      final path = Path();
      for (int i = 0; i <= 100; i++) {
        final t = i / 100;
        final x = t;
        final y = selectedSpline.evaluate(x).clamp(0.0, 1.0);
        final pos = Offset(x * w, (1.0 - y) * h);

        if (i == 0) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      paintSelected.color = getChannelColor(selectedChannel);
      canvas.drawPath(path, paintSelected);
    }

    // Draw control points
    final points = controlPoints[selectedChannel]!;
    for (int i = 0; i < points.length; i++) {
      final pos = Offset(points[i].dx * w, (1 - points[i].dy) * h);
      final selected = (i == highlightedIndex);

      canvas.drawCircle(pos, 5, selected ? paintSelectedPoint : paintPoint);
      canvas.drawCircle(
        pos,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
