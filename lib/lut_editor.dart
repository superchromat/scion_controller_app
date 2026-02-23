import 'dart:math';
import 'dart:typed_data';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:osc/osc.dart';
import 'network.dart';
import 'monotonic_spline.dart';
import 'osc_widget_binding.dart';
import 'lut_painter.dart';
import 'osc_registry.dart';
import 'osc_log.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';

enum _GradeParam { shadowLevel, shadowBlend, midLevel, midBlend }


/// A LUT editor widget with two-way OSC binding per channel.
class LUTEditor extends StatefulWidget {
  /// Maximum number of control points per channel (including placeholders).
  final int maxControlPoints;
  /// Optional grade base path (e.g., "/send/1/grade") for level/blend lines UI.
  final String? gradePath;

  const LUTEditor({super.key, this.maxControlPoints = 16, this.gradePath});

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
  int? _activePointer;
  Timer? _longPressTimer;
  Offset? _pointerDownLocalPosition;
  bool _longPressTriggered = false;

  final ValueNotifier<bool> flashLockNotifier = ValueNotifier(false);
  static const double insetPadding = 20.0;
  static const double _minGap = 0.01;

  // Grade boundary values (level/upper & blend) for shadows and midtones
  double _shadowLevel = 0.25;
  double _shadowBlend = 0.1;
  double _midLevel = 0.75;
  double _midBlend = 0.1;
  GradeHandle? _activeGradeHandle;

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
  void dispose() {
    _cancelLongPressTracking();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      final registry = OscRegistry();

      // Register base address
      registry.registerAddress(oscAddress);

      // Grade endpoints (optional)
      if (widget.gradePath != null) {
        for (final path in [
          '${widget.gradePath}/shadows/level',
          '${widget.gradePath}/shadows/blend',
          '${widget.gradePath}/midtones/level',
          '${widget.gradePath}/midtones/blend',
        ]) {
          registry.registerAddress(path);
        }
        registry.registerListener('${widget.gradePath}/shadows/level',
            (args) => _updateGradeFromOsc(_GradeParam.shadowLevel, args));
        registry.registerListener('${widget.gradePath}/shadows/blend',
            (args) => _updateGradeFromOsc(_GradeParam.shadowBlend, args));
        registry.registerListener('${widget.gradePath}/midtones/level',
            (args) => _updateGradeFromOsc(_GradeParam.midLevel, args));
        registry.registerListener('${widget.gradePath}/midtones/blend',
            (args) => _updateGradeFromOsc(_GradeParam.midBlend, args));
      }

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

  void _beginInteractionAt(
    Offset localPosition,
    Size size, {
    required bool startDrag,
  }) {
    final pos = _normalize(localPosition, size);
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
      isDragging = startDrag;
    });
    _rebuildSplines();
    _sendCurrentChannel();
  }

  void onPanStart(DragStartDetails details, Size size) {
    if (_tryStartGradeDrag(details.localPosition, size)) return;
    _beginInteractionAt(details.localPosition, size, startDrag: true);
  }

  void onPanUpdate(DragUpdateDetails details, Size size) {
    if (_activeGradeHandle != null) {
      _updateGradeDrag(details.localPosition, size);
    } else {
      _updateInteractionAt(details.localPosition, size);
    }
  }

  void _updateInteractionAt(Offset localPosition, Size size) {
    if (!isDragging || currentControlPointIdx == null) return;
    final pos = _normalize(localPosition, size);
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
    if (_activeGradeHandle != null) {
      _activeGradeHandle = null;
    } else {
      _endInteraction();
    }
  }

  void _endInteraction() {
    _cancelLongPressTracking();
    setState(() {
      isDragging = false;
      currentControlPointIdx = null;
    });
    _activePointer = null;
  }

  void onTapDown(TapDownDetails details, Size size) {
    _beginInteractionAt(details.localPosition, size, startDrag: false);
  }

  void onTapUp(TapUpDetails _) {
    setState(() {
      isDragging = false;
      currentControlPointIdx = null;
    });
    _activePointer = null;
  }

  void onTapCancel() {
    if (isDragging) return;
    setState(() {
      isDragging = false;
      currentControlPointIdx = null;
    });
    _activePointer = null;
  }

  void _deletePointAt(Offset localPosition, Size size) {
    final pos = _normalize(localPosition, size);
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

  void _startLongPressTracking(Offset localPosition, Size size) {
    _cancelLongPressTracking();
    _pointerDownLocalPosition = localPosition;
    _longPressTriggered = false;
    _longPressTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _activePointer == null || _pointerDownLocalPosition == null) {
        return;
      }
      _longPressTriggered = true;
      _deletePointAt(_pointerDownLocalPosition!, size);
    });
  }

  void _updateLongPressTracking(Offset localPosition) {
    final start = _pointerDownLocalPosition;
    if (start == null || _longPressTriggered) return;
    if ((localPosition - start).distance > 10) {
      _cancelLongPressTracking();
    }
  }

  void _cancelLongPressTracking() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _pointerDownLocalPosition = null;
  }

  // --- Grade handles interaction ------------------------------------------------
  bool _startNearestGradeDrag(Offset localPos, Size size) {
    if (widget.gradePath == null) return false;
    final w = size.width - 2 * insetPadding;
    final candidates = <({double xNorm, GradeHandle handle})>[
      (xNorm: _shadowLevel, handle: GradeHandle.shadowCenter),
      (xNorm: (_shadowLevel - _shadowBlend).clamp(0.0, 1.0), handle: GradeHandle.shadowBlendLeft),
      (xNorm: (_shadowLevel + _shadowBlend).clamp(0.0, 1.0), handle: GradeHandle.shadowBlendRight),
      (xNorm: _midLevel, handle: GradeHandle.midCenter),
      (xNorm: (_midLevel - _midBlend).clamp(0.0, 1.0), handle: GradeHandle.midBlendLeft),
      (xNorm: (_midLevel + _midBlend).clamp(0.0, 1.0), handle: GradeHandle.midBlendRight),
    ];
    final targetX = (localPos.dx - insetPadding).clamp(0.0, w);
    candidates.sort((a, b) =>
        ((a.xNorm * w) - targetX).abs().compareTo(((b.xNorm * w) - targetX).abs()));
    _activeGradeHandle = candidates.first.handle;
    _updateGradeDrag(localPos, size);
    return true;
  }

  bool _tryStartGradeDrag(Offset localPos, Size size) {
    if (widget.gradePath == null) return false;
    final handle = _hitGradeHandle(localPos, size);
    if (handle == null) return false;
    _activeGradeHandle = handle;
    _updateGradeDrag(localPos, size);
    return true;
  }

  GradeHandle? _hitGradeHandle(Offset pos, Size size) {
    if (widget.gradePath == null) return null;
    final w = size.width - 2 * insetPadding;
    const handleHeight = 28.0;
    final hitTop = size.height - insetPadding - handleHeight;
    const bottomBand = 80.0; // generous catch zone near the flags
    final plotBottom = size.height - insetPadding;

    GradeHandle? _check(double xNorm, GradeHandle h) {
      final x = insetPadding + xNorm * w;
      final dx = (pos.dx - x).abs();
      final inBottomBand =
          pos.dy >= hitTop - bottomBand && pos.dy <= size.height - insetPadding + 8;

      // Only allow hits near the bottom handles; clicks on the line elsewhere fall through.
      if (inBottomBand && dx <= 28) return h; // big, easy hit on flags
      return null;
    }

    // Only respond to hits below the plot area (i.e., below y=0 line).
    if (pos.dy < plotBottom) return null;

    // Shadows
    final sL = _shadowLevel;
    final sB = _shadowBlend;
    final mL = _midLevel;
    final mB = _midBlend;

    for (final candidate in [
      _check(sL, GradeHandle.shadowCenter),
      _check((sL - sB).clamp(0.0, 1.0), GradeHandle.shadowBlendLeft),
      _check((sL + sB).clamp(0.0, 1.0), GradeHandle.shadowBlendRight),
      _check(mL, GradeHandle.midCenter),
      _check((mL - mB).clamp(0.0, 1.0), GradeHandle.midBlendLeft),
      _check((mL + mB).clamp(0.0, 1.0), GradeHandle.midBlendRight),
    ]) {
      if (candidate != null) return candidate;
    }
    return null;
  }

  void _updateGradeDrag(Offset localPos, Size size) {
    if (_activeGradeHandle == null) return;
    final w = size.width - 2 * insetPadding;
    final xNorm = ((localPos.dx - insetPadding) / w).clamp(0.0, 1.0);

    setState(() {
      switch (_activeGradeHandle!) {
        case GradeHandle.shadowCenter:
          _shadowLevel = xNorm.clamp(0.0, _midLevel - _minGap);
          _shadowBlend = _shadowBlend.clamp(0.0, _maxShadowBlend());
          _sendGradeValue('shadows/level', _shadowLevel);
          _sendGradeValue('shadows/blend', _shadowBlend);
          break;
        case GradeHandle.shadowBlendLeft:
        case GradeHandle.shadowBlendRight:
          final newBlend = (xNorm - _shadowLevel).abs();
          _shadowBlend = newBlend.clamp(0.0, _maxShadowBlend());
          _sendGradeValue('shadows/blend', _shadowBlend);
          break;
        case GradeHandle.midCenter:
          _midLevel = xNorm.clamp(_shadowLevel + _minGap, 1.0);
          _midBlend = _midBlend.clamp(0.0, _maxMidBlend());
          _sendGradeValue('midtones/level', _midLevel);
          _sendGradeValue('midtones/blend', _midBlend);
          break;
        case GradeHandle.midBlendLeft:
        case GradeHandle.midBlendRight:
          final newBlend = (xNorm - _midLevel).abs();
          _midBlend = newBlend.clamp(0.0, _maxMidBlend());
          _sendGradeValue('midtones/blend', _midBlend);
          break;
      }
    });
  }

  void _updateGradeFromOsc(_GradeParam param, List<Object?> args) {
    if (args.isEmpty || args.first is! num) return;
    final v = (args.first as num).toDouble();
    setState(() {
      switch (param) {
        case _GradeParam.shadowLevel:
          _shadowLevel = v.clamp(0.0, 1.0);
          _shadowLevel = min(_shadowLevel, _midLevel - _minGap);
          _shadowBlend = _shadowBlend.clamp(0.0, _maxShadowBlend());
          break;
        case _GradeParam.shadowBlend:
          _shadowBlend = v.clamp(0.0, _maxShadowBlend());
          break;
        case _GradeParam.midLevel:
          _midLevel = v.clamp(0.0, 1.0);
          _midLevel = max(_midLevel, _shadowLevel + _minGap);
          _midBlend = _midBlend.clamp(0.0, _maxMidBlend());
          break;
        case _GradeParam.midBlend:
          _midBlend = v.clamp(0.0, _maxMidBlend());
          break;
      }
    });
  }

  double _maxShadowBlend() {
    final a = _shadowLevel;
    final b = _midLevel - _shadowLevel - _minGap;
    final c = 1 - _shadowLevel;
    return max(0.0, min(a, min(b, c)));
  }

  double _maxMidBlend() {
    final a = _midLevel - _shadowLevel - _minGap;
    final b = 1 - _midLevel;
    final c = _midLevel;
    return max(0.0, min(a, min(b, c)));
  }

  void _sendGradeValue(String suffix, double v) {
    if (widget.gradePath == null) return;
    final path = '${widget.gradePath}/$suffix';
    final net = context.read<Network>();
    net.sendOscMessage(path, [v]);
    final reg = OscRegistry();
    reg.registerAddress(path);
    reg.dispatchLocal(path, [v]);
    oscLogKey.currentState?.logOscMessage(
      address: path,
      arg: [v],
      status: OscStatus.ok,
      direction: Direction.sent,
      binary: Uint8List(0),
    );
  }

  Widget _buildButton({
    required Widget child,
    required bool selected,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final lighting = context.watch<LightingSettings>();
    return _NeumorphicLutButton(
      lighting: lighting,
      selected: selected,
      accentColor: color,
      onPressed: onPressed,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(insetPadding, insetPadding, insetPadding, 0),
          child: Row(
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
                  color: flashing ? Colors.amber : Colors.white,
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
        )),
        const SizedBox(height: 5),
        Expanded(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return RawGestureDetector(
                behavior: HitTestBehavior.opaque,
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          EagerGestureRecognizer>(
                    () => EagerGestureRecognizer(),
                    (instance) {},
                  ),
                },
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (_activePointer != null) return;
                    _activePointer = event.pointer;
                    // Only if BELOW the plot (y > 0 line) do we grab grade handles.
                    final belowGraph =
                        event.localPosition.dy >= size.height - insetPadding;
                    if (belowGraph && _startNearestGradeDrag(event.localPosition, size)) return;
                    // Grade handles get first dibs; if hit, skip LUT point logic.
                    final consumed = _tryStartGradeDrag(event.localPosition, size);
                    if (consumed) return;
                    _startLongPressTracking(event.localPosition, size);
                    _beginInteractionAt(
                      event.localPosition,
                      size,
                      startDrag: true,
                    );
                  },
                  onPointerMove: (event) {
                    if (_activePointer != event.pointer) return;
                    if (_activeGradeHandle != null) {
                      _updateGradeDrag(event.localPosition, size);
                      return;
                    }
                    _updateLongPressTracking(event.localPosition);
                    _updateInteractionAt(event.localPosition, size);
                  },
                  onPointerUp: (event) {
                    if (_activePointer != event.pointer) return;
                    if (_activeGradeHandle != null) {
                      _activeGradeHandle = null;
                    } else {
                      _endInteraction();
                    }
                    _activePointer = null;
                  },
                  onPointerCancel: (event) {
                    if (_activePointer != event.pointer) return;
                    _activeGradeHandle = null;
                    _endInteraction();
                    _activePointer = null;
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    child: CustomPaint(
                      size: size,
                      painter: LUTPainter(
                        controlPoints: controlPoints,
                        splines: splines,
                        selectedChannel: selectedChannel,
                        highlightedIndex: currentControlPointIdx,
                        insetPadding: insetPadding,
                        gradeBands: widget.gradePath != null
                            ? [
                                GradeBand(
                                  center: _shadowLevel,
                                  blend: _shadowBlend,
                                  color: const Color(0xFFF0D86A),
                                ),
                                GradeBand(
                                  center: _midLevel,
                                  blend: _midBlend,
                                  color: const Color(0xFFF0D86A),
                                ),
                              ]
                            : const [],
                        activeHandle: _activeGradeHandle,
                      ),
                    ),
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

/// Neumorphic button for LUT editor controls.
class _NeumorphicLutButton extends StatefulWidget {
  final LightingSettings lighting;
  final bool selected;
  final Color? accentColor;
  final VoidCallback onPressed;
  final Widget child;

  const _NeumorphicLutButton({
    required this.lighting,
    required this.selected,
    this.accentColor,
    required this.onPressed,
    required this.child,
  });

  @override
  State<_NeumorphicLutButton> createState() => _NeumorphicLutButtonState();
}

class _NeumorphicLutButtonState extends State<_NeumorphicLutButton>
    with GlobalRectTracking<_NeumorphicLutButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isPressed = widget.selected || _isPressed;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          key: globalRectKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.lighting.createNeumorphicShadows(
              elevation: 3.0,
              inset: isPressed,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CustomPaint(
              painter: _LutButtonPainter(
                lighting: widget.lighting,
                isPressed: isPressed,
                isHovered: _isHovered,
                accentColor: widget.accentColor,
                selected: widget.selected,
                globalRect: trackedGlobalRect,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LutButtonPainter extends CustomPainter {
  final LightingSettings lighting;
  final bool isPressed;
  final bool isHovered;
  final Color? accentColor;
  final bool selected;
  final Rect? globalRect;

  _LutButtonPainter({
    required this.lighting,
    required this.isPressed,
    required this.isHovered,
    this.accentColor,
    required this.selected,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));

    // Base color - darker when pressed, accent tint when selected
    Color baseColor;
    if (selected && accentColor != null) {
      baseColor = Color.lerp(const Color(0xFF3A3A3C), accentColor!, 0.3)!;
    } else if (isPressed) {
      baseColor = const Color(0xFF2A2A2C);
    } else if (isHovered) {
      baseColor = const Color(0xFF424246);
    } else {
      baseColor = const Color(0xFF3A3A3C);
    }

    // Gradient fill with global position for Phong shading
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: isPressed ? 0.02 : 0.04,
      globalRect: globalRect,
    );
    final gradientPaint = Paint()..shader = gradient.createShader(rect);
    canvas.drawRRect(rrect, gradientPaint);

    // Edge highlight/shadow
    final light = lighting.lightDir2D;
    final edgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment(light.dx, light.dy),
        end: Alignment(-light.dx, -light.dy),
        colors: isPressed
            ? [
                Colors.black.withValues(alpha: 0.12),
                Colors.transparent,
                Colors.white.withValues(alpha: 0.02),
              ]
            : [
                Colors.white.withValues(alpha: 0.06),
                Colors.transparent,
                Colors.black.withValues(alpha: 0.1),
              ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rrect.deflate(0.5), edgePaint);

    // Accent color border when selected
    if (selected && accentColor != null) {
      final accentPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = accentColor!.withValues(alpha: 0.6);
      canvas.drawRRect(rrect.deflate(0.5), accentPaint);
    }

    // Noise texture
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ui.ImageShader(
          lighting.noiseImage!,
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = ui.BlendMode.overlay;

      canvas.save();
      canvas.clipRRect(rrect);
      canvas.drawRect(rect, noisePaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _LutButtonPainter oldDelegate) {
    return oldDelegate.isPressed != isPressed ||
        oldDelegate.isHovered != isHovered ||
        oldDelegate.selected != selected ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}
