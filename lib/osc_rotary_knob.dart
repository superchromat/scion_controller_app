import 'package:flutter/material.dart';

import 'rotary_knob.dart';
import 'osc_widget_binding.dart';

/// OSC-enabled wrapper for RotaryKnob.
///
/// This widget manages its own internal state and syncs with OSC:
/// - Sends values when user changes them (unless [sendOsc] is false)
/// - Receives values from OSC and updates the knob
///
/// Wrap with [OscPathSegment] to set the OSC address path.
class OscRotaryKnob extends StatefulWidget {
  /// Minimum value
  final double minValue;

  /// Maximum value
  final double maxValue;

  /// Initial value
  final double initialValue;

  /// Printf-style format string for displaying value
  final String format;

  /// Label text
  final String label;

  /// Default value for long-press reset
  final double? defaultValue;

  /// Whether this is a bipolar knob
  final bool isBipolar;

  /// Custom neutral value for bipolar display
  final double? neutralValue;

  /// Callback when value changes (called for both user and OSC changes)
  final ValueChanged<double>? onChanged;

  /// Snap configuration
  final SnapConfig snapConfig;

  /// Mapping segments for non-linear value mapping
  final List<MappingSegment>? mappingSegments;

  /// Size of the knob
  final double size;

  /// Width of the drag bar
  final double dragBarWidth;

  /// Whether to send OSC messages when value changes
  final bool sendOsc;

  /// If true, send integers when value is a whole number
  final bool preferInteger;

  /// Optional style override for the label below the knob
  final TextStyle? labelStyle;

  const OscRotaryKnob({
    super.key,
    required this.minValue,
    required this.maxValue,
    this.initialValue = 0,
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
    this.sendOsc = true,
    this.preferInteger = false,
    this.labelStyle,
  });

  @override
  State<OscRotaryKnob> createState() => OscRotaryKnobState();
}

class OscRotaryKnobState extends State<OscRotaryKnob> with OscAddressMixin {
  late double _value;

  /// Track the last value we sent to ignore local echo
  double? _lastSentValue;

  /// Track when we're actively dragging
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _value = _quantize(widget.initialValue);
  }

  @override
  void didUpdateWidget(OscRotaryKnob oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clamp value if range changed
    if (widget.minValue != oldWidget.minValue ||
        widget.maxValue != oldWidget.maxValue) {
      _value = _quantize(_value);
    }
  }

  /// Current value (read-only access for external use)
  double get value => _value;

  double _quantize(double v) {
    final clamped = v.clamp(widget.minValue, widget.maxValue);
    if (widget.preferInteger) {
      return clamped.roundToDouble();
    }
    return clamped;
  }

  /// Programmatically set the value
  ///
  /// [emit] - whether to call onChanged callback
  /// [sendOscNow] - whether to immediately send OSC message
  void setValue(double newValue, {bool emit = true, bool sendOscNow = false}) {
    final clamped = _quantize(newValue);
    if ((clamped - _value).abs() > 0.0001) {
      setState(() => _value = clamped);
      if (emit) {
        widget.onChanged?.call(_value);
      }
      if (sendOscNow && widget.sendOsc) {
        _doSendOsc();
      }
    }
  }

  void _doSendOsc() {
    _lastSentValue = _value;
    if (widget.preferInteger) {
      sendOsc(_value.round());
    } else {
      sendOsc(_value);
    }
  }

  @override
  OscStatus onOscMessage(List<Object?> args) {
    if (args.isNotEmpty && args.first is num) {
      final newValue = _quantize((args.first as num).toDouble());

      // Ignore if we're dragging - user input takes priority
      if (_isDragging) {
        return OscStatus.ok;
      }

      // Ignore local echo (value we just sent)
      if (_lastSentValue != null && (newValue - _lastSentValue!).abs() < 0.0001) {
        return OscStatus.ok;
      }

      setValue(newValue, emit: true);
      return OscStatus.ok;
    }
    return OscStatus.error;
  }

  void _onChanged(double newValue) {
    _isDragging = true;
    final quantized = _quantize(newValue);
    setState(() => _value = quantized);
    widget.onChanged?.call(_value);

    if (widget.sendOsc) {
      _doSendOsc();
    }

    // Reset dragging flag after a short delay to allow any echo to be ignored
    Future.delayed(const Duration(milliseconds: 50), () {
      _isDragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format =
        (widget.preferInteger && widget.format == '%.2f') ? '%.0f' : widget.format;

    return RotaryKnob(
      minValue: widget.minValue,
      maxValue: widget.maxValue,
      value: _value,
      format: format,
      label: widget.label,
      defaultValue: widget.defaultValue,
      isBipolar: widget.isBipolar,
      neutralValue: widget.neutralValue,
      onChanged: _onChanged,
      snapConfig: widget.snapConfig,
      mappingSegments: widget.mappingSegments,
      size: widget.size,
      dragBarWidth: widget.dragBarWidth,
      integerOnly: widget.preferInteger,
      labelStyle: widget.labelStyle,
    );
  }
}
