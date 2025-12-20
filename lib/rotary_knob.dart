import 'dart:async';
import 'dart:math' as math;
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
enum SnapBehavior { hard, soft }

/// Snap point configuration
class SnapConfig {
  final List<double> snapPoints;
  final double snapRegionHalfWidth;
  final double snapHysteresisMultiplier;
  final double snapAvoidanceSpeedThreshold;
  final int snapBriefHoldTimeMs;
  final SnapBehavior snapBehavior;

  const SnapConfig({
    this.snapPoints = const [],
    this.snapRegionHalfWidth = 0.05,
    this.snapHysteresisMultiplier = 1.5,
    this.snapAvoidanceSpeedThreshold = 0.01,
    this.snapBriefHoldTimeMs = 100,
    this.snapBehavior = SnapBehavior.hard,
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
  });

  @override
  State<RotaryKnob> createState() => _RotaryKnobState();
}

class _RotaryKnobState extends State<RotaryKnob>
    with SingleTickerProviderStateMixin {
  _KnobState _state = _KnobState.idle;

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

    _textController = TextEditingController();
    _textFocusNode = FocusNode();
    _textFocusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(RotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _state == _KnobState.idle) {
      _currentValue = widget.value.clamp(widget.minValue, widget.maxValue);
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
    if (!_textFocusNode.hasFocus && _isEditing) {
      _commitEditing();
    }
  }

  void _startEditing() {
    if (_isEditing) return;
    setState(() {
      _isEditing = true;
      _textController.text = _formatValue(_currentValue);
      _textController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _textController.text.length,
      );
    });
    _textFocusNode.requestFocus();
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
      });
      widget.onChanged?.call(_currentValue);
    } else {
      setState(() {
        _isEditing = false;
      });
    }
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
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
  double _applySnapping(double vProposed, double speed) {
    if (widget.snapConfig.snapPoints.isEmpty) return vProposed;

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

    // Snap avoidance - slow motion bypasses snapping
    if (speed < widget.snapConfig.snapAvoidanceSpeedThreshold) {
      _snappedTo = null;
      return vProposed;
    }

    // Hysteresis logic
    if (_snappedTo != null) {
      final releaseThreshold = widget.snapConfig.snapRegionHalfWidth *
          widget.snapConfig.snapHysteresisMultiplier;
      if ((vProposed - _snappedTo!).abs() > releaseThreshold) {
        _snappedTo = null;
      } else {
        // Still snapped
        return widget.snapConfig.snapBehavior == SnapBehavior.hard
            ? _snappedTo!
            : _softSnap(vProposed, _snappedTo!);
      }
    }

    // Capture condition
    if (inSnapRegion) {
      _snappedTo = nearestSnap;
      _snapTime = DateTime.now();
      return widget.snapConfig.snapBehavior == SnapBehavior.hard
          ? nearestSnap
          : _softSnap(vProposed, nearestSnap);
    }

    return vProposed;
  }

  double _softSnap(double vProposed, double snapPoint) {
    // Bias toward snap point using smooth weighting
    final dist = (vProposed - snapPoint).abs();
    final weight = 1.0 -
        (dist / widget.snapConfig.snapRegionHalfWidth).clamp(0.0, 1.0);
    return vProposed + (snapPoint - vProposed) * weight * weight;
  }

  String _formatValue(double value) {
    // Printf-style format with fixed-width output for stable decimal alignment
    final format = widget.format;
    final match = RegExp(r'%(\+)?(\d*)\.?(\d*)f').firstMatch(format);
    final showPlus = match?.group(1) == '+';
    final precision = int.tryParse(match?.group(3) ?? '') ?? 2;

    // Calculate width needed for integer part based on value range
    final maxAbsInt = [widget.minValue.abs(), widget.maxValue.abs()]
        .reduce((a, b) => a > b ? a : b)
        .truncate();
    final intWidth = maxAbsInt == 0 ? 1 : maxAbsInt.toString().length;

    // Format the number
    final formatted = value.toStringAsFixed(precision);
    final parts = formatted.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Handle sign and padding
    final isNegative = intPart.startsWith('-');
    if (isNegative) {
      intPart = intPart.substring(1);
    }

    // Pad integer part to consistent width
    intPart = intPart.padLeft(intWidth, ' ');

    // Add sign (or space for positive if range includes negatives or showPlus)
    final needsSignSpace = widget.minValue < 0 || showPlus;
    final sign = isNegative ? '-' : (showPlus ? '+' : (needsSignSpace ? ' ' : ''));

    return '$sign$intPart$decPart';
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

      // Calculate speed for snap avoidance
      final now = DateTime.now();
      final timeDelta =
          now.difference(_lastUpdateTime).inMilliseconds / 1000.0;
      final speed =
          timeDelta > 0 ? (vProposed - _lastValue).abs() / timeDelta : 0.0;

      final vFinal = _applySnapping(vProposed, speed);

      _lastValue = _currentValue;
      _lastUpdateTime = now;

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
    });
  }

  void _onDoubleTap() {
    if (widget.defaultValue != null) {
      setState(() {
        _currentValue =
            widget.defaultValue!.clamp(widget.minValue, widget.maxValue);
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

    // Calculate knob center position (accounting for label if present)
    final labelHeight = widget.label.isNotEmpty ? 19.0 : 0.0;
    final knobCenterX = knobPosition.dx + knobSize.width / 2;
    final knobCenterY = knobPosition.dy + labelHeight + widget.size / 2;
    final knobRadius = widget.size / 2;

    // Calculate ideal position centered below the knob
    // Position so the bar's center text overlaps the knob's value text
    double barX = knobPosition.dx + knobSize.width / 2 - widget.dragBarWidth / 2;
    double barY = knobPosition.dy + knobSize.height - 20;

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
                      if (widget.label.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            widget.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[400],
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      SizedBox(
                        width: widget.size,
                        height: widget.size,
                        child: CustomPaint(
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
                          ),
                        ),
                      ),
                      // Value text - hidden here since drag bar shows it
                      const SizedBox(height: 20),
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

    return GestureDetector(
      key: _knobKey,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onDoubleTap: _onDoubleTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label
          if (widget.label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                ),
              ),
            ),
          // Knob
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
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
              ),
            ),
          ),
          // Value display (editable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MouseRegion(
              onEnter: (_) => setState(() => _isHovering = true),
              onExit: (_) => setState(() => _isHovering = false),
              child: GestureDetector(
                onTap: _startEditing,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                      color: _isEditing
                          ? Colors.yellow
                          : _isHovering
                              ? Colors.grey[500]!
                              : Colors.transparent,
                      width: 1,
                    ),
                    color: _isEditing ? Colors.grey[900] : Colors.transparent,
                  ),
                  child: _isEditing
                      ? IntrinsicWidth(
                          child: Focus(
                            onKeyEvent: (node, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.escape) {
                                _cancelEditing();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              controller: _textController,
                              focusNode: _textFocusNode,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'Courier',
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                                border: InputBorder.none,
                              ),
                              textAlign: TextAlign.center,
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
                          ),
                        )
                      : Text(
                          _formatValue(_currentValue),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Courier',
                            color: _snappedTo != null ? Colors.yellow : Colors.white,
                          ),
                        ),
                ),
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

  static const double startAngle = 0.75 * math.pi; // 135 degrees
  static const double sweepAngle = 1.5 * math.pi; // 270 degrees
  static const double deadZone = 0.25 * math.pi; // 45 degrees dead zone at bottom

  _KnobPainter({
    required this.normalized,
    required this.isBipolar,
    this.neutralNormalized,
    required this.isActive,
    required this.snapPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;

    // Background arc
    final bgPaint = Paint()
      ..color = Colors.grey[800]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      bgPaint,
    );

    // Value arc
    final valuePaint = Paint()
      ..color = isActive ? Colors.yellow : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    if (isBipolar && neutralNormalized != null) {
      // Draw from neutral point to current value
      final neutralAngle = startAngle + neutralNormalized! * sweepAngle;
      final valueAngle = startAngle + normalized * sweepAngle;
      final arcStart = math.min(neutralAngle, valueAngle);
      final arcSweep = (valueAngle - neutralAngle).abs();

      if (arcSweep > 0.01) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          arcStart,
          arcSweep,
          false,
          valuePaint,
        );
      }

      // Neutral marker
      final neutralMarkerPaint = Paint()
        ..color = Colors.grey[500]!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      final neutralX = center.dx + (radius - 8) * math.cos(neutralAngle);
      final neutralY = center.dy + (radius - 8) * math.sin(neutralAngle);
      final neutralX2 = center.dx + (radius + 4) * math.cos(neutralAngle);
      final neutralY2 = center.dy + (radius + 4) * math.sin(neutralAngle);
      canvas.drawLine(Offset(neutralX, neutralY), Offset(neutralX2, neutralY2), neutralMarkerPaint);
    } else {
      // Draw from start to current value
      final valueSweep = normalized * sweepAngle;
      if (valueSweep > 0.01) {
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          valueSweep,
          false,
          valuePaint,
        );
      }
    }

    // Snap point markers
    final snapPaint = Paint()
      ..color = Colors.grey[600]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final snapNorm in snapPoints) {
      final snapAngle = startAngle + snapNorm * sweepAngle;
      final x1 = center.dx + (radius - 6) * math.cos(snapAngle);
      final y1 = center.dy + (radius - 6) * math.sin(snapAngle);
      final x2 = center.dx + (radius + 2) * math.cos(snapAngle);
      final y2 = center.dy + (radius + 2) * math.sin(snapAngle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), snapPaint);
    }

    // Value indicator dot
    final indicatorAngle = startAngle + normalized * sweepAngle;
    final indicatorX = center.dx + (radius - 12) * math.cos(indicatorAngle);
    final indicatorY = center.dy + (radius - 12) * math.sin(indicatorAngle);

    final indicatorPaint = Paint()
      ..color = isActive ? Colors.yellow : Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(indicatorX, indicatorY), 4, indicatorPaint);

    // Center circle
    final centerPaint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.3, centerPaint);

    final centerBorderPaint = Paint()
      ..color = Colors.grey[600]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, radius * 0.3, centerBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalized != normalized ||
        oldDelegate.isBipolar != isBipolar ||
        oldDelegate.neutralNormalized != neutralNormalized ||
        oldDelegate.isActive != isActive;
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
  });

  String _formatValue(double value) {
    // Printf-style format with fixed-width output for stable decimal alignment
    final match = RegExp(r'%(\+)?(\d*)\.?(\d*)f').firstMatch(format);
    final showPlus = match?.group(1) == '+';
    final precision = int.tryParse(match?.group(3) ?? '') ?? 2;

    // Calculate width needed for integer part based on value range
    final maxAbsInt = [minValue.abs(), maxValue.abs()]
        .reduce((a, b) => a > b ? a : b)
        .truncate();
    final intWidth = maxAbsInt == 0 ? 1 : maxAbsInt.toString().length;

    // Format the number
    final formatted = value.toStringAsFixed(precision);
    final parts = formatted.split('.');
    var intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // Handle sign and padding
    final isNegative = intPart.startsWith('-');
    if (isNegative) {
      intPart = intPart.substring(1);
    }

    // Pad integer part to consistent width
    intPart = intPart.padLeft(intWidth, ' ');

    // Add sign (or space for positive if range includes negatives or showPlus)
    final needsSignSpace = minValue < 0 || showPlus;
    final sign = isNegative ? '-' : (showPlus ? '+' : (needsSignSpace ? ' ' : ''));

    return '$sign$intPart$decPart';
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
                  _formatValue(value),
                  style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'Courier',
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
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

  _DragBarPainter({
    required this.normalizedValue,
    required this.startNormalized,
    required this.isBipolar,
    this.neutralValue,
    required this.minValue,
    required this.maxValue,
    required this.snapPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barHeight = size.height;
    final barY = 0.0;

    // Background track
    final trackPaint = Paint()
      ..color = Colors.grey[700]!
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barY, size.width, barHeight),
        const Radius.circular(2),
      ),
      trackPaint,
    );

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

    // Snap point markers
    final snapPaint = Paint()
      ..color = Colors.grey[600]!
      ..strokeWidth = 1;

    for (final snap in snapPoints) {
      final snapNorm = (snap - minValue) / (maxValue - minValue);
      if (snapNorm >= 0 && snapNorm <= 1) {
        final snapX = snapNorm * size.width;
        canvas.drawLine(
          Offset(snapX, barY - 1),
          Offset(snapX, barY + barHeight + 1),
          snapPaint,
        );
      }
    }

    // Value bar (filled bar from start/neutral to current value)
    final valueX = normalizedValue * size.width;
    final valuePaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;

    if (isBipolar) {
      // Draw bar from neutral point to current value
      final neutral = neutralValue ?? 0;
      final neutralNorm = (neutral - minValue) / (maxValue - minValue);
      final neutralX = neutralNorm * size.width;
      final barLeft = valueX < neutralX ? valueX : neutralX;
      final barWidth = (valueX - neutralX).abs();
      if (barWidth > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(barLeft, barY, barWidth, barHeight),
            const Radius.circular(2),
          ),
          valuePaint,
        );
      }
    } else {
      // Draw bar from left edge to current value
      if (valueX > 0.5) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, barY, valueX, barHeight),
            const Radius.circular(2),
          ),
          valuePaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DragBarPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.startNormalized != startNormalized;
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
