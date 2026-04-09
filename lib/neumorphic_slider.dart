import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Axis for the slider track.
enum SliderAxis { vertical, horizontal }

/// A neumorphic slider with a physical slot track and raised thumb.
///
/// Matches the neumorphic slot + lit-indicator style of [RotaryKnob].
/// The track is a recessed channel; the thumb is a raised capsule that
/// slides along it.
class NeumorphicSlider extends StatefulWidget {
  final double minValue;
  final double maxValue;
  final double value;
  final ValueChanged<double>? onChanged;
  final String label;
  final String format;
  final double? defaultValue;
  final bool isBipolar;
  final SliderAxis axis;

  /// Track length (height for vertical, width for horizontal).
  /// Set to null for horizontal sliders to fill available width.
  final double? trackLength;

  /// Track slot width in pixels.
  final double trackWidth;

  /// Thumb length along the track axis.
  final double thumbLength;

  const NeumorphicSlider({
    super.key,
    required this.minValue,
    required this.maxValue,
    required this.value,
    this.onChanged,
    this.label = '',
    this.format = '%.1f',
    this.defaultValue,
    this.isBipolar = false,
    this.axis = SliderAxis.vertical,
    this.trackLength,
    this.trackWidth = 10,
    this.thumbLength = 28,
  });

  @override
  State<NeumorphicSlider> createState() => _NeumorphicSliderState();
}

class _NeumorphicSliderState extends State<NeumorphicSlider> {
  double _value = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(NeumorphicSlider old) {
    super.didUpdateWidget(old);
    if (!_dragging) _value = widget.value;
  }

  double get _normalized =>
      (((_value - widget.minValue) / (widget.maxValue - widget.minValue))
          .clamp(0.0, 1.0));

  double get _neutralNormalized {
    final nv = widget.defaultValue ?? 0.0;
    return ((nv - widget.minValue) / (widget.maxValue - widget.minValue))
        .clamp(0.0, 1.0);
  }

  /// Usable travel length (track minus thumb).
  double _travelFor(double length) => length - widget.thumbLength;

  double _resolvedLength = 200; // updated by build/LayoutBuilder

