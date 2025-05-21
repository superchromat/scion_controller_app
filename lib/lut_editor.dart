import 'package:flutter/material.dart';
import 'dart:math';

import 'monotonic_spline.dart';
import 'osc_widget_binding.dart';
import 'lut_painter.dart';

class LUTEditor extends StatefulWidget {
  /// Maximum number of control points per channel (including placeholders).
  final int maxControlPoints;

  const LUTEditor({
    super.key,
    this.maxControlPoints = 16,
  });

  @override
  State<LUTEditor> createState() => _LUTEditorState();
}

class _LUTEditorState extends State<LUTEditor> with OscAddressMixin<LUTEditor> {
  final ValueNotifier<bool> flashLockNotifier = ValueNotifier(false);
  static const List<String> channels = ['Y', 'R', 'G', 'B'];

  late final Map<String, List<Offset>> controlPoints;
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

  static const double insetPadding = 20.0;
  bool _didInit = false;

  @override
  void initState() {
    super.initState();

    // Initialize fixed-size lists with placeholders
    controlPoints = Map.fromEntries(
      channels.map((c) {
        return MapEntry(
          c,
          List<Offset>.generate(
            widget.maxControlPoints,
            (i) => i == 0
                ? const Offset(0, 0)
                : i == 1
                    ? const Offset(1, 1)
                    : const Offset(-1, -1),
          ),
        );
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_didInit) {
      _didInit = true;

      // Register defaults for each channel (including placeholders)
      for (var c in channels) {
        final flat = (List<Offset>.from(controlPoints[c]!)
              ..sort((a, b) => a.dx.compareTo(b.dx)))
            .expand((pt) => [pt.dx, pt.dy])
            .toList();
        setDefaultValues(flat, address: c);
      }

      updateSplines();
    }
  }

  void updateSplines() {
    setState(() {
      for (var c in channels) {
        final activePts = controlPoints[c]!.where((pt) => pt.dx >= 0).toList()
          ..sort((a, b) => a.dx.compareTo(b.dx));
        splines[c] = MonotonicSpline(activePts);
      }
    });

    // Send OSC for selected channel with sorted points
    final addr = '$oscAddress/$selectedChannel';
    final sortedPts = controlPoints[selectedChannel]!.toList()
      ..sort((a, b) => a.dx.compareTo(b.dx));
    final flat = sortedPts.expand((pt) => [pt.dx, pt.dy]).toList();
    sendOsc(flat, address: addr);
  }

  void resetControlPoints() {
    setState(() {
      for (var c in channels) {
        final list = controlPoints[c]!;
        for (int i = 0; i < widget.maxControlPoints; i++) {
          list[i] = i == 0
              ? const Offset(0, 0)
              : i == 1
                  ? const Offset(1, 1)
                  : const Offset(-1, -1);
        }
      }
      updateSplines();
    });
  }

  int? _findUnusedIndex(List<Offset> pts) {
    final idx = pts.indexWhere((pt) => pt.dx < 0);
    return idx == -1 ? null : idx;
  }

  int? findNearbyControlPoint(Offset pos, List<Offset> points) {
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      if (pt.dx < 0) continue;
      final dx = pt.dx - pos.dx;
      final dy = pt.dy - pos.dy;
      if (sqrt(dx * dx + dy * dy) < 0.05) return i;
    }
    return null;
  }

  Offset normalize(Offset localPos, Size size) {
    final w = size.width - 2 * insetPadding;
    final h = size.height - 2 * insetPadding;
    return Offset(
      (localPos.dx - insetPadding) / w,
      1.0 - (localPos.dy - insetPadding) / h,
    );
  }

  void onPanStart(DragStartDetails details, Size size) {
    final pos = normalize(details.localPosition, size);
    final pts = controlPoints[selectedChannel]!;
    final idx = findNearbyControlPoint(pos, pts);

    setState(() {
      if (idx != null) {
        currentControlPointIdx = idx;
      } else {
        final unused = _findUnusedIndex(pts);
        if (unused != null) {
          pts[unused] = pos;
          currentControlPointIdx = unused;
          if (locked && selectedChannel == 'Y') {
            for (var c in channels) {
              controlPoints[c]![unused] = pos;
            }
          }
          updateSplines();
        }
      }
      isDragging = true;
    });
  }

  void onPanUpdate(DragUpdateDetails details, Size size) {
    if (!isDragging || currentControlPointIdx == null) return;
    final pos = normalize(details.localPosition, size);
    final pts = controlPoints[selectedChannel]!;
    final idx = currentControlPointIdx!;

    setState(() {
      double x = pos.dx.clamp(0.0, 1.0);
      double y = pos.dy.clamp(0.0, 1.0);

      // (Optional) enforce ordering spacing here

      pts[idx] = Offset(x, y);
      if (locked && selectedChannel == 'Y') {
        for (var c in channels) {
          controlPoints[c]![idx] = Offset(x, y);
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
    final pts = controlPoints[selectedChannel]!;
    final idx = findNearbyControlPoint(pos, pts);

    if (idx != null && idx > 1) {
      setState(() {
        pts[idx] = const Offset(-1, -1);
        if (locked && selectedChannel == 'Y') {
          for (var c in channels) {
            controlPoints[c]![idx] = const Offset(-1, -1);
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