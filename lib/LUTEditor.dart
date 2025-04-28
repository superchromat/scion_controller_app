import 'package:flutter/material.dart';
import 'dart:math';

class LUTEditor extends StatefulWidget {
  const LUTEditor({super.key});

  @override
  State<LUTEditor> createState() => _LUTEditorState();
}

class _LUTEditorState extends State<LUTEditor> {
  List<Offset> controlPoints = [
    Offset(0, 0),
    Offset(1, 1),
  ];

  late List<Offset> initialControlPoints;
  MonotonicSpline? spline;
  int? currentControlPointIdx;
  bool isDragging = false;

  @override
  void initState() {
    super.initState();
    initialControlPoints = List<Offset>.from(controlPoints);
    updateSpline();
  }

  void updateSpline() {
    setState(() {
      spline = MonotonicSpline(controlPoints);
    });
  }

  void resetControlPoints() {
    setState(() {
      controlPoints = List<Offset>.from(initialControlPoints);
      updateSpline();
    });
  }

  int findInsertIndex(double x) {
    int i = 0;
    while (i < controlPoints.length && controlPoints[i].dx < x) {
      i++;
    }
    return i;
  }

  int? findNearbyControlPoint(Offset pos) {
    for (int i = 0; i < controlPoints.length; i++) {
      final dx = controlPoints[i].dx - pos.dx;
      final dy = controlPoints[i].dy - pos.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.05) {
        return i;
      }
    }
    return null;
  }

  Offset normalize(Offset localPos, Size size) {
    return Offset(
      (localPos.dx / size.width),
      (1.0 - (localPos.dy / size.height)),
    );
  }

  void onPanStart(DragStartDetails details, Size size) {
    final pos = normalize(details.localPosition, size);
    final idx = findNearbyControlPoint(pos);
    setState(() {
      if (idx != null) {
        currentControlPointIdx = idx;
      } else {
        int i = findInsertIndex(pos.dx);
        controlPoints.insert(i, pos);
        currentControlPointIdx = i;
        updateSpline();
      }
      isDragging = true;
    });
  }

  void onPanUpdate(DragUpdateDetails details, Size size) {
    if (!isDragging || currentControlPointIdx == null) return;

    final pos = normalize(details.localPosition, size);

    setState(() {
      double x = pos.dx.clamp(0.0, 1.0);
      double y = pos.dy.clamp(0.0, 1.0);

      const double minSpace = 0.01;
      if (currentControlPointIdx! < controlPoints.length - 1) {
        double nextX = controlPoints[currentControlPointIdx! + 1].dx;
        x = min(x, nextX - minSpace);
      }
      if (currentControlPointIdx! > 0) {
        double prevX = controlPoints[currentControlPointIdx! - 1].dx;
        x = max(x, prevX + minSpace);
      }

      // Special handling for first point
      if (currentControlPointIdx == 0) {
        if (x > y) {
          y = 0;
        } else {
          x = 0;
        }
      }

      // Special handling for last point
      if (currentControlPointIdx == controlPoints.length - 1) {
        if (x < y) {
          y = 1;
        } else {
          x = 1;
        }
      }

      controlPoints[currentControlPointIdx!] = Offset(x, y);
      updateSpline();
    });
  }

  void onPanEnd() {
    setState(() {
      isDragging = false;
      currentControlPointIdx = null;
    });
  }

  void onLongPressStart(LongPressStartDetails details, Size size) {
    final pos = normalize(details.localPosition, size);
    final idx = findNearbyControlPoint(pos);

    if (idx != null) {
      setState(() {
        controlPoints.removeAt(idx);
        currentControlPointIdx = null;
        updateSpline();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.7,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);

          return Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => onPanStart(details, size),
                onPanUpdate: (details) => onPanUpdate(details, size),
                onPanEnd: (_) => onPanEnd(),
                onLongPressStart: (details) => onLongPressStart(details, size),
                child: ClipRect(
                  child: CustomPaint(
                    size: size,
                    painter: LUTPainter(
                      controlPoints: controlPoints,
                      spline: spline,
                      highlightedIndex: currentControlPointIdx,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: Icon(Icons.restore, size: 20),
                  color: Colors.white,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                  onPressed: resetControlPoints,
                  tooltip: 'Reset control points',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class LUTPainter extends CustomPainter {
  final List<Offset> controlPoints;
  final MonotonicSpline? spline;
  final int? highlightedIndex;

  LUTPainter(
      {required this.controlPoints,
      required this.spline,
      this.highlightedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint gridPaintMinor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.25;

    final Paint gridPaintMajor = Paint()
      ..color = const Color(0xFF53525A)
      ..strokeWidth = 0.5;

    final Paint curvePaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final Paint pointPaint = Paint()
      ..color = const Color.fromARGB(255, 54, 120, 244)
      ..style = PaintingStyle.fill;

    final Paint selectedPointPaint = Paint()
      ..color = const Color.fromARGB(255, 59, 222, 255)
      ..style = PaintingStyle.fill;

    // Draw grid
    for (double i = 0; i <= 1.0; i += 0.05) {
      final x = i * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaintMinor);

      final y = (1.0 - i) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaintMinor);
    }

    for (double i = 0; i <= 1.0; i += 0.2) {
      final x = i * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaintMajor);

      final y = (1.0 - i) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaintMajor);
    }

    if (spline != null) {
      final Path path = Path();
      for (int i = 0; i <= 100; i++) {
        final t = i / 100.0;
        final x = t;
        final y = spline!.evaluate(x).clamp(0.0, 1.0);
        final pos = Offset(x * size.width, (1.0 - y) * size.height);

        if (i == 0) {
          path.moveTo(pos.dx, pos.dy);
        } else {
          path.lineTo(pos.dx, pos.dy);
        }
      }
      canvas.drawPath(path, curvePaint);
    }

    for (int i = 0; i < controlPoints.length; i++) {
      final point = controlPoints[i];
      final pos = Offset(point.dx * size.width, (1.0 - point.dy) * size.height);
      final isSelected = (i == highlightedIndex);

      canvas.drawCircle(pos, 5, isSelected ? selectedPointPaint : pointPaint);
      canvas.drawCircle(
          pos,
          5,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ------------------
// Monotonic Spline
// ------------------
class MonotonicSpline {
  final List<Offset> points;
  late final List<double> _slopes;
  late final List<double> _tangents;

  MonotonicSpline(this.points) {
    assert(points.length >= 2);
    _computeSlopes();
    _computeTangents();
  }

  void _computeSlopes() {
    _slopes = [];
    for (int i = 0; i < points.length - 1; i++) {
      final dx = points[i + 1].dx - points[i].dx;
      final dy = points[i + 1].dy - points[i].dy;
      _slopes.add(dy / dx);
    }
  }

  void _computeTangents() {
    _tangents = List.filled(points.length, 0.0);

    _tangents[0] = _slopes[0];
    for (int i = 1; i < points.length - 1; i++) {
      final mPrev = _slopes[i - 1];
      final mNext = _slopes[i];

      if (mPrev * mNext <= 0) {
        _tangents[i] = 0.0;
      } else {
        _tangents[i] = (mPrev + mNext) / 2.0;
      }
    }
    _tangents[points.length - 1] = _slopes[_slopes.length - 1];

    // Enforce monotonicity constraint
    for (int i = 0; i < _slopes.length; i++) {
      if (_slopes[i] == 0.0) {
        _tangents[i] = 0.0;
        _tangents[i + 1] = 0.0;
      } else {
        final a = _tangents[i] / _slopes[i];
        final b = _tangents[i + 1] / _slopes[i];
        final s = a * a + b * b;
        if (s > 9.0) {
          final tau = 3.0 / sqrt(s);
          _tangents[i] = tau * a * _slopes[i];
          _tangents[i + 1] = tau * b * _slopes[i];
        }
      }
    }
  }

  double evaluate(double x) {
    if (x <= points.first.dx) return points.first.dy;
    if (x >= points.last.dx) return points.last.dy;

    int i = 0;
    while (i < points.length - 2 && points[i + 1].dx < x) {
      i++;
    }

    final x0 = points[i].dx;
    final x1 = points[i + 1].dx;
    final y0 = points[i].dy;
    final y1 = points[i + 1].dy;
    final t0 = _tangents[i];
    final t1 = _tangents[i + 1];
    final h = x1 - x0;
    final t = (x - x0) / h;

    final m = _slopes[i];

    // If the tangents match the slope perfectly, do linear interpolation
    if ((t0 == m && t1 == m)) {
      return y0 + (y1 - y0) * t;
    }

    // Otherwise Hermite cubic interpolation
    final h00 = (2 * t * t * t) - (3 * t * t) + 1;
    final h10 = (t * t * t) - (2 * t * t) + t;
    final h01 = (-2 * t * t * t) + (3 * t * t);
    final h11 = (t * t * t) - (t * t);

    return h00 * y0 + h10 * h * t0 + h01 * y1 + h11 * h * t1;
  }
}