  void _updateFromPos(double pos) {
    final travel = _travelFor(_resolvedLength);
    final clamped = pos.clamp(0.0, travel);
    double norm;
    if (widget.axis == SliderAxis.vertical) {
      norm = 1.0 - clamped / travel; // invert for vertical
    } else {
      norm = clamped / travel;
    }
    final raw = widget.minValue + norm * (widget.maxValue - widget.minValue);
    final v = raw.clamp(widget.minValue, widget.maxValue);
    if (v != _value) {
      setState(() => _value = v);
      widget.onChanged?.call(v);
    }
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final local = d.localPosition;
    final pos = widget.axis == SliderAxis.vertical
        ? local.dy - widget.thumbLength / 2
        : local.dx - widget.thumbLength / 2;
    _updateFromPos(pos);
  }

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
  }

  void _onDoubleTap() {
    final def = widget.defaultValue ?? widget.minValue;
    setState(() => _value = def);
    widget.onChanged?.call(def);
  }

  String get _formattedValue {
    try {
      final replaced = widget.format.replaceAllMapped(
        RegExp(r'%(\.\d+)?[dfeg]'),
        (m) => _value.toStringAsFixed(
          int.tryParse(m.group(1)?.substring(1) ?? '0') ?? 0,
        ),
      );
      return replaced.replaceAll('%%', '%');
    } catch (_) {
      return _value.toStringAsFixed(1);
    }
  }

  Widget _buildTrack(double trackLength) {
    final isVertical = widget.axis == SliderAxis.vertical;
    final crossSize = widget.trackWidth + 24;

    final painter = _SliderPainter(
      normalized: _normalized,
      neutralNormalized: widget.isBipolar ? _neutralNormalized : null,
      isBipolar: widget.isBipolar,
      isActive: _dragging,
      axis: widget.axis,
      trackLength: trackLength,
      trackWidth: widget.trackWidth,
      thumbLength: widget.thumbLength,
    );

    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onDoubleTap: _onDoubleTap,
      child: SizedBox(
        width: isVertical ? crossSize : trackLength,
        height: isVertical ? trackLength : crossSize,
        child: CustomPaint(painter: painter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVertical = widget.axis == SliderAxis.vertical;
    final explicitLength = widget.trackLength;

    // For null trackLength in horizontal mode, use LayoutBuilder to fill width.
    final bool useLayoutBuilder = explicitLength == null && !isVertical;

    Widget track;
    if (useLayoutBuilder) {
      track = LayoutBuilder(
        builder: (context, constraints) {
          final len = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
          _resolvedLength = len;
          return _buildTrack(len);
        },
      );
    } else {
      final len = explicitLength ?? 200;
      _resolvedLength = len.toDouble();
      track = _buildTrack(len.toDouble());
    }

    // Value label
    final valueText = Text(
      _formattedValue,
      style: const TextStyle(
        fontSize: 12,
        fontFamily: 'DINPro',
        fontWeight: FontWeight.w500,
        color: Color(0xFFF2F2F2),
      ),
    );

    final labelText = widget.label.isNotEmpty
        ? Text(
            widget.label,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'DINPro',
              fontWeight: FontWeight.w400,
              color: Color(0xFFD2D2D4),
            ),
          )
        : null;

    if (isVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          valueText,
          const SizedBox(height: 4),
          track,
          const SizedBox(height: 4),
          if (labelText != null) labelText,
        ],
      );
    } else {
      // No label or value text — return track alone (e.g., crossfader)
      if (labelText == null && widget.format.isEmpty) {
        return track;
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (labelText != null) ...[labelText, const SizedBox(width: 8)],
          track,
          const SizedBox(width: 8),
          valueText,
        ],
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _SliderPainter extends CustomPainter {
  final double normalized;
  final double? neutralNormalized;
  final bool isBipolar;
  final bool isActive;
  final SliderAxis axis;
  final double trackLength;
  final double trackWidth;
  final double thumbLength;

  static const Color _activeColor = Color(0xFFF0B830); // amber/gold
  static const Color _inactiveColor = Color(0xFFE8E8E8);

  _SliderPainter({
    required this.normalized,
    this.neutralNormalized,
    required this.isBipolar,
    required this.isActive,
    required this.axis,
    required this.trackLength,
    required this.trackWidth,
    required this.thumbLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final isVertical = axis == SliderAxis.vertical;

    // Centre of the cross-axis
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Track rect in logical coordinates (vertical: y runs top→bottom)
    final double trackStart; // along-axis start pixel
    final double trackEnd;
    if (isVertical) {
      trackStart = 0;
      trackEnd = trackLength;
    } else {
      trackStart = 0;
      trackEnd = trackLength;
    }

    final halfSlot = trackWidth / 2;

    // ─── Slot (recessed channel) ───
    _drawSlot(canvas, size, isVertical, cx, cy, trackStart, trackEnd, halfSlot);

    // ─── Value fill ───
    _drawValueFill(canvas, size, isVertical, cx, cy, trackStart, trackEnd, halfSlot);

    // ─── Thumb ───
    _drawThumb(canvas, size, isVertical, cx, cy, trackStart, trackEnd, halfSlot);
  }

  void _drawSlot(Canvas canvas, Size size, bool isVertical,
      double cx, double cy, double trackStart, double trackEnd, double halfSlot) {
    // Slot border (outer bright edge)
    final borderGradient = isVertical
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF585858), Color(0xFF484848), Color(0xFF383838)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF585858), Color(0xFF484848), Color(0xFF383838)],
          );

    final RRect slotOuter;
    if (isVertical) {
      slotOuter = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - halfSlot - 1, trackStart, cx + halfSlot + 1, trackEnd),
        Radius.circular(halfSlot + 1),
      );
    } else {
      slotOuter = RRect.fromRectAndRadius(
        Rect.fromLTRB(trackStart, cy - halfSlot - 1, trackEnd, cy + halfSlot + 1),
        Radius.circular(halfSlot + 1),
      );
    }
    canvas.drawRRect(
      slotOuter,
      Paint()..shader = borderGradient.createShader(slotOuter.outerRect),
    );

    // Slot floor (dark recessed area)
    final floorGradient = isVertical
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1C1C1C), Color(0xFF141414), Color(0xFF101010)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1C1C1C), Color(0xFF141414), Color(0xFF101010)],
          );

    final RRect slotInner;
    if (isVertical) {
      slotInner = RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - halfSlot, trackStart + 1, cx + halfSlot, trackEnd - 1),
        Radius.circular(halfSlot),
      );
    } else {
      slotInner = RRect.fromRectAndRadius(
        Rect.fromLTRB(trackStart + 1, cy - halfSlot, trackEnd - 1, cy + halfSlot),
        Radius.circular(halfSlot),
      );
    }
    canvas.drawRRect(
      slotInner,
      Paint()..shader = floorGradient.createShader(slotInner.outerRect),
    );

    // Inner shadow on the lit edge of the slot (top for vertical, left for horizontal)
    final shadowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    if (isVertical) {
      shadowPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0.15),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(slotInner.outerRect);
    } else {
      shadowPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.black.withValues(alpha: 0.15),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05),
        ],
      ).createShader(slotInner.outerRect);
    }
    canvas.drawRRect(slotInner.deflate(0.5), shadowPaint);
  }

  void _drawValueFill(Canvas canvas, Size size, bool isVertical,
      double cx, double cy, double trackStart, double trackEnd, double halfSlot) {
    final travel = trackLength - thumbLength;
    final baseColor = isActive ? _activeColor : _inactiveColor;

    // Determine fill start/end in along-axis pixels
    double fillStart, fillEnd;
    if (isBipolar && neutralNormalized != null) {
      final nNorm = neutralNormalized!;
      final lo = math.min(nNorm, normalized);
      final hi = math.max(nNorm, normalized);
      if (isVertical) {
        fillStart = trackLength - (hi * travel + thumbLength / 2);
        fillEnd = trackLength - (lo * travel + thumbLength / 2);
      } else {
        fillStart = lo * travel + thumbLength / 2;
        fillEnd = hi * travel + thumbLength / 2;
      }
    } else {
      if (isVertical) {
        fillStart = trackLength - (normalized * travel + thumbLength / 2);
        fillEnd = trackLength;
      } else {
        fillStart = 0;
        fillEnd = normalized * travel + thumbLength / 2;
      }
    }

    if ((fillEnd - fillStart).abs() < 1) return;

    // Clip to slot and draw coloured fill
    final fillInset = 2.0;
    RRect fillRect;
    if (isVertical) {
      fillRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          cx - halfSlot + fillInset,
          fillStart.clamp(trackStart + fillInset, trackEnd - fillInset),
          cx + halfSlot - fillInset,
          fillEnd.clamp(trackStart + fillInset, trackEnd - fillInset),
        ),
        Radius.circular(halfSlot - fillInset),
      );
    } else {
      fillRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          fillStart.clamp(trackStart + fillInset, trackEnd - fillInset),
          cy - halfSlot + fillInset,
          fillEnd.clamp(trackStart + fillInset, trackEnd - fillInset),
          cy + halfSlot - fillInset,
        ),
        Radius.circular(halfSlot - fillInset),
      );
    }

    final gradient = isVertical
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.lerp(baseColor, Colors.black, 0.15)!,
              baseColor,
              Color.lerp(baseColor, Colors.black, 0.15)!,
            ],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color.lerp(baseColor, Colors.black, 0.15)!,
              baseColor,
              Color.lerp(baseColor, Colors.black, 0.15)!,
            ],
          );

    canvas.drawRRect(
      fillRect,
      Paint()..shader = gradient.createShader(fillRect.outerRect),
    );

    // Highlight on the value fill
    final highlightGradient = isVertical
        ? LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.white.withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.05),
              Colors.transparent,
            ],
          )
        : LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.25),
              Colors.white.withValues(alpha: 0.05),
              Colors.transparent,
            ],
          );

    canvas.drawRRect(
      fillRect,
      Paint()..shader = highlightGradient.createShader(fillRect.outerRect),
    );
  }

  void _drawThumb(Canvas canvas, Size size, bool isVertical,
      double cx, double cy, double trackStart, double trackEnd, double halfSlot) {
    final travel = trackLength - thumbLength;

    // Thumb centre position along track
    final double thumbCentre;
    if (isVertical) {
      thumbCentre = trackLength - (normalized * travel + thumbLength / 2);
    } else {
      thumbCentre = normalized * travel + thumbLength / 2;
    }

    final thumbHalf = thumbLength / 2;
    final thumbCrossHalf = halfSlot + 5; // wider than slot
    final thumbRadius = math.min(thumbCrossHalf, thumbHalf);

    RRect thumbRect;
    if (isVertical) {
      thumbRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          cx - thumbCrossHalf,
          thumbCentre - thumbHalf,
          cx + thumbCrossHalf,
          thumbCentre + thumbHalf,
        ),
        Radius.circular(thumbRadius),
      );
    } else {
      thumbRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(
          thumbCentre - thumbHalf,
          cy - thumbCrossHalf,
          thumbCentre + thumbHalf,
          cy + thumbCrossHalf,
        ),
        Radius.circular(thumbRadius),
      );
    }

    // Shadow under thumb
    final shadowRect = thumbRect.shift(const Offset(0, 2));
    canvas.drawRRect(
      shadowRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Thumb body — raised capsule with gradient
    final thumbGradient = isVertical
        ? const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF555558), Color(0xFF4A4A4D), Color(0xFF3E3E41)],
          )
        : const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF555558), Color(0xFF4A4A4D), Color(0xFF3E3E41)],
          );

    canvas.drawRRect(
      thumbRect,
      Paint()..shader = thumbGradient.createShader(thumbRect.outerRect),
    );

    // Highlight edge on lit side
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    if (isVertical) {
      highlightPaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(thumbRect.outerRect);
    } else {
      highlightPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.06),
          Colors.transparent,
        ],
      ).createShader(thumbRect.outerRect);
    }
    canvas.drawRRect(thumbRect.deflate(0.5), highlightPaint);

    // Shadow edge on opposite side
    final shadowEdgePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    if (isVertical) {
      shadowEdgePaint.shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.12),
        ],
      ).createShader(thumbRect.outerRect);
    } else {
      shadowEdgePaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.06),
          Colors.black.withValues(alpha: 0.12),
        ],
      ).createShader(thumbRect.outerRect);
    }
    canvas.drawRRect(thumbRect.deflate(0.5), shadowEdgePaint);

    // Centre grip line on thumb
    final gripPaint = Paint()
      ..color = const Color(0xFF2A2A2D)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;
    if (isVertical) {
      final gripLen = thumbCrossHalf * 0.6;
      canvas.drawLine(
        Offset(cx - gripLen, thumbCentre),
        Offset(cx + gripLen, thumbCentre),
        gripPaint,
      );
      // Highlight line above
      canvas.drawLine(
        Offset(cx - gripLen, thumbCentre - 1),
        Offset(cx + gripLen, thumbCentre - 1),
        Paint()..color = Colors.white.withValues(alpha: 0.08)..strokeCap = StrokeCap.round,
      );
    } else {
      final gripLen = thumbCrossHalf * 0.6;
      canvas.drawLine(
        Offset(thumbCentre, cy - gripLen),
        Offset(thumbCentre, cy + gripLen),
        gripPaint,
      );
      canvas.drawLine(
        Offset(thumbCentre - 1, cy - gripLen),
        Offset(thumbCentre - 1, cy + gripLen),
        Paint()..color = Colors.white.withValues(alpha: 0.08)..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) =>
      old.normalized != normalized ||
      old.neutralNormalized != neutralNormalized ||
      old.isActive != isActive ||
      old.isBipolar != isBipolar;
}
