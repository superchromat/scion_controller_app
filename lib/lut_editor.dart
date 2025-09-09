import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:osc/osc.dart';
import 'network.dart';
import 'monotonic_spline.dart';
import 'osc_widget_binding.dart';
import 'lut_painter.dart';
import 'osc_registry.dart';
import 'osc_log.dart';


/// A LUT editor widget with two-way OSC binding per channel.
class LUTEditor extends StatefulWidget {
  /// Maximum number of control points per channel (including placeholders).
  final int maxControlPoints;

  const LUTEditor({super.key, this.maxControlPoints = 16});

  @override
  State<LUTEditor> createState() => _LUTEditorState();
}

class _LUTEditorState extends State<LUTEditor> with OscAddressMixin<LUTEditor> {
  static const List<String> channels = ['Y', 'R', 'G', 'B'];
  static const double _eqEps = 1e-6;

  /// Control points per channel, fixed length with placeholders at (-1,-1).
  late final Map<String, List<Offset>> controlPoints;
  final Map<String, MonotonicSpline?> splines = {
    for (var c in channels) c: null,
  };

  bool locked = true;
  String selectedChannel = 'Y';
  int? currentControlPointIdx;
  bool isDragging = false;

  final ValueNotifier<bool> flashLockNotifier = ValueNotifier(false);
  static const double insetPadding = 20.0;

  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    // Initialize control points with placeholders
    controlPoints = {
      for (var c in channels)
        c: List<Offset>.generate(
          widget.maxControlPoints,
          (i) => i == 0
              ? const Offset(0, 0)
              : i == 1
                  ? const Offset(1, 1)
                  : const Offset(-1, -1),
        ),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      final registry = OscRegistry();

      // Register base address
      registry.registerAddress(oscAddress);

      // Setup incoming listeners, no network send on these
      for (var c in channels) {
        final path = '$oscAddress/$c';
        registry.registerAddress(path);
        registry.registerListener(path, (args) {
          if (isDragging) return; 

          final pts = controlPoints[c]!;
          for (var i = 0; i < pts.length; i++) {
            final idx = i * 2;
            if (idx + 1 < args.length) {
              pts[i] = Offset(
                (args[idx] as num).toDouble(),
                (args[idx + 1] as num).toDouble(),
              );
            } else {
              pts[i] = const Offset(-1, -1);
            }
          }
          // If all RGB LUTs are identical after this update, mirror to Y
          if (c != 'Y') {
            _maybeMirrorRgbToY();
          }
          _rebuildSplines();
          if (!OscRegistry().isLogSuppressed(path)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              oscLogKey.currentState?.logOscMessage(
                address: path,
                arg: args,
                status: OscStatus.ok,
                direction: Direction.received,
                binary: Uint8List(0),
              );
            });
          }
        });
      }

      // Initial build and one network send
      _rebuildSplines();
      _sendCurrentChannel();
    }
  }

  bool _offsetEq(Offset a, Offset b) {
    return (a.dx - b.dx).abs() <= _eqEps && (a.dy - b.dy).abs() <= _eqEps;
  }

  bool _listEq(List<Offset> a, List<Offset> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_offsetEq(a[i], b[i])) return false;
    }
    return true;
  }

  /// If R, G, and B are equal, copy that LUT into Y.
  void _maybeMirrorRgbToY() {
    final r = controlPoints['R']!;
    final g = controlPoints['G']!;
    final b = controlPoints['B']!;
    if (_listEq(r, g) && _listEq(g, b)) {
      // Replace Y with a copy so downstream equality checks don't alias
      controlPoints['Y'] = List<Offset>.from(r);
    }
  }

  /// Recompute splines without network send.
  void _rebuildSplines() {
    setState(() {
      for (var c in channels) {
        final active = controlPoints[c]!
            .where((pt) => pt.dx >= 0 && pt.dy >= 0)
            .toList()
          ..sort((a, b) => a.dx.compareTo(b.dx));
        // MonotonicSpline requires at least two points; if not available, skip.
        splines[c] = active.length >= 2 ? MonotonicSpline(active) : null;
      }
    });
  }

  /// Send current channel data over OSC network only.
  /// Note: Do not transmit the Y channel LUT over the network.
  /// When locked (and editing Y), mirror the curve to R/G/B and send only those.
  void _sendCurrentChannel() {
    // Determine channels to send (skip Y)
    if (selectedChannel == 'Y' && !locked) return;

    // Helper to flatten points for a channel
    List<Object> flatFor(String c) {
      final pts = List<Offset>.from(controlPoints[c]!);
      pts.sort((a, b) => a.dx.compareTo(b.dx));
      final active = pts.where((pt) => pt.dx >= 0 && pt.dy >= 0);
      return active.expand((pt) => [pt.dx, pt.dy]).toList();
    }

    if (locked && selectedChannel == 'Y') {
      // Bundle R,G,B into one OSC bundle for atomic apply on device
      final messages = <OSCMessage>[
        OSCMessage('$oscAddress/R', arguments: flatFor('R')),
        OSCMessage('$oscAddress/G', arguments: flatFor('G')),
        OSCMessage('$oscAddress/B', arguments: flatFor('B')),
      ];
      // Send via Network directly to ensure single datagram
      final net = context.read<Network>();
      net.sendOscBundle(messages);
    } else {
      // Single channel update
      final flat = flatFor(selectedChannel);
      sendOsc(flat, address: '$oscAddress/$selectedChannel');
    }
  }


  void resetControlPoints() {
    for (var c in channels) {
      final list = controlPoints[c]!;
      for (int i = 0; i < list.length; i++) {
        list[i] = i == 0
            ? const Offset(0, 0)
            : i == 1
                ? const Offset(1, 1)
                : const Offset(-1, -1);
      }
    }
    _rebuildSplines();
    _sendCurrentChannel();
  }

  int? _findUnusedIndex(List<Offset> pts) {
    final idx = pts.indexWhere((pt) => pt.dx < 0);
    return idx == -1 ? null : idx;
  }

  int? _findNearby(Offset pos, List<Offset> pts) {
    for (var i = 0; i < pts.length; i++) {
      final pt = pts[i];
      if (pt.dx < 0) continue;
      final dx = pt.dx - pos.dx;
      final dy = pt.dy - pos.dy;
      if (sqrt(dx * dx + dy * dy) < 0.05) return i;
    }
    return null;
  }

  Offset _normalize(Offset localPos, Size size) {
    final w = size.width - 2 * insetPadding;
    final h = size.height - 2 * insetPadding;
    return Offset(
      (localPos.dx - insetPadding) / w,
      1.0 - (localPos.dy - insetPadding) / h,
    );
  }

  void onPanStart(DragStartDetails details, Size size) {
    final pos = _normalize(details.localPosition, size);
    final pts = controlPoints[selectedChannel]!;
    final idx = _findNearby(pos, pts);
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
        }
      }
      isDragging = true;
    });
    _rebuildSplines();
    _sendCurrentChannel();
  }

  void onPanUpdate(DragUpdateDetails details, Size size) {
    if (!isDragging || currentControlPointIdx == null) return;
    final pos = _normalize(details.localPosition, size);
    setState(() {
      final idx = currentControlPointIdx!;
      final x = pos.dx.clamp(0.0, 1.0);
      final y = pos.dy.clamp(0.0, 1.0);
      controlPoints[selectedChannel]![idx] = Offset(x, y);
      if (locked && selectedChannel == 'Y') {
        for (var c in channels) {
          controlPoints[c]![idx] = Offset(x, y);
        }
      }
    });
    _rebuildSplines();
    _sendCurrentChannel();
  }

  void onPanEnd(DragEndDetails _) {
    setState(() {
      isDragging = false;
      currentControlPointIdx = null;
    });
  }

  void onLongPressStart(LongPressStartDetails details, Size size) {
    final pos = _normalize(details.localPosition, size);
    final pts = controlPoints[selectedChannel]!;
    final idx = _findNearby(pos, pts);
    if (idx != null && idx > 1) {
      setState(() {
        pts[idx] = const Offset(-1, -1);
        if (locked && selectedChannel == 'Y') {
          for (var c in channels) {
            controlPoints[c]![idx] = const Offset(-1, -1);
          }
        }
      });
      _rebuildSplines();
      _sendCurrentChannel();
    }
  }

  Widget _buildButton({
    required Widget child,
    required bool selected,
    required VoidCallback onPressed,
    Color? color,
  }) =>
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? (color ?? Colors.white) : null,
          side: BorderSide(color: (color ?? Colors.white)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onPressed: onPressed,
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            _buildButton(
              child: const Icon(Icons.refresh, color: Colors.white),
              selected: false,
              onPressed: resetControlPoints,
            ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: flashLockNotifier,
              builder: (_, flashing, __) => _buildButton(
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
                        controlPoints[c] = List.from(controlPoints['Y']!);
                      }
                      selectedChannel = 'Y';
                    }
                  });
                  _rebuildSplines();
                  _sendCurrentChannel();
                },
              ),
            ),
            const SizedBox(width: 8),
            for (var c in channels)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _buildButton(
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
                    } else {
                      setState(() => selectedChannel = c);
                      _rebuildSplines();
                      _sendCurrentChannel();
                    }
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) => onPanStart(d, size),
                onPanUpdate: (d) => onPanUpdate(d, size),
                onPanEnd: onPanEnd,
                onLongPressStart: (d) => onLongPressStart(d, size),
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
      ],
    );
  }
}
