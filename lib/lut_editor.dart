import 'dart:math';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'color_channels.dart';
import 'package:provider/provider.dart';
import 'package:osc/osc.dart';
import 'network.dart';
import 'monotonic_spline.dart';
import 'osc_widget_binding.dart';
import 'lut_painter.dart';
import 'osc_registry.dart';
import 'osc_log.dart';
import 'app_button.dart';
import 'oklch_color_picker.dart';
import 'rotary_knob.dart';
import 'grid.dart';

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

  // ── posterize overlay ───────────────────────────────────────────────────────
  // Regions are the vertical slabs between the Y-channel control points' output
  // (Y) values. Band attributes are indexed bottom→top; colour null = default
  // grayscale ramp so the column is legible before anything is set.
  bool _poster = false;
  final List<int> _bandType = List.filled(16, 7); // 7 = solid
  final List<int?> _bandColor = List.filled(16, null);
  int? _selBand;
  // Global zebra geometry (edited from the region dialog).
  int _zebraW = 2, _zebraRep = 10;

  // Zebra pattern dropdown: label → band type value.
  static const Map<String, int> _patterns = {
    'None (solid)': 7,
    'Zebra ↗': 1,
    'Zebra ↖': 2,
    'Zebra —': 3,
    'Zebra |': 4,
    'Original': 0,
  };

  List<double> get _posterTh => controlPoints['Y']!
      .where((p) => p.dx >= 0 && p.dy > 0 && p.dy < 1)
      .map((p) => p.dy)
      .toList()
    ..sort();

  List<int> _posterColors() {
    final n = _posterTh.length + 1;
    return List.generate(n, (b) {
      final c = _bandColor[b];
      if (c != null) return c;
      final g = (n <= 1) ? 255 : (b * 255 ~/ (n - 1));
      return (g << 16) | (g << 8) | g;
    });
  }

  List<int> _posterTypes() =>
      List.generate(_posterTh.length + 1, (b) => _bandType[b]);

  // Which region a column click landed in (0 = bottom band).
  void _onPosterColumnTap(Offset local, Size size) {
    final h = size.height - 2 * insetPadding;
    final ny = (1.0 - (local.dy - insetPadding) / h).clamp(0.0, 1.0);
    final bounds = <double>[0.0, ..._posterTh, 1.0];
    int band = bounds.length - 2;
    for (int b = 0; b < bounds.length - 1; b++) {
      if (ny <= bounds[b + 1]) {
        band = b;
        break;
      }
    }
    setState(() => _selBand = band);
    _openRegionDialog(band);
  }

  Future<void> _openRegionDialog(int band) async {
    await showDialog<void>(
      context: context,
      builder: (dctx) {
        final t = GridProvider.of(dctx);
        return StatefulBuilder(builder: (dctx, setD) {
          final rgb = _bandColor[band] ?? _posterColors()[band];
          final curColor = Color(0xFF000000 | rgb);
          final isZebra = _bandType[band] >= 1 && _bandType[band] <= 4;
          return AlertDialog(
            backgroundColor: const Color(0xFF1E1E22),
            title: Text('Region ${band + 1}', style: t.textHeading),
            content: SizedBox(
              width: 300,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                OklchColorPicker(
                  initialColor: curColor,
                  size: 150,
                  onColorChanged: (c) {
                    setState(() =>
                        _bandColor[band] = (c.r8 << 16) | (c.g8 << 8) | c.b8);
                    setD(() {});
                    _pushBand(band);
                  },
                ),
                SizedBox(height: t.md),
                Row(children: [
                  Text('Pattern', style: t.textLabel),
                  SizedBox(width: t.sm),
                  Expanded(
                    child: DropdownButton<int>(
                      value: _bandType[band],
                      isExpanded: true,
                      dropdownColor: const Color(0xFF2A2A2E),
                      style: t.textLabel.copyWith(color: Colors.white),
                      items: [
                        for (final e in _patterns.entries)
                          DropdownMenuItem(value: e.value, child: Text(e.key)),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _bandType[band] = v);
                        setD(() {});
                        _pushBand(band);
                      },
                    ),
                  ),
                ]),
                SizedBox(height: t.sm),
                // Global zebra geometry — only editable when this region uses a
                // zebra pattern; greyed out otherwise.
                IgnorePointer(
                  ignoring: !isZebra,
                  child: Opacity(
                    opacity: isZebra ? 1.0 : 0.35,
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _zebraKnob(
                              t,
                              'Width',
                              _zebraW.toDouble(),
                              0,
                              15,
                              (v) => setState(() {
                                    _zebraW = v.round();
                                    _pushZebra();
                                  })),
                          _zebraKnob(
                              t,
                              'Repeat',
                              _zebraRep.toDouble(),
                              0,
                              15,
                              (v) => setState(() {
                                    _zebraRep = v.round();
                                    _pushZebra();
                                  })),
                        ]),
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dctx),
                  child: const Text('Done')),
            ],
          );
        });
      },
    );
    if (mounted) setState(() => _selBand = null);
  }

  Widget _zebraKnob(GridTokens t, String label, double v, double min,
          double max, ValueChanged<double> onCh) =>
      RotaryKnob(
        label: label,
        minValue: min,
        maxValue: max,
        value: v,
        defaultValue: v,
        format: '%.0f',
        integerOnly: true,
        size: t.knobMd,
        labelStyle: t.textLabel,
        onChanged: onCh,
      );

  // ── posterize OSC (thresholds follow the control points) ────────────────────
  void _pushBand(int b) {
    final cols = _posterColors(), types = _posterTypes();
    if (b >= cols.length) return;
    context
        .read<Network>()
        .sendOscMessage('/send/1/color/poster/band', [b, types[b], cols[b]]);
  }

  void _pushZebra() {
    context
        .read<Network>()
        .sendOscMessage('/send/1/color/poster/zebra', [_zebraW, _zebraRep]);
  }

  // Presets (Gray N / Hue N / Contour N). Keeps existing control points and
  // adds the rest ON the current spline (so the curve shape is untouched) until
  // there are enough interior dividers for [nBands] regions, or the 16-point
  // budget runs out. Then colours each region by the preset's scheme.
  void _applyPreset(int nBands, int mode) {
    final pts = controlPoints['Y']!;
    final spline = splines['Y'];
    int interior() =>
        pts.where((p) => p.dx >= 0 && p.dy > 0 && p.dy < 1).length;
    final target = nBands - 1;
    final existingX = pts.where((p) => p.dx >= 0).map((p) => p.dx).toList();
    for (int k = 1; k <= target && interior() < target; k++) {
      final x = k / (target + 1);
      if (existingX.any((ex) => (ex - x).abs() < 0.02)) continue;
      final y = (spline?.evaluate(x) ?? x).clamp(0.0, 1.0);
      if (y <= 0 || y >= 1) continue;
      final slot = pts.indexWhere((p) => p.dx < 0);
      if (slot < 0) break;
      pts[slot] = Offset(x, y);
      if (locked) {
        for (final c in ['R', 'G', 'B']) {
          controlPoints[c]![slot] = Offset(x, y);
        }
      }
      existingX.add(x);
    }
    final n = _posterTh.length + 1;
    for (int b = 0; b < 16; b++) {
      final band = (b < n) ? b : n - 1;
      final lum = (n <= 1) ? 255 : band * 255 ~/ (n - 1);
      switch (mode) {
        case 0: // grayscale
          _bandType[b] = 7;
          _bandColor[b] = (lum << 16) | (lum << 8) | lum;
        case 1: // hue ramp
          _bandType[b] = 7;
          final h = band * 6 * 255 ~/ (n < 2 ? 2 : n);
          final seg = h ~/ 255, f = h % 255;
          int r = 0, g = 0, bl = 0;
          switch (seg) {
            case 0:
              r = 255;
              g = f;
            case 1:
              r = 255 - f;
              g = 255;
            case 2:
              g = 255;
              bl = f;
            case 3:
              g = 255 - f;
              bl = 255;
            case 4:
              r = f;
              bl = 255;
            default:
              r = 255;
              bl = 255 - f;
          }
          _bandColor[b] = (r << 16) | (g << 8) | bl;
        case 2: // contour (alternate solid / passthrough)
          _bandType[b] = band.isOdd ? 7 : 0;
          _bandColor[b] = 0xFFFFFF;
      }
    }
    setState(() {});
    _rebuildSplines();
    _sendCurrentChannel();
    _pushPoster();
  }

  void _pushPoster() {
    final net = context.read<Network>();
    // Band on luma: the regions come from the Y-channel LUT output, so the
    // hardware must threshold in YCbCr on the Y component.
    net.sendOscMessage('/send/1/color/poster/domain', [1]); // YCbCr
    net.sendOscMessage('/send/1/color/poster/comp', [1]); // Y (luma)
    final divs = _posterTh;
    for (int i = 0; i < 15; i++) {
      final v = (i < divs.length) ? (divs[i] * 255).round().clamp(0, 255) : 255;
      net.sendOscMessage('/send/1/color/poster/th', [i, v]);
    }
    final cols = _posterColors(), types = _posterTypes();
    for (int i = 0; i < 16; i++) {
      final col = (i < cols.length) ? cols[i] : cols.last;
      final ty = (i < types.length) ? types[i] : types.last;
      net.sendOscMessage('/send/1/color/poster/band', [i, ty, col]);
    }
    net.sendOscMessage('/send/1/color/poster/zebra', [_zebraW, _zebraRep]);
    net.sendOscMessage('/send/1/color/poster/enable', [_poster ? 1 : 0]);
  }

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

      // Posterize attributes (Send-1 global block). Thresholds follow the Y
      // control points (synced by the channel listeners above); these cover the
      // rest so a /sync repopulates the overlay from device state.
      for (final p in const [
        '/send/1/color/poster/enable',
        '/send/1/color/poster/band',
        '/send/1/color/poster/zebra',
      ]) {
        registry.registerAddress(p);
      }
      registry.registerListener('/send/1/color/poster/enable', (args) {
        if (!mounted || args.isEmpty || args[0] is! int) return;
        setState(() => _poster = (args[0] as int) != 0);
      });
      registry.registerListener('/send/1/color/poster/band', (args) {
        if (!mounted ||
            args.length < 3 ||
            args[0] is! int ||
            args[1] is! int ||
            args[2] is! int) {
          return;
        }
        final loc = args[0] as int;
        if (loc < 0 || loc >= 16) return;
        setState(() {
          _bandType[loc] = args[1] as int;
          _bandColor[loc] = (args[2] as int) & 0xFFFFFF;
        });
      });
      registry.registerListener('/send/1/color/poster/zebra', (args) {
        if (!mounted || args.length < 2 || args[0] is! int || args[1] is! int) {
          return;
        }
        setState(() {
          _zebraW = args[0] as int;
          _zebraRep = args[1] as int;
        });
      });

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
    // Reset grade lines to defaults if enabled
    setState(() {
      _shadowLevel = 0.25;
      _shadowBlend = 0.1;
      _midLevel = 0.75;
      _midBlend = 0.1;
    });
    if (widget.gradePath != null) {
      _sendGradeValue('shadows/level', _shadowLevel);
      _sendGradeValue('shadows/blend', _shadowBlend);
      _sendGradeValue('midtones/level', _midLevel);
      _sendGradeValue('midtones/blend', _midBlend);
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

  // Inner plot width — narrowed to match the painter when the posterize column
  // is shown, so screen↔normalized coordinates agree (hit-testing points).
  double _plotW(Size size) =>
      (size.width - 2 * insetPadding) * (_poster ? kPosterPlotFrac : 1.0);

  // True when a pointer is to the right of the curve area (the gap + column),
  // within its vertical band — those clicks must not add or move control points.
  bool _inPosterColumn(Offset local, Size size) {
    if (!_poster) return false;
    final plotRight =
        insetPadding + (size.width - 2 * insetPadding) * kPosterPlotFrac;
    final withinV =
        local.dy >= insetPadding && local.dy <= size.height - insetPadding;
    return withinV && local.dx > plotRight;
  }

  Offset _normalize(Offset localPos, Size size) {
    final w = _plotW(size);
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
    if (_poster) _pushPoster(); // thresholds moved with the point
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
      if (!mounted ||
          _activePointer == null ||
          _pointerDownLocalPosition == null) {
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
    final w = _plotW(size);
    final candidates = <({double xNorm, GradeHandle handle})>[
      (xNorm: _shadowLevel, handle: GradeHandle.shadowCenter),
      (
        xNorm: (_shadowLevel - _shadowBlend).clamp(0.0, 1.0),
        handle: GradeHandle.shadowBlendLeft
      ),
      (
        xNorm: (_shadowLevel + _shadowBlend).clamp(0.0, 1.0),
        handle: GradeHandle.shadowBlendRight
      ),
      (xNorm: _midLevel, handle: GradeHandle.midCenter),
      (
        xNorm: (_midLevel - _midBlend).clamp(0.0, 1.0),
        handle: GradeHandle.midBlendLeft
      ),
      (
        xNorm: (_midLevel + _midBlend).clamp(0.0, 1.0),
        handle: GradeHandle.midBlendRight
      ),
    ];
    final targetX = (localPos.dx - insetPadding).clamp(0.0, w);
    candidates.sort((a, b) => ((a.xNorm * w) - targetX)
        .abs()
        .compareTo(((b.xNorm * w) - targetX).abs()));
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
    final w = _plotW(size);
    const handleHeight = 28.0;
    final hitTop = size.height - insetPadding - handleHeight;
    const bottomBand = 80.0; // generous catch zone near the flags
    final plotBottom = size.height - insetPadding;

    GradeHandle? check(double xNorm, GradeHandle h) {
      final x = insetPadding + xNorm * w;
      final dx = (pos.dx - x).abs();
      final inBottomBand = pos.dy >= hitTop - bottomBand &&
          pos.dy <= size.height - insetPadding + 8;

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
      check(sL, GradeHandle.shadowCenter),
      check((sL - sB).clamp(0.0, 1.0), GradeHandle.shadowBlendLeft),
      check((sL + sB).clamp(0.0, 1.0), GradeHandle.shadowBlendRight),
      check(mL, GradeHandle.midCenter),
      check((mL - mB).clamp(0.0, 1.0), GradeHandle.midBlendLeft),
      check((mL + mB).clamp(0.0, 1.0), GradeHandle.midBlendRight),
    ]) {
      if (candidate != null) return candidate;
    }
    return null;
  }

  void _updateGradeDrag(Offset localPos, Size size) {
    if (_activeGradeHandle == null) return;
    final w = _plotW(size);
    final xNorm = ((localPos.dx - insetPadding) / w).clamp(0.0, 1.0);

    setState(() {
      switch (_activeGradeHandle!) {
        case GradeHandle.shadowCenter:
          _shadowLevel = xNorm.clamp(0.0, _midLevel - _minGap);
          _shadowBlend = _shadowBlend.clamp(0.0, 1.0);
          _sendGradeValue('shadows/level', _shadowLevel);
          _sendGradeValue('shadows/blend', _shadowBlend);
        case GradeHandle.shadowBlendLeft:
        case GradeHandle.shadowBlendRight:
          final newBlend = (xNorm - _shadowLevel).abs();
          _shadowBlend = newBlend.clamp(0.0, 1.0);
          _sendGradeValue('shadows/blend', _shadowBlend);
        case GradeHandle.midCenter:
          _midLevel = xNorm.clamp(_shadowLevel + _minGap, 1.0);
          _midBlend = _midBlend.clamp(0.0, 1.0);
          _sendGradeValue('midtones/level', _midLevel);
          _sendGradeValue('midtones/blend', _midBlend);
        case GradeHandle.midBlendLeft:
        case GradeHandle.midBlendRight:
          final newBlend = (xNorm - _midLevel).abs();
          _midBlend = newBlend.clamp(0.0, 1.0);
          _sendGradeValue('midtones/blend', _midBlend);
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
          _shadowBlend = _shadowBlend.clamp(0.0, 1.0);
        case _GradeParam.shadowBlend:
          _shadowBlend = v.clamp(0.0, 1.0);
        case _GradeParam.midLevel:
          _midLevel = v.clamp(0.0, 1.0);
          _midLevel = max(_midLevel, _shadowLevel + _minGap);
          _midBlend = _midBlend.clamp(0.0, 1.0);
        case _GradeParam.midBlend:
          _midBlend = v.clamp(0.0, 1.0);
      }
    });
  }

  void _sendGradeValue(String suffix, double v) {
    if (widget.gradePath == null) return;
    final path = '${widget.gradePath}/$suffix';
    final net = context.read<Network>();
    net.sendOscMessage(path, [v]); // Network logs the send centrally
    final reg = OscRegistry();
    reg.registerAddress(path);
    reg.dispatchLocal(path, [v]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(
                insetPadding, insetPadding, insetPadding, 0),
            child: Row(
              children: [
                AppButton(
                  icon: Icons.refresh,
                  dense: true,
                  onPressed: resetControlPoints,
                ),
                const Spacer(),
                ValueListenableBuilder<bool>(
                  valueListenable: flashLockNotifier,
                  builder: (_, flashing, __) => AppButton(
                    icon: locked ? Icons.lock : Icons.lock_open,
                    selected: locked,
                    dense: true,
                    accentColor: flashing ? Colors.amber : null,
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
                    child: AppButton(
                      label: c,
                      selected: selectedChannel == c,
                      dense: true,
                      accentColor: getChannelColor(c),
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
              return Stack(clipBehavior: Clip.none, children: [
                RawGestureDetector(
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
                      // Clicks in the posterize column/gap select a region (dialog
                      // wired next); they must never touch the LUT control points.
                      if (_inPosterColumn(event.localPosition, size)) {
                        _onPosterColumnTap(event.localPosition, size);
                        return;
                      }
                      // Only if BELOW the plot (y > 0 line) do we grab grade handles.
                      final belowGraph =
                          event.localPosition.dy >= size.height - insetPadding;
                      if (belowGraph &&
                          _startNearestGradeDrag(event.localPosition, size)) {
                        return;
                      }
                      // Grade handles get first dibs; if hit, skip LUT point logic.
                      final consumed =
                          _tryStartGradeDrag(event.localPosition, size);
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
                        setState(() {
                          _activeGradeHandle = null;
                        });
                      } else {
                        _endInteraction();
                      }
                      _activePointer = null;
                    },
                    onPointerCancel: (event) {
                      if (_activePointer != event.pointer) return;
                      setState(() {
                        _activeGradeHandle = null;
                      });
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
                          posterMode: _poster,
                          posterThresholds: _posterTh,
                          posterColors: _posterColors(),
                          posterTypes: _posterTypes(),
                          posterSelected: _selBand,
                          posterZebraWidth: _zebraW,
                          posterZebraRepeat: _zebraRep,
                        ),
                      ),
                    ),
                  ),
                ),
                _posterButton(),
              ]);
            },
          ),
        ),
      ],
    );
  }

  // Small reveal control tucked in the plot's bottom-right corner. (Scaffold:
  // a plain toggle; the press-drag preset dropdown comes next.)
  Widget _posterButton() {
    return Positioned(
      right: insetPadding + 6,
      bottom: insetPadding + 6,
      child: Container(
        decoration: BoxDecoration(
          color: _poster ? const Color(0xFFF0B830) : const Color(0xFF212124),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Tap the label to reveal/hide the column.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _poster = !_poster);
              _pushPoster();
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.view_column_outlined,
                    size: 15,
                    color: _poster ? Colors.black : const Color(0xFF9A9AA2)),
                const SizedBox(width: 5),
                Text('Posterize',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            _poster ? Colors.black : const Color(0xFF9A9AA2))),
              ]),
            ),
          ),
          // Caret: press-and-drag to pick a preset (Warp-style). The list
          // extends UP so it stays on-screen — the button sits at the bottom.
          _PresetDragButton(
            color: _poster ? Colors.black : const Color(0xFF9A9AA2),
            onPick: (n, mode) {
              if (!_poster) setState(() => _poster = true);
              _applyPreset(n, mode);
            },
          ),
        ]),
      ),
    );
  }
}

