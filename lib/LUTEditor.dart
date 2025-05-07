import 'package:flutter/material.dart';
import 'dart:math';

import 'MonotonicSpline.dart';
import 'OscPathSegment.dart';

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

class LUTEditor extends StatefulWidget {
  const LUTEditor({super.key});

  @override
  State<LUTEditor> createState() => _LUTEditorState();
}

class _LUTEditorState extends State<LUTEditor> with OscAddressMixin<LUTEditor> {
  final ValueNotifier<bool> flashLockNotifier = ValueNotifier(false);

  static const List<String> channels = ['Y', 'R', 'G', 'B'];

  final Map<String, List<Offset>> controlPoints = {
    'Y': [Offset(0, 0), Offset(1, 1)],
    'R': [Offset(0, 0), Offset(1, 1)],
    'G': [Offset(0, 0), Offset(1, 1)],
    'B': [Offset(0, 0), Offset(1, 1)],
  };

  final Map<String, MonotonicSpline?> splines = {
    'Y': null,
    'R': null,
    'G': null,
    'B': null,
  };

  bool locked = true;
  String selectedChannel = 'Y';
  int? currentControlPointIdx;
  bool isDragging = false;

  static const double insetPadding =
      20.0; // True padding to avoid clipping control points

  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies(); // runs OscAddressMixin’s logic first

    if (!_didInit) {
      _didInit = true;
      updateSplines(); // now oscAddress is valid
    }
  }

  @override
  void initState() {
    super.initState();
  }

  void updateSplines() {
    setState(() {
      for (var c in channels) {
        splines[c] = MonotonicSpline(controlPoints[c]!);
      }
    });

    // After updating, send OSC with flattened control points for selected channel
    final addr = '$oscAddress/$selectedChannel';

    final points = controlPoints[selectedChannel]!;
    final flat = <double>[];
    for (var pt in points) {
      flat.add(pt.dx);
      flat.add(pt.dy);
    }
    sendOsc(flat, address: addr);
  }

  void resetControlPoints() {
    setState(() {
      for (var c in channels) {
        controlPoints[c] = [Offset(0, 0), Offset(1, 1)];
      }
      updateSplines();
    });
  }

  int findInsertIndex(double x, List<Offset> points) {
    int i = 0;
    while (i < points.length && points[i].dx < x) {
      i++;
    }
    return i;
  }

  int? findNearbyControlPoint(Offset pos, List<Offset> points) {
    for (int i = 0; i < points.length; i++) {
      final dx = points[i].dx - pos.dx;
      final dy = points[i].dy - pos.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (dist < 0.05) return i;
    }
    return null;
  }

  Offset normalize(Offset localPos, Size size) {
    final double w = size.width - 2 * insetPadding;
    final double h = size.height - 2 * insetPadding;
    return Offset(
      (localPos.dx - insetPadding) / w,
      1.0 - (localPos.dy - insetPadding) / h,
    );
  }

  void onPanStart(DragStartDetails details, Size size) {
    final pos = normalize(details.localPosition, size);
    final points = controlPoints[selectedChannel]!;

    final idx = findNearbyControlPoint(pos, points);
    setState(() {
      if (idx != null) {
        currentControlPointIdx = idx;
      } else {
        int i = findInsertIndex(pos.dx, points);
        points.insert(i, pos);
        currentControlPointIdx = i;
        if (locked && selectedChannel == 'Y') {
          for (var c in channels) {
            controlPoints[c] = List<Offset>.from(points);
          }
        }
        updateSplines();
      }
      isDragging = true;
    });
  }

  void onPanUpdate(DragUpdateDetails details, Size size) {
    if (!isDragging || currentControlPointIdx == null) return;

    final pos = normalize(details.localPosition, size);
    final points = controlPoints[selectedChannel]!;

    setState(() {
      double x = pos.dx.clamp(0.0, 1.0);
      double y = pos.dy.clamp(0.0, 1.0);

      const double minSpace = 0.01;
      if (currentControlPointIdx! < points.length - 1) {
        double nextX = points[currentControlPointIdx! + 1].dx;
        x = min(x, nextX - minSpace);
      }
      if (currentControlPointIdx! > 0) {
        double prevX = points[currentControlPointIdx! - 1].dx;
        x = max(x, prevX + minSpace);
      }

      if (currentControlPointIdx == 0) {
        if (x > y) {
          y = 0;
        } else {
          x = 0;
        }
      }
      if (currentControlPointIdx == points.length - 1) {
        if (x < y) {
          y = 1;
        } else {
          x = 1;
        }
      }

      points[currentControlPointIdx!] = Offset(x, y);

      if (locked && selectedChannel == 'Y') {
        for (var c in channels) {
          controlPoints[c] = List<Offset>.from(points);
        }
      }
      updateSplines();
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
    final points = controlPoints[selectedChannel]!;

    final idx = findNearbyControlPoint(pos, points);

    if (idx != null) {
      setState(() {
        points.removeAt(idx);
        currentControlPointIdx = null;
        if (locked && selectedChannel == 'Y') {
          for (var c in channels) {
            controlPoints[c] = List<Offset>.from(points);
          }
        }
        updateSplines();
      });
    }
  }

  Widget buildButton({
    required Widget child,
    required bool selected,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor:
            selected ? (color ?? Colors.white) : Colors.transparent,
        side: BorderSide(color: (color ?? Colors.white)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      onPressed: onPressed,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              buildButton(
                child: const Icon(Icons.refresh, color: Colors.white),
                selected: false,
                onPressed: resetControlPoints,
              ),
              const Spacer(),
              ValueListenableBuilder<bool>(
                valueListenable: flashLockNotifier,
                builder: (context, flashing, child) {
                  return buildButton(
                    child: Icon(
                      locked ? Icons.lock : Icons.lock_open,
                      color: flashing
                          ? Colors.amber
                          : (locked ? Colors.grey[900] : Colors.white),
                    ),
                    selected: locked,
                    onPressed: () {
                      setState(() {
                        locked = !locked;
                        if (locked) {
                          // Copy Y into R,G,B
                          for (var c in ['R', 'G', 'B']) {
                            controlPoints[c] =
                                List<Offset>.from(controlPoints['Y']!);
                          }
                          updateSplines();
                          selectedChannel = 'Y';
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(width: 8),
              for (var c in channels)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: buildButton(
                    child: Text(
                      c,
                      style: TextStyle(
                        color: selectedChannel == c
                            ? Colors.grey[900]
                            : getChannelColor(c),
                      ),
                    ),
                    selected: selectedChannel == c,
                    color: getChannelColor(c).withOpacity(0.8),
                    onPressed: () {
                      if (locked && c != 'Y') {
                        flashLockNotifier.value = true;
                        Future.delayed(const Duration(milliseconds: 200), () {
                          flashLockNotifier.value = false;
                        });
                        return;
                      }
                      setState(() => selectedChannel = c);
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth == 0 || constraints.maxHeight == 0) {
                    return const SizedBox.shrink();
                  }
                  final size =
                      Size(constraints.maxWidth, constraints.maxHeight);

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (details) => onPanStart(details, size),
                    onPanUpdate: (details) => onPanUpdate(details, size),
                    onPanEnd: (_) => onPanEnd(),
                    onLongPressStart: (details) =>
                        onLongPressStart(details, size),
                    child: CustomPaint(
                      size: size,
                      painter: LUTPainter(
                        controlPoints: controlPoints,
                        splines: splines,
                        selectedChannel: selectedChannel,
                        highlightedIndex: currentControlPointIdx,
                        insetPadding: insetPadding,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
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
