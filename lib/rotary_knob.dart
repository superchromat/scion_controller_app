import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A segment for piecewise value mapping between normalized [0,1] and value space.
class MappingSegment {
  final double t0, t1; // normalized bounds
  final double v0, v1; // value bounds
  final double Function(double) curve; // monotonic mapping function

  const MappingSegment({
    required this.t0,
    required this.t1,
    required this.v0,
    required this.v1,
    required this.curve,
  });

  /// Linear mapping segment
  static MappingSegment linear({
    required double t0,
    required double t1,
    required double v0,
    required double v1,
  }) {
    return MappingSegment(
      t0: t0,
      t1: t1,
      v0: v0,
      v1: v1,
      curve: (t) => t,
    );
  }
}

/// Snap behavior modes
enum SnapBehavior {
  /// Locks exactly to snap point until hysteresis threshold exceeded
  hard,
  /// Biases toward snap point with smooth weighting
  soft,
}

/// Snap point configuration
class SnapConfig {
  final List<double> snapPoints;
  final double snapRegionHalfWidth;
  final double snapHysteresisMultiplier;
  final double snapAvoidanceSpeedThreshold;
  final int snapBriefHoldTimeMs;
  final SnapBehavior snapBehavior;

  /// Exponent for soft snap weight curve.
  /// - 1.0 = linear (strongest effect)
  /// - 2.0 = quadratic (default, moderate)
  /// - 3.0 = cubic (gentler, snappier at center)
  /// Lower values = stronger magnetic pull throughout the region
  final double softSnapExponent;

  const SnapConfig({
    this.snapPoints = const [],
    this.snapRegionHalfWidth = 0.05,
    this.snapHysteresisMultiplier = 1.5,
    this.snapAvoidanceSpeedThreshold = 0.25,  // normalized range per second (0.25 = 4 sec to traverse full range)
    this.snapBriefHoldTimeMs = 100,
    this.snapBehavior = SnapBehavior.hard,
    this.softSnapExponent = 2.0,
  });
}

/// Interaction states for the knob
enum _KnobState { idle, armed, dragging, settling }

/// A rotary knob with transient linear drag bar.
///
/// The rotary knob represents the current state compactly.
/// A transient horizontal bar provides an explicit, linear interaction surface.
/// Value changes are incremental and continuous, with no jumps.
class RotaryKnob extends StatefulWidget {
  /// Minimum value
  final double minValue;

  /// Maximum value
  final double maxValue;

  /// Current value
  final double value;

  /// Printf-style format string for displaying value
  final String format;

  /// Label text
  final String label;

  /// Default value (optional)
  final double? defaultValue;

  /// Whether this is a bipolar knob (has a meaningful center point)
  final bool isBipolar;

  /// Custom neutral value for bipolar display (defaults to 0 if isBipolar is true)
  /// The arc will be drawn from this value to the current value
  final double? neutralValue;

  /// Callback when value changes
  final ValueChanged<double>? onChanged;

  /// Snap configuration
  final SnapConfig snapConfig;

  /// Mapping segments for non-linear value mapping
  final List<MappingSegment>? mappingSegments;

  /// Size of the knob
  final double size;

  /// Width of the drag bar
  final double dragBarWidth;

  /// Light azimuthal angle in radians (0 = right, pi/2 = top)
  final double lightPhi;

  /// Light polar angle from vertical in radians (0 = above, pi/2 = horizontal)
  final double lightTheta;

  /// Arc/slot width in pixels
  final double arcWidth;

  /// Notch depth in pixels
  final double notchDepth;

  /// Notch half-width angle in radians (for arc notches)
  final double notchHalfAngle;

  const RotaryKnob({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.value,
    this.format = '%.2f',
    this.label = '',
    this.defaultValue,
    this.isBipolar = false,
    this.neutralValue,
    this.onChanged,
    this.snapConfig = const SnapConfig(),
    this.mappingSegments,
    this.size = 80,
    this.dragBarWidth = 400,
    this.lightPhi = math.pi / 2,    // Default: 90°
    this.lightTheta = 320 * math.pi / 180,  // Default: 320°
    this.arcWidth = 8.0,
    this.notchDepth = 4.0,
    this.notchHalfAngle = 0.055,    // ~3.15 degrees
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob>
    with SingleTickerProviderStateMixin {
  _KnobState _state = _KnobState.idle;

  // Static noise image shared by all knobs
  static ui.Image? _noiseImage;
  static bool _noiseImageLoading = false;

  // Drag tracking
  double _startValue = 0;
  double _startNormalized = 0;
  double _startMouseX = 0;
  DateTime _startTime = DateTime.now();
  double _currentValue = 0;

  // Snap state
  double? _snappedTo;
  DateTime? _snapTime;
  double _lastValue = 0;
  DateTime _lastUpdateTime = DateTime.now();

  // Overlay for drag bar and background
  OverlayEntry? _dragBarOverlay;
  final GlobalKey _knobKey = GlobalKey();

  // Animation for settling
  late AnimationController _settleController;
  late Animation<double> _settleAnimation;

  // Text editing state
  bool _isHovering = false;
  bool _isEditing = false;
  late TextEditingController _textController;
  late FocusNode _textFocusNode;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value.clamp(widget.minValue, widget.maxValue);
    _lastValue = _currentValue;

    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _textController = TextEditingController(text: _formatValue(_currentValue));
    _textFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelEditing();
          _textFocusNode.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    );
    _textFocusNode.addListener(_onFocusChange);

    // Generate noise image if not already done
    _generateNoiseImage();
  }

  Future<void> _generateNoiseImage() async {
    if (_noiseImage != null || _noiseImageLoading) return;
    _noiseImageLoading = true;

    const size = 256;
    final random = math.Random(12345);

    // Create raw RGBA pixel data for crisp noise
    final pixels = Uint8List(size * size * 4);
    for (int i = 0; i < size * size; i++) {
      final grey = 128 + random.nextInt(20);
      pixels[i * 4 + 0] = grey; // R
      pixels[i * 4 + 1] = grey; // G
      pixels[i * 4 + 2] = grey; // B
      pixels[i * 4 + 3] = 255; // A
    }

    // Decode raw pixels into image
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      size,
      size,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;

    if (mounted) {
      setState(() {
        _noiseImage = image;
      });
    } else {
      _noiseImage = image;
    }
    _noiseImageLoading = false;
  }

  @override
  void didUpdateWidget(RotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _state == _KnobState.idle) {
      _currentValue = widget.value.clamp(widget.minValue, widget.maxValue);
      if (!_isEditing) {
        _textController.text = _formatValue(_currentValue);
      }
    }
  }