/// Press-and-drag preset picker (Warp-button style). The menu opens *upward*
/// from the trigger, so it stays on-screen when the trigger sits at the bottom
/// of the chart. Drag onto an item and release to pick.
class _PresetDragButton extends StatefulWidget {
  final void Function(int n, int mode) onPick;
  final Color color;
  const _PresetDragButton({required this.onPick, required this.color});

  @override
  State<_PresetDragButton> createState() => _PresetDragButtonState();
}

class _PresetDragButtonState extends State<_PresetDragButton> {
  static const List<({String label, int n, int mode})> _presets = [
    (label: 'Gray 6', n: 6, mode: 0),
    (label: 'Hue 8', n: 8, mode: 1),
    (label: 'Contour 8', n: 8, mode: 2),
    (label: 'Gray 16', n: 16, mode: 0),
  ];
  static const double _ih = 30, _menuW = 116;
  final _key = GlobalKey();
  OverlayEntry? _entry;
  int _hover = -1;
  Rect _menu = Rect.zero;

  void _open() {
    final box = _key.currentContext!.findRenderObject() as RenderBox;
    final tl = box.localToGlobal(Offset.zero);
    final menuH = _presets.length * _ih;
    _menu = Rect.fromLTWH(tl.dx + box.size.width - _menuW, tl.dy - menuH - 4,
        _menuW, menuH); // above the trigger
    _hover = -1;
    _entry = OverlayEntry(builder: (_) => _build());
    Overlay.of(context).insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    _hover = -1;
  }

  int _at(Offset g) {
    if (!_menu.inflate(8).contains(g)) return -1;
    final i = ((g.dy - _menu.top) / _ih).floor();
    return (i >= 0 && i < _presets.length) ? i : -1;
  }

  Widget _build() {
    return Positioned(
      left: _menu.left,
      top: _menu.top,
      width: _menu.width,
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45), blurRadius: 14),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (int i = 0; i < _presets.length; i++)
              Container(
                height: _ih,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color:
                    i == _hover ? const Color(0xFFF0B830) : Colors.transparent,
                child: Text(_presets[i].label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: i == _hover ? Colors.black : Colors.white)),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _open(),
      onPointerMove: (e) {
        final i = _at(e.position);
        if (i != _hover) {
          _hover = i;
          _entry?.markNeedsBuild();
        }
      },
      onPointerUp: (_) {
        if (_hover >= 0) {
          final p = _presets[_hover];
          widget.onPick(p.n, p.mode);
        }
        _close();
      },
      child: Container(
        key: _key,
        padding: const EdgeInsets.only(right: 4),
        child: Icon(Icons.arrow_drop_up, size: 18, color: widget.color),
      ),
    );
  }
}

/// Neumorphic button for LUT editor controls.