  @override
  void dispose() {
    _removeDragBar();
    _settleController.dispose();
    _textFocusNode.removeListener(_onFocusChange);
    _textFocusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_textFocusNode.hasFocus) {
      // Gained focus - start editing, strip leading zeros
      if (!_isEditing) {
        final text = _textController.text;
        int start = 0;
        if (text.isNotEmpty && (text[0] == '+' || text[0] == '-')) {
          start = 1;
        }
        int zerosEnd = start;
        while (zerosEnd < text.length - 1 &&
               text[zerosEnd] == '0' &&
               text[zerosEnd + 1] != '.') {
          zerosEnd++;
        }
        final editText = text.substring(0, start) + text.substring(zerosEnd);
        _textController.text = editText;
        // Put cursor at end
        _textController.selection = TextSelection.collapsed(offset: editText.length);
        setState(() => _isEditing = true);
      }
    } else {
      // Lost focus - commit editing
      if (_isEditing) {
        _commitEditing();
      }
    }
  }

  void _commitEditing() {
    if (!_isEditing) return;
    final text = _textController.text.replaceAll(RegExp(r'[^\d.\-+]'), '');
    final parsed = double.tryParse(text);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.minValue, widget.maxValue);
      setState(() {
        _currentValue = clamped;
        _isEditing = false;
        _textController.text = _formatValue(_currentValue);
      });
      widget.onChanged?.call(_currentValue);
    } else {
      setState(() {
        _isEditing = false;
        _textController.text = _formatValue(_currentValue);
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _textController.text = _formatValue(_currentValue);
    });
  }

  int _getMaxInputLength() {
    // Determine max length based on format string and value range
    final format = widget.format;
    final match = RegExp(r'%[+]?(\d*)\.?(\d*)f').firstMatch(format);
    final precision = match != null ? int.tryParse(match.group(2) ?? '') ?? 2 : 2;

    // Calculate max integer digits needed
    final maxAbs = [widget.minValue.abs(), widget.maxValue.abs()]
        .reduce((a, b) => a > b ? a : b);
    final intDigits = maxAbs < 1 ? 1 : (maxAbs.floor().toString().length);

    // Total: sign + integer digits + decimal point + precision
    final needsSign = widget.minValue < 0;
    final hasDecimal = precision > 0;

    return (needsSign ? 1 : 0) + intDigits + (hasDecimal ? 1 : 0) + precision;
  }

  // Value mapping functions
  double _valueFromNormalized(double t) {
    t = t.clamp(0.0, 1.0);
    if (widget.mappingSegments != null && widget.mappingSegments!.isNotEmpty) {
      for (final seg in widget.mappingSegments!) {
        if (t >= seg.t0 && t <= seg.t1) {
          final localT = (t - seg.t0) / (seg.t1 - seg.t0);
          final curvedT = seg.curve(localT);
          return seg.v0 + curvedT * (seg.v1 - seg.v0);
        }
      }
    }
    // Default linear mapping
    return widget.minValue + t * (widget.maxValue - widget.minValue);
  }

  double _normalizedFromValue(double v) {
    v = v.clamp(widget.minValue, widget.maxValue);
    if (widget.mappingSegments != null && widget.mappingSegments!.isNotEmpty) {
      for (final seg in widget.mappingSegments!) {
        if (v >= seg.v0 && v <= seg.v1) {
          // Inverse of the curve - for linear curves this is straightforward
          final localV = (v - seg.v0) / (seg.v1 - seg.v0);
          // For non-linear curves, we'd need to invert the curve function
          // For now, assume linear
          return seg.t0 + localV * (seg.t1 - seg.t0);
        }
      }
    }
    // Default linear mapping
    return (v - widget.minValue) / (widget.maxValue - widget.minValue);
  }

  // Snapping logic
  double _applySnapping(double vProposed, {required bool bypassSnap}) {
    if (widget.snapConfig.snapPoints.isEmpty) return vProposed;
    if (bypassSnap) {
      _snappedTo = null;
      return vProposed;
    }

    // Find nearest snap point
    double? nearestSnap;
    double nearestDist = double.infinity;
    final direction = (vProposed - _lastValue).sign;

    for (final snap in widget.snapConfig.snapPoints) {
      final dist = (vProposed - snap).abs();
      if (dist < nearestDist ||
          (dist == nearestDist && (snap - _lastValue).sign == direction)) {
        nearestDist = dist;
        nearestSnap = snap;
      }
    }

    if (nearestSnap == null) return vProposed;

    // Check if we're in snap region
    final inSnapRegion = nearestDist <= widget.snapConfig.snapRegionHalfWidth;
    final behavior = widget.snapConfig.snapBehavior;

    // Hard snap: simple on/off behavior
    if (behavior == SnapBehavior.hard) {
      if (_snappedTo != null) {
        final releaseThreshold = widget.snapConfig.snapRegionHalfWidth *
            widget.snapConfig.snapHysteresisMultiplier;
        if ((vProposed - _snappedTo!).abs() > releaseThreshold) {
          _snappedTo = null;
        } else {
          return _snappedTo!;
        }
      }
      if (inSnapRegion) {
        _snappedTo = nearestSnap;
        return nearestSnap;
      }
      return vProposed;
    }

    // Soft snap: weighted pull toward snap point
    if (behavior == SnapBehavior.soft) {
      if (_snappedTo != null) {
        final releaseThreshold = widget.snapConfig.snapRegionHalfWidth *
            widget.snapConfig.snapHysteresisMultiplier;
        if ((vProposed - _snappedTo!).abs() > releaseThreshold) {
          _snappedTo = null;
        } else {
          return _softSnap(vProposed, _snappedTo!);
        }
      }
      if (inSnapRegion) {
        _snappedTo = nearestSnap;
        return _softSnap(vProposed, nearestSnap);
      }
      return vProposed;
    }

    return vProposed;
  }

  double _softSnap(double vProposed, double snapPoint) {
    // Bias toward snap point using smooth weighting
    final dist = (vProposed - snapPoint).abs();
    final weight = 1.0 -
        (dist / widget.snapConfig.snapRegionHalfWidth).clamp(0.0, 1.0);
    // Apply exponent: lower = stronger pull, higher = gentler
    final adjustedWeight = math.pow(weight, widget.snapConfig.softSnapExponent);
    return vProposed + (snapPoint - vProposed) * adjustedWeight;
  }

  /// Returns (prefix, mainValue) for display with different colors
  /// Prefix includes sign and leading zeros, main is the significant digits
  (String, String) _formatValueWithLeading(double value) {
    final format = widget.format;
    final match = RegExp(r'%(\+)?(\d*)\.?(\d*)f').firstMatch(format);
    final showPlus = match?.group(1) == '+';
    final precision = int.tryParse(match?.group(3) ?? '') ?? 2;

    // Calculate total width needed for integer part
    final maxAbsInt = [widget.minValue.abs(), widget.maxValue.abs()]
        .reduce((a, b) => a > b ? a : b)
        .truncate();
    final intDigits = maxAbsInt == 0 ? 1 : maxAbsInt.toString().length;

    // Format the number
    final formatted = value.toStringAsFixed(precision);
    final parts = formatted.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Handle sign
    final isNegative = intPart.startsWith('-');
    if (isNegative) {
      intPart = intPart.substring(1);
    }

    // Pad integer part with zeros
    final paddedInt = intPart.padLeft(intDigits, '0');

    // Find where leading zeros end
    int leadingZeroCount = 0;
    for (int i = 0; i < paddedInt.length - 1; i++) {
      if (paddedInt[i] == '0') {
        leadingZeroCount++;
      } else {
        break;
      }
    }

    // Build sign prefix (sign comes BEFORE leading zeros)
    final sign = isNegative ? '-' : (showPlus ? '+' : '');

    // Split into prefix (sign + leading zeros) and main value
    final leadingZeros = paddedInt.substring(0, leadingZeroCount);
    final mainInt = paddedInt.substring(leadingZeroCount);

    return ('$sign$leadingZeros', '$mainInt$decPart');
  }

  String _formatValue(double value) {
    final (leading, main) = _formatValueWithLeading(value);
    return '$leading$main';
  }

  double _measureTextWidth(String text, double fontSize) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: 'Courier',
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.width;
  }

  void _onPanStart(DragStartDetails details) {
    setState(() {
      _state = _KnobState.armed;
      _startValue = _currentValue;
      _startNormalized = _normalizedFromValue(_currentValue);
      _startMouseX = details.globalPosition.dx;
      _startTime = DateTime.now();
      _lastValue = _currentValue;
      _lastUpdateTime = DateTime.now();
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_state == _KnobState.idle) return;

    final dx = details.globalPosition.dx - _startMouseX;
    const dragThreshold = 3.0;

    if (_state == _KnobState.armed && dx.abs() > dragThreshold) {
      setState(() {
        _state = _KnobState.dragging;
      });
      _showDragBar();
    }

    if (_state == _KnobState.dragging) {
      final dt = dx / widget.dragBarWidth;
      final tProposed = (_startNormalized + dt).clamp(0.0, 1.0);
      final vProposed = _valueFromNormalized(tProposed);

      // Check if Ctrl key is held to bypass snapping
      final ctrlHeld = HardwareKeyboard.instance.logicalKeysPressed.any(
        (key) => key == LogicalKeyboardKey.controlLeft ||
                 key == LogicalKeyboardKey.controlRight,
      );

      final vFinal = _applySnapping(vProposed, bypassSnap: ctrlHeld);

      _lastValue = _currentValue;
      _lastUpdateTime = DateTime.now();

      setState(() {
        _currentValue = vFinal.clamp(widget.minValue, widget.maxValue);
      });

      widget.onChanged?.call(_currentValue);
      _updateDragBar();
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _removeDragBar();
    setState(() {
      _state = _KnobState.idle;
      _snappedTo = null;
      _textController.text = _formatValue(_currentValue);
    });
  }

  void _onDoubleTap() {
    if (widget.defaultValue != null) {
      setState(() {
        _currentValue =
            widget.defaultValue!.clamp(widget.minValue, widget.maxValue);
        _textController.text = _formatValue(_currentValue);
      });
      widget.onChanged?.call(_currentValue);
    }
  }

  void _showDragBar() {
    _removeDragBar();

    final overlay = Overlay.of(context);
    final RenderBox? renderBox =
        _knobKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final knobPosition = renderBox.localToGlobal(Offset.zero);
    final knobSize = renderBox.size;
    final screenSize = MediaQuery.of(context).size;

    // Calculate knob center position (knob is at top, label below)
    final knobCenterX = knobPosition.dx + knobSize.width / 2;
    final knobCenterY = knobPosition.dy + widget.size / 2;
    final knobRadius = widget.size / 2;

    // Calculate ideal position centered below the knob and label
    double barX = knobPosition.dx + knobSize.width / 2 - widget.dragBarWidth / 2;
    double barY = knobPosition.dy + knobSize.height + 4;

    // Clamp to viewport
    barX = barX.clamp(8.0, screenSize.width - widget.dragBarWidth - 8);

    // If not enough space below, try above
    final barHeight = 60.0;
    bool barBelow = true;
    if (barY + barHeight > screenSize.height) {
      barY = knobPosition.dy - barHeight - 4;
      barBelow = false;
    }
    barY = barY.clamp(8.0, screenSize.height - barHeight - 8);

    // Single overlay entry with background, knob copy, and drag bar all layered correctly
    _dragBarOverlay = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Background shape (bottom layer)
          _KnobDragBackground(
            knobCenterX: knobCenterX,
            knobCenterY: knobCenterY,
            knobRadius: knobRadius,
            barX: barX,
            barY: barY,
            barWidth: widget.dragBarWidth,
            barHeight: barHeight,
            barBelow: barBelow,
          ),
          // Knob visuals (middle layer) - positioned over the original knob
          Positioned(
            left: knobPosition.dx,
            top: knobPosition.dy,
            child: IgnorePointer(
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: knobSize.width,
                  height: knobSize.height,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Knob with centered value
                      SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: Size(widget.size, widget.size),
                              painter: _KnobPainter(
                                normalized: _normalizedFromValue(_currentValue),
                                isBipolar: widget.isBipolar,
                                neutralNormalized: widget.isBipolar
                                    ? _normalizedFromValue(widget.neutralValue ?? 0)
                                    : null,
                                isActive: true,
                                snapPoints: widget.snapConfig.snapPoints
                                    .map((v) => _normalizedFromValue(v))
                                    .toList(),
                                lightPhi: widget.lightPhi,
                                lightTheta: widget.lightTheta,
                                arcWidth: widget.arcWidth,
                                notchDepth: widget.notchDepth,
                                notchHalfAngle: widget.notchHalfAngle,
                                noiseImage: _noiseImage,
                              ),
                            ),
                            // Value display in knob center
                            Builder(
                              builder: (context) {
                                final (leading, main) = _formatValueWithLeading(_currentValue);
                                final fontSize = widget.size * 0.18;
                                return Text.rich(
                                  TextSpan(
                                    children: [
                                      if (leading.isNotEmpty)
                                        TextSpan(
                                          text: leading,
                                          style: TextStyle(
                                            fontSize: fontSize,
                                            fontFamily: 'Courier',
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey[600],
                                            decoration: TextDecoration.none,
                                          ),
                                        ),
                                      TextSpan(
                                        text: main,
                                        style: TextStyle(
                                          fontSize: fontSize,
                                          fontFamily: 'Courier',
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                          decoration: TextDecoration.none,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      // Label (below knob)
                      if (widget.label.isNotEmpty)
                        Transform.translate(
                          offset: const Offset(0, -4),
                          child: Text(
                            widget.label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Drag bar (top layer)
          Positioned(
            left: barX,
            top: barY,
            child: _DragBar(
              width: widget.dragBarWidth,
              value: _currentValue,
              minValue: widget.minValue,
              maxValue: widget.maxValue,
              normalizedValue: _normalizedFromValue(_currentValue),
              startNormalized: _startNormalized,
              isBipolar: widget.isBipolar,
              neutralValue: widget.neutralValue,
              format: widget.format,
              snapPoints: widget.snapConfig.snapPoints,
              lightPhi: widget.lightPhi,
              lightTheta: widget.lightTheta,
              noiseImage: _noiseImage,
            ),
          ),
        ],
      ),
    );

    overlay.insert(_dragBarOverlay!);
  }

  void _updateDragBar() {
    _dragBarOverlay?.markNeedsBuild();
  }

  void _removeDragBar() {
    _dragBarOverlay?.remove();
    _dragBarOverlay = null;
  }

  @override
  Widget build(BuildContext context) {
    final normalized = _normalizedFromValue(_currentValue);
    // Scale font size based on knob size
    final valueFontSize = widget.size * 0.14;

    return GestureDetector(
      key: _knobKey,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onDoubleTap: _onDoubleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Knob with centered value
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Knob arc
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _KnobPainter(
                    normalized: normalized,
                    isBipolar: widget.isBipolar,
                    neutralNormalized: widget.isBipolar
                        ? _normalizedFromValue(widget.neutralValue ?? 0)
                        : null,
                    isActive: _state != _KnobState.idle,
                    snapPoints: widget.snapConfig.snapPoints
                        .map((v) => _normalizedFromValue(v))
                        .toList(),
                    lightPhi: widget.lightPhi,
                    lightTheta: widget.lightTheta,
                    arcWidth: widget.arcWidth,
                    notchDepth: widget.notchDepth,
                    notchHalfAngle: widget.notchHalfAngle,
                    noiseImage: _noiseImage,
                  ),
                ),
                // Centered value display (editable)
                Builder(
                  builder: (context) {
                    final mainColor = _snappedTo != null
                        ? const Color(0xFFF0B830)
                        : Colors.grey[400]!;

                    // Border color: transparent normally, grey on hover, yellow on focus
                    Color borderColor;
                    if (_isEditing) {
                      borderColor = Colors.yellow;
                    } else if (_isHovering) {
                      borderColor = Colors.grey[600]!;
                    } else {
                      borderColor = Colors.transparent;
                    }

                    return MouseRegion(
                      cursor: SystemMouseCursors.text,
                      onEnter: (_) => setState(() => _isHovering = true),
                      onExit: (_) => setState(() => _isHovering = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          // Always have a border to prevent layout shift
                          border: Border.all(color: borderColor, width: 1),
                        ),
                        child: Builder(
                          builder: (context) {
                            // Fixed width based on formatted value (with leading zeros)
                            final fullText = _formatValue(_currentValue);
                            final charWidth = _measureTextWidth('0', valueFontSize);
                            final fixedWidth = charWidth * fullText.length;

                            final style = TextStyle(
                              fontSize: valueFontSize,
                              fontFamily: 'Courier',
                              fontFeatures: const [FontFeature.tabularFigures()],
                              fontWeight: FontWeight.normal,
                              letterSpacing: 0,
                              height: 1.0,
                            );

                            return SizedBox(
                              width: fixedWidth,
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.centerRight,
                                children: [
                                  // TextField - always present for interaction
                                  TextField(
                                    controller: _textController,
                                    focusNode: _textFocusNode,
                                    style: style.copyWith(
                                      color: _isEditing ? Colors.white : Colors.transparent,
                                    ),
                                    cursorColor: Colors.white,
                                    cursorWidth: 1.5,
                                    textAlign: TextAlign.right,
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      isCollapsed: true,
                                    ),
                                    keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.+\-]')),
                                      LengthLimitingTextInputFormatter(_getMaxInputLength()),
                                    ],
                                    onSubmitted: (_) => _commitEditing(),
                                  ),
                                  // Colored text overlay when not editing
                                  if (!_isEditing)
                                    IgnorePointer(
                                      child: Builder(
                                        builder: (context) {
                                          final text = _textController.text;
                                          int signEnd = 0;
                                          if (text.isNotEmpty && (text[0] == '+' || text[0] == '-')) {
                                            signEnd = 1;
                                          }
                                          int zerosEnd = signEnd;
                                          while (zerosEnd < text.length - 1 &&
                                                 text[zerosEnd] == '0' &&
                                                 zerosEnd + 1 < text.length &&
                                                 text[zerosEnd + 1] != '.') {
                                            zerosEnd++;
                                          }
                                          return RichText(
                                            textAlign: TextAlign.right,
                                            text: TextSpan(
                                              children: [
                                                if (signEnd > 0)
                                                  TextSpan(
                                                    text: text.substring(0, signEnd),
                                                    style: style.copyWith(color: mainColor),
                                                  ),
                                                if (zerosEnd > signEnd)
                                                  TextSpan(
                                                    text: text.substring(signEnd, zerosEnd),
                                                    style: style.copyWith(color: Colors.grey[700]),
                                                  ),
                                                TextSpan(
                                                  text: text.substring(zerosEnd),
                                                  style: style.copyWith(color: mainColor),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Label (below knob, larger white font)
          if (widget.label.isNotEmpty)
            Transform.translate(
              offset: const Offset(0, -4),
              child: Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Painter for the rotary knob
class _KnobPainter extends CustomPainter {
  final double normalized;
  final bool isBipolar;
  final double? neutralNormalized;
  final bool isActive;
  final List<double> snapPoints;
  final double lightPhi;   // Azimuthal angle in radians (0 = right, pi/2 = top)
  final double lightTheta; // Polar angle from vertical in radians (0 = above, pi/2 = horizontal)

  static const double startAngle = 0.75 * math.pi; // 135 degrees
  static const double sweepAngle = 1.5 * math.pi; // 270 degrees
  static const double deadZone = 0.25 * math.pi; // 45 degrees dead zone at bottom

  // Saturated amber for active state, bright white-ish for inactive
  static const Color _activeColor = Color(0xFFF0B830);  // Vivid amber/gold
  static const Color _inactiveColor = Color(0xFFE8E8E8);  // Brighter light grey

  _KnobPainter({
    required this.normalized,
    required this.isBipolar,
    this.neutralNormalized,
    required this.isActive,
    required this.snapPoints,
    this.lightPhi = math.pi / 2,
    this.lightTheta = 320 * math.pi / 180,
    this.arcWidth = 8.0,
    this.notchDepth = 4.0,
    this.notchHalfAngle = 0.055,
    this.noiseImage,
  });

  final double arcWidth;
  final double notchDepth;
  final double notchHalfAngle;
  final ui.Image? noiseImage;

  /// Compute 2D light direction from spherical coordinates
  /// Returns (Lx, Ly) where positive Ly is down (screen coords)
  Offset get lightDir2D {
    final lx = math.sin(lightTheta) * math.cos(lightPhi);
    final ly = -math.sin(lightTheta) * math.sin(lightPhi); // Negative because screen Y is down
    return Offset(lx, ly);
  }

  /// Compute edge brightness from normal direction
  double edgeBrightness(Offset normal) {
    final light = lightDir2D;
    final dot = normal.dx * light.dx + normal.dy * light.dy;
    return dot.clamp(0.0, 1.0);
  }

  /// Draw arc edge with piecewise lighting based on surface normals
  /// [canvas] - canvas to draw on
  /// [center] - center of the arc
  /// [radius] - radius of the arc
  /// [startAngle] - start angle in radians
  /// [sweepAngle] - sweep angle in radians
  /// [outward] - true if normal points outward (outer edge), false for inward (inner edge)
  /// [strokeWidth] - width of the edge highlight stroke
  /// [maxAlpha] - maximum alpha value for brightest highlights (0.0 to 1.0)
  void drawLitArcEdge(
    Canvas canvas,
    Offset center,
    double radius,
    double arcStartAngle,
    double arcSweepAngle,
    bool outward, {
    double strokeWidth = 0.75,
    double maxAlpha = 0.4,
    int segments = 24,
  }) {
    if (arcSweepAngle.abs() < 0.001) return;

    final segmentAngle = arcSweepAngle / segments;
    final light = lightDir2D;

    for (int i = 0; i < segments; i++) {
      final angle1 = arcStartAngle + i * segmentAngle;
      final angle2 = angle1 + segmentAngle;
      final midAngle = (angle1 + angle2) / 2;

      // Normal direction at this segment
      final normalX = outward ? math.cos(midAngle) : -math.cos(midAngle);
      final normalY = outward ? math.sin(midAngle) : -math.sin(midAngle);

      // Brightness from dot product
      final dot = normalX * light.dx + normalY * light.dy;
      final brightness = dot.clamp(0.0, 1.0);

      if (brightness > 0.05) {
        final alpha = (brightness * maxAlpha * 255).round();
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt
          ..color = Color.fromARGB(alpha, 255, 255, 255);

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          angle1,
          segmentAngle,
          false,
          paint,
        );
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 6;
    final slotWidth = arcWidth;
    final slotOuterRadius = radius + slotWidth / 2;
    final slotInnerRadius = radius - slotWidth / 2;
    final notchOuterRadius = slotOuterRadius + notchDepth;

    // === NEUMORPHIC SLOT (drawn normally, no clipping) ===
    const lightOffset = Alignment(0.0, -0.4);

    final borderGradient = RadialGradient(
      center: lightOffset,
      radius: 0.7,
      colors: const [Color(0xFF686868), Color(0xFF484848), Color(0xFF383838)],
      stops: const [0.0, 0.5, 1.0],
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth + 2
      ..strokeCap = StrokeCap.butt
      ..shader = borderGradient.createShader(
        Rect.fromCircle(center: center, radius: radius + arcWidth),
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false, borderPaint,
    );

    final outerShadowGradient = RadialGradient(
      center: const Alignment(0.0, 0.5),
      radius: 0.6,
      colors: const [Color(0xFF0C0C0C), Color(0xFF040404), Color(0x00000000)],
      stops: const [0.0, 0.3, 0.8],
    );
    final outerShadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.butt
      ..shader = outerShadowGradient.createShader(
        Rect.fromCircle(center: center, radius: radius + arcWidth / 2),
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius + arcWidth / 2 - 1),
      startAngle, sweepAngle, false, outerShadowPaint,
    );

    final innerHighlightGradient = RadialGradient(
      center: lightOffset,
      radius: 0.6,
      colors: const [Color(0xFF353535), Color(0xFF252525), Color(0x00000000)],
      stops: const [0.0, 0.2, 0.5],
    );
    final innerHighlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.butt
      ..shader = innerHighlightGradient.createShader(
        Rect.fromCircle(center: center, radius: radius - arcWidth / 2),
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - arcWidth / 2 + 1),
      startAngle, sweepAngle, false, innerHighlightPaint,
    );

    final floorGradient = RadialGradient(
      center: lightOffset,
      radius: 0.7,
      colors: const [Color(0xFF1C1C1C), Color(0xFF161616), Color(0xFF101010)],
      stops: const [0.0, 0.5, 1.0],
    );
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = floorGradient.createShader(
        Rect.fromCircle(center: center, radius: radius),
      );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle, sweepAngle, false, bgPaint,
    );

    // === SLOT EDGE LIGHTING ===
    // Outer edge of slot (normal points outward)
    drawLitArcEdge(
      canvas,
      center,
      slotOuterRadius,
      startAngle,
      sweepAngle,
      true,  // outward normal
      strokeWidth: 0.75,
      maxAlpha: 0.5,
    );

    // Inner edge of slot (normal points inward)
    drawLitArcEdge(
      canvas,
      center,
      slotInnerRadius,
      startAngle,
      sweepAngle,
      false,  // inward normal
      strokeWidth: 0.75,
      maxAlpha: 0.5,
    );

    // Notch base - slightly inside slot to cover seam
    final notchBaseRadius = slotOuterRadius - 1.5;

    // === VALUE ARC ===
    final baseColor = isActive ? _activeColor : _inactiveColor;

    // Calculate arc angular range
    double arcStartAngle, arcEndAngle;
    if (isBipolar && neutralNormalized != null) {
      final neutralAngle = startAngle + neutralNormalized! * sweepAngle;
      final valueAngle = startAngle + normalized * sweepAngle;
      arcStartAngle = math.min(neutralAngle, valueAngle);
      arcEndAngle = math.max(neutralAngle, valueAngle);
    } else {
      arcStartAngle = startAngle;
      arcEndAngle = startAngle + normalized * sweepAngle;
    }
    final arcSweep = arcEndAngle - arcStartAngle;

    // Create the value arc gradient (shared by slot and notches)
    // Use subtle darkening instead of transparency to avoid show-through
    final valueArcGradient = RadialGradient(
      center: lightOffset,
      radius: 0.8,
      colors: [
        baseColor,
        Color.lerp(baseColor, Colors.black, 0.10)!,
        Color.lerp(baseColor, Colors.black, 0.20)!,
      ],
      stops: const [0.0, 0.5, 1.0],
    );

    final highlightGradient = RadialGradient(
      center: const Alignment(0.0, -0.6),
      radius: 0.5,
      colors: [
        Colors.white.withOpacity(0.35),
        Colors.white.withOpacity(0.10),
        Colors.transparent,
      ],
      stops: const [0.0, 0.3, 0.7],
    );

    // Minimum arc width for visibility (about 6 degrees)
    const minArcSweep = 0.10;
    final valueAngle = startAngle + normalized * sweepAngle;

    // Calculate effective arc for drawing
    double drawArcStart = arcStartAngle;
    double drawArcSweep = arcSweep;

    if (arcSweep < minArcSweep) {
      // Center minimum arc on value position
      drawArcStart = valueAngle - minArcSweep / 2;
      drawArcSweep = minArcSweep;
    }

    // Draw value arc
    final valueArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = slotWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = valueArcGradient.createShader(
        Rect.fromCircle(center: center, radius: radius + slotWidth),
      );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      drawArcStart,
      drawArcSweep,
      false,
      valueArcPaint,
    );

    // Top highlight on the value arc
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = slotWidth - 2
      ..strokeCap = StrokeCap.butt
      ..shader = highlightGradient.createShader(
        Rect.fromCircle(center: center, radius: radius + slotWidth),
      );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      drawArcStart,
      drawArcSweep,
      false,
      highlightPaint,
    );

    // Grain/noise texture overlay on the value arc
    final halfSlot = (slotWidth - 2) / 2;
    if (noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      // Save canvas state and clip to value arc
      canvas.save();
      final arcPath = Path()
        ..addArc(
          Rect.fromCircle(center: center, radius: radius + halfSlot),
          drawArcStart,
          drawArcSweep,
        )
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius - halfSlot),
          drawArcStart + drawArcSweep,
          -drawArcSweep,
          false,
        )
        ..close();
      canvas.clipPath(arcPath);
      canvas.drawRect(
        Rect.fromCircle(center: center, radius: radius + slotWidth),
        noisePaint,
      );
      canvas.restore();
    }

    // === NOTCHES ===
    final lightDir = lightDir2D;

    for (final snapNorm in snapPoints) {
      final clampedNorm = snapNorm.clamp(0.0, 1.0);
      if ((snapNorm - clampedNorm).abs() > 0.001) continue;

      final snapAngle = startAngle + clampedNorm * sweepAngle;
      final leftAngle = snapAngle - notchHalfAngle;
      final rightAngle = snapAngle + notchHalfAngle;

      // Check if this notch is at the arc endpoints
      final atArcStart = clampedNorm < 0.001;
      final atArcEnd = clampedNorm > 0.999;

      final leftBase = Offset(
        center.dx + notchBaseRadius * math.cos(atArcStart ? startAngle : leftAngle),
        center.dy + notchBaseRadius * math.sin(atArcStart ? startAngle : leftAngle),
      );
      final rightBase = Offset(
        center.dx + notchBaseRadius * math.cos(atArcEnd ? (startAngle + sweepAngle) : rightAngle),
        center.dy + notchBaseRadius * math.sin(atArcEnd ? (startAngle + sweepAngle) : rightAngle),
      );
      final tip = Offset(
        center.dx + notchOuterRadius * math.cos(snapAngle),
        center.dy + notchOuterRadius * math.sin(snapAngle),
      );

      // Build notch path - half-V at endpoints, full V otherwise
      final notchPath = Path();
      if (atArcStart) {
        // Half-V at start: perpendicular left edge (radial), angled right edge
        final radialBase = Offset(
          center.dx + notchBaseRadius * math.cos(startAngle),
          center.dy + notchBaseRadius * math.sin(startAngle),
        );
        notchPath.moveTo(radialBase.dx, radialBase.dy);
        notchPath.lineTo(tip.dx, tip.dy);
        notchPath.lineTo(rightBase.dx, rightBase.dy);
        notchPath.close();
      } else if (atArcEnd) {
        // Half-V at end: angled left edge, perpendicular right edge (radial)
        final radialBase = Offset(
          center.dx + notchBaseRadius * math.cos(startAngle + sweepAngle),
          center.dy + notchBaseRadius * math.sin(startAngle + sweepAngle),
        );
        notchPath.moveTo(leftBase.dx, leftBase.dy);
        notchPath.lineTo(tip.dx, tip.dy);
        notchPath.lineTo(radialBase.dx, radialBase.dy);
        notchPath.close();
      } else {
        // Full V
        notchPath.moveTo(leftBase.dx, leftBase.dy);
        notchPath.lineTo(tip.dx, tip.dy);
        notchPath.lineTo(rightBase.dx, rightBase.dy);
        notchPath.close();
      }

      // Check if DRAWN value arc covers this notch (use effective draw bounds)
      final drawArcEnd = drawArcStart + drawArcSweep;
      final notchInArc = drawArcEnd > leftAngle && drawArcStart < rightAngle;

      if (notchInArc) {
        // Lit - fill with arc color
        canvas.save();
        canvas.clipPath(notchPath);

        final arcWedgePath = Path()
          ..moveTo(center.dx, center.dy)
          ..lineTo(
            center.dx + (notchOuterRadius + 10) * math.cos(drawArcStart),
            center.dy + (notchOuterRadius + 10) * math.sin(drawArcStart),
          )
          ..arcTo(
            Rect.fromCircle(center: center, radius: notchOuterRadius + 10),
            drawArcStart,
            drawArcSweep,
            false,
          )
          ..close();
        canvas.clipPath(arcWedgePath);

        final litPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = valueArcGradient.createShader(
            Rect.fromCircle(center: center, radius: notchOuterRadius),
          );
        canvas.drawPath(notchPath, litPaint);

        final litHighlightPaint = Paint()
          ..style = PaintingStyle.fill
          ..shader = highlightGradient.createShader(
            Rect.fromCircle(center: center, radius: notchOuterRadius),
          );
        canvas.drawPath(notchPath, litHighlightPaint);

        canvas.restore();
      } else {
        // Unlit - fill with dark color
        final darkPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = const Color(0xFF101010);
        canvas.drawPath(notchPath, darkPaint);
      }

      // === EDGE LIGHTING WITH DEPTH ===
      // Each edge gets both a highlight (facing light) and shadow (away from light)
      // to match the depth appearance of the arc slot
      final leftEdgeStart = Offset(
        center.dx + slotOuterRadius * math.cos(atArcStart ? startAngle : leftAngle),
        center.dy + slotOuterRadius * math.sin(atArcStart ? startAngle : leftAngle),
      );
      final rightEdgeEnd = Offset(
        center.dx + slotOuterRadius * math.cos(atArcEnd ? (startAngle + sweepAngle) : rightAngle),
        center.dy + slotOuterRadius * math.sin(atArcEnd ? (startAngle + sweepAngle) : rightAngle),
      );

      // Left edge
      if (!atArcStart) {
        final leftMidAngle = (leftAngle + snapAngle) / 2;
        final leftNormal = Offset(math.cos(leftMidAngle), math.sin(leftMidAngle));
        final leftDot = leftNormal.dx * lightDir.dx + leftNormal.dy * lightDir.dy;

        // Highlight on lit side
        if (leftDot > 0.05) {
          final leftAlpha = (0.5 * leftDot.clamp(0.0, 1.0) * 255).round();
          final leftPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.butt
            ..color = Color.fromARGB(leftAlpha, 255, 255, 255);
          canvas.drawLine(leftEdgeStart, tip, leftPaint);
        }
        // Shadow on dark side
        if (leftDot < -0.05) {
          final shadowAlpha = (0.4 * (-leftDot).clamp(0.0, 1.0) * 255).round();
          final shadowPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.butt
            ..color = Color.fromARGB(shadowAlpha, 0, 0, 0);
          canvas.drawLine(leftEdgeStart, tip, shadowPaint);
        }
      }

      // Right edge
      if (!atArcEnd) {
        final rightMidAngle = (snapAngle + rightAngle) / 2;
        final rightNormal = Offset(math.cos(rightMidAngle), math.sin(rightMidAngle));
        final rightDot = rightNormal.dx * lightDir.dx + rightNormal.dy * lightDir.dy;

        // Highlight on lit side
        if (rightDot > 0.05) {
          final rightAlpha = (0.5 * rightDot.clamp(0.0, 1.0) * 255).round();
          final rightPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..strokeCap = StrokeCap.butt
            ..color = Color.fromARGB(rightAlpha, 255, 255, 255);
          canvas.drawLine(tip, rightEdgeEnd, rightPaint);
        }
        // Shadow on dark side
        if (rightDot < -0.05) {
          final shadowAlpha = (0.4 * (-rightDot).clamp(0.0, 1.0) * 255).round();
          final shadowPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap = StrokeCap.butt
            ..color = Color.fromARGB(shadowAlpha, 0, 0, 0);
          canvas.drawLine(tip, rightEdgeEnd, shadowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalized != normalized ||
        oldDelegate.isBipolar != isBipolar ||
        oldDelegate.neutralNormalized != neutralNormalized ||
        oldDelegate.isActive != isActive ||
        oldDelegate.lightPhi != lightPhi ||
        oldDelegate.lightTheta != lightTheta ||
        oldDelegate.arcWidth != arcWidth ||
        oldDelegate.notchDepth != notchDepth ||
        oldDelegate.notchHalfAngle != notchHalfAngle;
  }
}

/// The transient horizontal drag bar
class _DragBar extends StatelessWidget {
  final double width;
  final double value;
  final double minValue;
  final double maxValue;
  final double normalizedValue;
  final double startNormalized;
  final bool isBipolar;
  final double? neutralValue;
  final String format;
  final List<double> snapPoints;
  final double lightPhi;
  final double lightTheta;
  final ui.Image? noiseImage;

  const _DragBar({
    required this.width,
    required this.value,
    required this.minValue,
    required this.maxValue,
    required this.normalizedValue,
    required this.startNormalized,
    required this.isBipolar,
    this.neutralValue,
    required this.format,
    required this.snapPoints,
    this.lightPhi = math.pi / 2,
    this.lightTheta = 320 * math.pi / 180,
    this.noiseImage,
  });

  String _formatValue(double value) {
    // Printf-style format with fixed-width output for stable decimal alignment
    final match = RegExp(r'%(\+)?(\d*)\.?(\d*)f').firstMatch(format);
    final showPlus = match?.group(1) == '+';
    final precision = int.tryParse(match?.group(3) ?? '') ?? 2;

    // Calculate total width needed for integer part + sign
    final maxAbsInt = [minValue.abs(), maxValue.abs()]
        .reduce((a, b) => a > b ? a : b)
        .truncate();
    final intDigits = maxAbsInt == 0 ? 1 : maxAbsInt.toString().length;
    final needsSign = minValue < 0 || showPlus;
    final totalIntWidth = intDigits + (needsSign ? 1 : 0);

    // Format the number
    final formatted = value.toStringAsFixed(precision);
    final parts = formatted.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Handle sign
    final isNegative = intPart.startsWith('-');
    if (isNegative) {
      intPart = intPart.substring(1);
    }
    final sign = isNegative ? '-' : (showPlus ? '+' : '');

    // Combine sign and integer, then pad the whole thing on the left
    final signedInt = '$sign$intPart';
    final paddedSignedInt = signedInt.padLeft(totalIntWidth, ' ');

    return '$paddedSignedInt$decPart';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 0,
      borderRadius: BorderRadius.circular(8),
      color: const Color(0xFF535355),  // 25% darker than 50% lighter
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatValue(minValue),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
                Text(
                  _formatValue(maxValue),
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 16,
              child: CustomPaint(
                size: Size(width - 24, 16),
                painter: _DragBarPainter(
                  normalizedValue: normalizedValue,
                  startNormalized: startNormalized,
                  isBipolar: isBipolar,
                  neutralValue: neutralValue,
                  minValue: minValue,
                  maxValue: maxValue,
                  snapPoints: snapPoints,
                  lightPhi: lightPhi,
                  lightTheta: lightTheta,
                  noiseImage: noiseImage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter for the drag bar
class _DragBarPainter extends CustomPainter {
  final double normalizedValue;
  final double startNormalized;
  final bool isBipolar;
  final double? neutralValue;
  final double minValue;
  final double maxValue;
  final List<double> snapPoints;
  final double lightPhi;
  final double lightTheta;
  final ui.Image? noiseImage;

  // Same saturated amber as knob
  static const Color _activeColor = Color(0xFFF0B830);  // Vivid amber/gold

  _DragBarPainter({
    required this.normalizedValue,
    required this.startNormalized,
    required this.isBipolar,
    this.neutralValue,
    required this.minValue,
    required this.maxValue,
    required this.snapPoints,
    this.lightPhi = math.pi / 2,
    this.lightTheta = 320 * math.pi / 180,
    this.noiseImage,
  });

  /// Compute 2D light direction from spherical coordinates
  Offset get lightDir2D {
    final lx = math.sin(lightTheta) * math.cos(lightPhi);
    final ly = -math.sin(lightTheta) * math.sin(lightPhi);
    return Offset(lx, ly);
  }

  /// Compute edge brightness from normal direction
  double edgeBrightness(Offset normal) {
    final light = lightDir2D;
    final dot = normal.dx * light.dx + normal.dy * light.dy;
    return dot.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height;
    final barY = 0.0;
    final lightDir = lightDir2D;

    // Notch geometry constants
    const notchDepth = 4.0;
    const notchHalfWidth = 3.0;
    const cornerRadius = 1.5;

    // === BUILD COMBINED SLOT + NOTCHES PATH ===
    // This is the "cutout" shape - slot rectangle with V notches extending upward
    final combinedPath = Path();

    // Start with slot rectangle
    combinedPath.addRect(Rect.fromLTWH(0, barY, size.width, barHeight));

    // Add each notch as a separate shape (union)
    for (final snap in snapPoints) {
      final snapNorm = (snap - minValue) / (maxValue - minValue);
      if (snapNorm < 0 || snapNorm > 1) continue;

      final snapX = snapNorm * size.width;
      final leftBaseX = snapX - notchHalfWidth;
      final rightBaseX = snapX + notchHalfWidth;
      final tipY = barY - notchDepth;

      // Notch path with corner radii where it meets the slot top edge
      final notchPath = Path();
      // Start at left corner radius start point
      notchPath.moveTo(leftBaseX - cornerRadius, barY);
      // Corner radius at left junction
      notchPath.quadraticBezierTo(leftBaseX, barY, leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
      // Left edge to tip
      notchPath.lineTo(snapX, tipY);
      // Right edge from tip
      notchPath.lineTo(rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);
      // Corner radius at right junction
      notchPath.quadraticBezierTo(rightBaseX, barY, rightBaseX + cornerRadius, barY);
      notchPath.close();

      combinedPath.addPath(notchPath, Offset.zero);
    }

    // === LAYER 0: OUTER BORDER/LIP ===
    final borderGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF404040), Color(0xFF585858)],
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = borderGradient.createShader(
        Rect.fromLTWH(-1, barY - notchDepth - 1, size.width + 2, barHeight + notchDepth + 2),
      );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-1, barY - 1, size.width + 2, barHeight + 2),
        const Radius.circular(3),
      ),
      borderPaint,
    );

    // === LAYER 1: DARK FLOOR (fills combined slot + notches shape) ===
    final floorGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Color(0xFF141414), Color(0xFF1C1C1C)],
    );
    final floorPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = floorGradient.createShader(
        Rect.fromLTWH(0, barY - notchDepth, size.width, barHeight + notchDepth),
      );

    canvas.save();
    canvas.clipPath(combinedPath);
    canvas.drawRect(
      Rect.fromLTWH(0, barY - notchDepth, size.width, barHeight + notchDepth),
      floorPaint,
    );
    canvas.restore();

    // === LAYER 2: VALUE INDICATOR (clipped to combined shape) ===
    final valueX = normalizedValue * size.width;
    double valueLeft, valueWidth;
    if (isBipolar) {
      final neutral = neutralValue ?? 0;
      final neutralNorm = (neutral - minValue) / (maxValue - minValue);
      final neutralX = neutralNorm * size.width;
      valueLeft = math.min(valueX, neutralX);
      valueWidth = (valueX - neutralX).abs();
    } else {
      valueLeft = 0;
      valueWidth = valueX;
    }

    if (valueWidth > 0.5) {
      canvas.save();
      canvas.clipPath(combinedPath);

      // Value bar fill
      final valueGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _activeColor,
          Color.lerp(_activeColor, Colors.black, 0.15)!,
        ],
      );
      final valuePaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = valueGradient.createShader(
          Rect.fromLTWH(valueLeft, barY - notchDepth, valueWidth, barHeight + notchDepth),
        );

      canvas.drawRect(
        Rect.fromLTWH(valueLeft, barY - notchDepth, valueWidth, barHeight + notchDepth),
        valuePaint,
      );

      // Top highlight on value bar
      final highlightGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
      final highlightPaint = Paint()
        ..style = PaintingStyle.fill
        ..shader = highlightGradient.createShader(
          Rect.fromLTWH(valueLeft, barY - notchDepth, valueWidth, 3),
        );
      canvas.drawRect(
        Rect.fromLTWH(valueLeft, barY - notchDepth, valueWidth, 3),
        highlightPaint,
      );

      // Noise texture overlay
      if (noiseImage != null) {
        final noisePaint = Paint()
          ..shader = ImageShader(
            noiseImage!,
            TileMode.repeated,
            TileMode.repeated,
            Matrix4.identity().storage,
          )
          ..blendMode = BlendMode.overlay;

        canvas.drawRect(
          Rect.fromLTWH(valueLeft, barY - notchDepth, valueWidth, barHeight + notchDepth),
          noisePaint,
        );
      }

      canvas.restore();
    }

    // Neutral marker for bipolar
    if (isBipolar) {
      final neutral = neutralValue ?? 0;
      final neutralNorm = (neutral - minValue) / (maxValue - minValue);
      if (neutralNorm >= 0 && neutralNorm <= 1) {
        final neutralX = neutralNorm * size.width;
        final neutralPaint = Paint()
          ..color = Colors.grey[500]!
          ..strokeWidth = 2;
        canvas.drawLine(
          Offset(neutralX, barY - 2),
          Offset(neutralX, barY + barHeight + 2),
          neutralPaint,
        );
      }
    }

    // === LAYER 3: EDGE HIGHLIGHTS ===
    // Top edge of slot (between notches)
    final topEdgeBrightness = edgeBrightness(const Offset(0, -1));
    if (topEdgeBrightness > 0.05) {
      final topEdgeAlpha = (topEdgeBrightness * 0.5 * 255).round();
      final topEdgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = Color.fromARGB(topEdgeAlpha, 255, 255, 255);

      // Draw top edge segments between notches
      double lastX = 0;
      final sortedSnaps = snapPoints
          .map((s) => (s - minValue) / (maxValue - minValue))
          .where((n) => n >= 0 && n <= 1)
          .toList()
        ..sort();

      for (final snapNorm in sortedSnaps) {
        final snapX = snapNorm * size.width;
        final leftEdge = snapX - notchHalfWidth - cornerRadius;
        if (leftEdge > lastX) {
          canvas.drawLine(Offset(lastX, barY), Offset(leftEdge, barY), topEdgePaint);
        }
        lastX = snapX + notchHalfWidth + cornerRadius;
      }
      if (lastX < size.width) {
        canvas.drawLine(Offset(lastX, barY), Offset(size.width, barY), topEdgePaint);
      }
    }

    // Bottom edge of slot
    final bottomEdgeBrightness = edgeBrightness(const Offset(0, 1));
    if (bottomEdgeBrightness > 0.05) {
      final bottomEdgeAlpha = (bottomEdgeBrightness * 0.5 * 255).round();
      final bottomEdgePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = Color.fromARGB(bottomEdgeAlpha, 255, 255, 255);
      canvas.drawLine(
        Offset(0, barY + barHeight),
        Offset(size.width, barY + barHeight),
        bottomEdgePaint,
      );
    }

    // Notch edge highlights with corner fillets
    for (final snap in snapPoints) {
      final snapNorm = (snap - minValue) / (maxValue - minValue);
      if (snapNorm < 0 || snapNorm > 1) continue;

      // Check if at bar boundaries
      final atBarStart = snapNorm < 0.001;
      final atBarEnd = snapNorm > 0.999;

      final snapX = snapNorm * size.width;
      final leftBaseX = snapX - notchHalfWidth;
      final rightBaseX = snapX + notchHalfWidth;
      final tipY = barY - notchDepth;
      final tip = Offset(snapX, tipY);

      // Left edge: only draw if not at bar start
      if (!atBarStart) {
        final leftStart = Offset(leftBaseX + cornerRadius * 0.7, barY - cornerRadius * 0.7);
        final leftEdgeVec = Offset(tip.dx - leftStart.dx, tip.dy - leftStart.dy);
        final leftNorm = Offset(leftEdgeVec.dy, -leftEdgeVec.dx);
        final leftLen = math.sqrt(leftNorm.dx * leftNorm.dx + leftNorm.dy * leftNorm.dy);
        final leftUnit = Offset(leftNorm.dx / leftLen, leftNorm.dy / leftLen);

        final leftDot = (leftUnit.dx * lightDir.dx + leftUnit.dy * lightDir.dy).clamp(0.0, 1.0);
        final leftAlpha = (0.5 * leftDot * 255).round();

        if (leftAlpha > 5) {
          final leftPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.75
            ..strokeCap = StrokeCap.round
            ..color = Color.fromARGB(leftAlpha, 255, 255, 255);
          canvas.drawLine(leftStart, tip, leftPaint);

          // Left corner fillet
          final cornerPath = Path()
            ..moveTo(leftBaseX - cornerRadius, barY)
            ..quadraticBezierTo(leftBaseX, barY, leftStart.dx, leftStart.dy);
          canvas.drawPath(cornerPath, leftPaint);
        }
      }

      // Right edge: only draw if not at bar end
      if (!atBarEnd) {
        final rightEnd = Offset(rightBaseX - cornerRadius * 0.7, barY - cornerRadius * 0.7);
        final rightEdgeVec = Offset(rightEnd.dx - tip.dx, rightEnd.dy - tip.dy);
        final rightNorm = Offset(-rightEdgeVec.dy, rightEdgeVec.dx);
        final rightLen = math.sqrt(rightNorm.dx * rightNorm.dx + rightNorm.dy * rightNorm.dy);
        final rightUnit = Offset(rightNorm.dx / rightLen, rightNorm.dy / rightLen);

        final rightDot = (rightUnit.dx * lightDir.dx + rightUnit.dy * lightDir.dy).clamp(0.0, 1.0);
        final rightAlpha = (0.5 * rightDot * 255).round();

        if (rightAlpha > 5) {
          final rightPaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.75
            ..strokeCap = StrokeCap.round
            ..color = Color.fromARGB(rightAlpha, 255, 255, 255);
          canvas.drawLine(tip, rightEnd, rightPaint);

          // Right corner fillet
          final cornerPath = Path()
            ..moveTo(rightEnd.dx, rightEnd.dy)
            ..quadraticBezierTo(rightBaseX, barY, rightBaseX + cornerRadius, barY);
          canvas.drawPath(cornerPath, rightPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DragBarPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.startNormalized != startNormalized ||
        oldDelegate.lightPhi != lightPhi ||
        oldDelegate.lightTheta != lightTheta;
  }
}

/// Background shape that connects the knob circle to the drag bar
class _KnobDragBackground extends StatelessWidget {
  final double knobCenterX;
  final double knobCenterY;
  final double knobRadius;
  final double barX;
  final double barY;
  final double barWidth;
  final double barHeight;
  final bool barBelow;

  const _KnobDragBackground({
    required this.knobCenterX,
    required this.knobCenterY,
    required this.knobRadius,
    required this.barX,
    required this.barY,
    required this.barWidth,
    required this.barHeight,
    required this.barBelow,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        size: MediaQuery.of(context).size,
        painter: _KnobDragBackgroundPainter(
          knobCenterX: knobCenterX,
          knobCenterY: knobCenterY,
          knobRadius: knobRadius,
          barX: barX,
          barY: barY,
          barWidth: barWidth,
          barHeight: barHeight,
          barBelow: barBelow,
        ),
      ),
    );
  }
}

/// Painter for the combined knob circle + drag bar background shape
class _KnobDragBackgroundPainter extends CustomPainter {
  final double knobCenterX;
  final double knobCenterY;
  final double knobRadius;
  final double barX;
  final double barY;
  final double barWidth;
  final double barHeight;
  final bool barBelow;

  // Padding around the content
  static const double padding = 16.0;
  // Corner radius for the bar portion
  static const double cornerRadius = 20.0;
  // Fillet radius for inside corners where circle meets bar
  static const double filletRadius = 24.0;

  _KnobDragBackgroundPainter({
    required this.knobCenterX,
    required this.knobCenterY,
    required this.knobRadius,
    required this.barX,
    required this.barY,
    required this.barWidth,
    required this.barHeight,
    required this.barBelow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF5A5A5E)  // Light grey
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);

    // Expanded dimensions with padding
    final barLeft = barX - padding;
    final barRight = barX + barWidth + padding;
    final barTop = barY - padding;
    final barBottom = barY + barHeight + padding;

    // Circle radius should be large enough that the circle's diameter
    // extends to where it can smoothly connect to the bar with fillets
    // The circle's edge at its widest should be at the fillet connection points
    final circleRadius = knobRadius + padding + 8;  // Extra padding for the circle

    // Create the combined path
    final path = Path();

    if (barBelow) {
      _drawCircleWithBarBelow(path, circleRadius, barLeft, barRight, barTop, barBottom);
    } else {
      _drawCircleWithBarAbove(path, circleRadius, barLeft, barRight, barTop, barBottom);
    }

    // Draw shadow first (offset down and slightly larger blur)
    canvas.drawPath(path.shift(const Offset(0, 6)), shadowPaint);

    // Draw the shape
    canvas.drawPath(path, paint);

    // Draw thin white border for separation
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(path, borderPaint);
  }

  void _drawCircleWithBarBelow(Path path, double circleRadius,
      double barLeft, double barRight, double barTop, double barBottom) {

    // The connection points where circle meets the bar (at circle's diameter level)
    // These are at the circle's horizontal extremes
    final connectLeft = knobCenterX - circleRadius;
    final connectRight = knobCenterX + circleRadius;

    // Start at top of circle
    path.moveTo(knobCenterX, knobCenterY - circleRadius);

    // Draw right half of circle (top to right side at horizontal diameter)
    path.arcTo(
      Rect.fromCircle(center: Offset(knobCenterX, knobCenterY), radius: circleRadius),
      -math.pi / 2,
      math.pi / 2,
      false,
    );

    // Now at (knobCenterX + circleRadius, knobCenterY) - rightmost point
    // Draw fillet curve down and out to bar top
    path.quadraticBezierTo(
      connectRight, barTop,  // Control point - straight down then curve
      connectRight + filletRadius, barTop,  // End on bar top edge
    );

    // Bar top edge to right corner
    path.lineTo(barRight - cornerRadius, barTop);

    // Bar top-right corner
    path.arcTo(
      Rect.fromLTWH(barRight - cornerRadius * 2, barTop, cornerRadius * 2, cornerRadius * 2),
      -math.pi / 2,
      math.pi / 2,
      false,
    );

    // Bar right edge
    path.lineTo(barRight, barBottom - cornerRadius);

    // Bar bottom-right corner
    path.arcTo(
      Rect.fromLTWH(barRight - cornerRadius * 2, barBottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2),
      0,
      math.pi / 2,
      false,
    );

    // Bar bottom edge
    path.lineTo(barLeft + cornerRadius, barBottom);

    // Bar bottom-left corner
    path.arcTo(
      Rect.fromLTWH(barLeft, barBottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2),
      math.pi / 2,
      math.pi / 2,
      false,
    );

    // Bar left edge
    path.lineTo(barLeft, barTop + cornerRadius);

    // Bar top-left corner
    path.arcTo(
      Rect.fromLTWH(barLeft, barTop, cornerRadius * 2, cornerRadius * 2),
      math.pi,
      math.pi / 2,
      false,
    );

    // Bar top edge to left fillet
    path.lineTo(connectLeft - filletRadius, barTop);

    // Left fillet: curve up and in to circle's left edge
    path.quadraticBezierTo(
      connectLeft, barTop,  // Control point
      connectLeft, knobCenterY,  // End at circle's leftmost point
    );

    // Complete left half of circle back to top
    path.arcTo(
      Rect.fromCircle(center: Offset(knobCenterX, knobCenterY), radius: circleRadius),
      math.pi,
      math.pi / 2,
      false,
    );

    path.close();
  }

  void _drawCircleWithBarAbove(Path path, double circleRadius,
      double barLeft, double barRight, double barTop, double barBottom) {

    final connectLeft = knobCenterX - circleRadius;
    final connectRight = knobCenterX + circleRadius;

    // Start at bottom of circle
    path.moveTo(knobCenterX, knobCenterY + circleRadius);

    // Draw right half of circle (bottom to right side)
    path.arcTo(
      Rect.fromCircle(center: Offset(knobCenterX, knobCenterY), radius: circleRadius),
      math.pi / 2,
      -math.pi / 2,
      false,
    );

    // Fillet up to bar bottom
    path.quadraticBezierTo(
      connectRight, barBottom,
      connectRight + filletRadius, barBottom,
    );

    // Bar bottom edge to right
    path.lineTo(barRight - cornerRadius, barBottom);

    // Bar bottom-right corner
    path.arcTo(
      Rect.fromLTWH(barRight - cornerRadius * 2, barBottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2),
      math.pi / 2,
      -math.pi / 2,
      false,
    );

    // Bar right edge
    path.lineTo(barRight, barTop + cornerRadius);

    // Bar top-right corner
    path.arcTo(
      Rect.fromLTWH(barRight - cornerRadius * 2, barTop, cornerRadius * 2, cornerRadius * 2),
      0,
      -math.pi / 2,
      false,
    );

    // Bar top edge
    path.lineTo(barLeft + cornerRadius, barTop);

    // Bar top-left corner
    path.arcTo(
      Rect.fromLTWH(barLeft, barTop, cornerRadius * 2, cornerRadius * 2),
      -math.pi / 2,
      -math.pi / 2,
      false,
    );

    // Bar left edge
    path.lineTo(barLeft, barBottom - cornerRadius);

    // Bar bottom-left corner
    path.arcTo(
      Rect.fromLTWH(barLeft, barBottom - cornerRadius * 2, cornerRadius * 2, cornerRadius * 2),
      math.pi,
      -math.pi / 2,
      false,
    );

    // Left fillet
    path.lineTo(connectLeft - filletRadius, barBottom);
    path.quadraticBezierTo(
      connectLeft, barBottom,
      connectLeft, knobCenterY,
    );

    // Complete left half of circle
    path.arcTo(
      Rect.fromCircle(center: Offset(knobCenterX, knobCenterY), radius: circleRadius),
      math.pi,
      -math.pi / 2,
      false,
    );

    path.close();
  }

  @override
  bool shouldRepaint(covariant _KnobDragBackgroundPainter oldDelegate) {
    return oldDelegate.knobCenterX != knobCenterX ||
        oldDelegate.knobCenterY != knobCenterY ||
        oldDelegate.knobRadius != knobRadius ||
        oldDelegate.barX != barX ||
        oldDelegate.barY != barY ||
        oldDelegate.barWidth != barWidth ||
        oldDelegate.barHeight != barHeight;
  }
}
