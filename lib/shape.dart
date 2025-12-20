// shape.dart

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';

class LinkableKnobPair extends StatefulWidget {
  final String label;
  final String xKey;
  final String yKey;
  final double xValue;
  final double yValue;
  final double minValue;
  final double maxValue;
  final List<double>? snapPoints;
  final int precision;
  /// If true, starts linked and shows the link icon
  final bool defaultLinked;

  const LinkableKnobPair({
    super.key,
    required this.label,
    required this.xKey,
    required this.yKey,
    required this.xValue,
    required this.yValue,
    required this.minValue,
    required this.maxValue,
    required this.precision,
    this.snapPoints,
    this.defaultLinked = false,
  });

  @override
  State<LinkableKnobPair> createState() => _LinkableKnobPairState();
}

class _LinkableKnobPairState extends State<LinkableKnobPair> {
  late bool _linked = widget.defaultLinked;
  final _xKnobKey = GlobalKey<OscRotaryKnobState>();
  final _yKnobKey = GlobalKey<OscRotaryKnobState>();
  String? _lastEditedKey;

  void _toggleLink() {
    setState(() => _linked = !_linked);
    if (_linked && _lastEditedKey != null) {
      final sourceKey = _lastEditedKey == widget.xKey ? _xKnobKey : _yKnobKey;
      final targetKey = _lastEditedKey == widget.xKey ? _yKnobKey : _xKnobKey;
      final sourceVal = sourceKey.currentState?.value;
      if (sourceVal != null) {
        targetKey.currentState?.setValue(sourceVal, sendOscNow: true);
      }
    }
  }

  void _onKnobChanged({
    required String changedKey,
    required double value,
    required GlobalKey<OscRotaryKnobState> otherKnobKey,
  }) {
    _lastEditedKey = changedKey;
    if (_linked) {
      otherKnobKey.currentState?.setValue(value, sendOscNow: true);
    }
  }

  Widget _buildKnob({
    required String label,
    required String segment,
    required GlobalKey<OscRotaryKnobState> knobKey,
    required double initialValue,
    required void Function(double) onChanged,
  }) {
    final format = '%.${widget.precision}f';
    return OscPathSegment(
      segment: segment,
      child: OscRotaryKnob(
        key: knobKey,
        initialValue: initialValue,
        minValue: widget.minValue,
        maxValue: widget.maxValue,
        format: format,
        label: label,
        defaultValue: initialValue,
        size: 55,
        snapConfig: SnapConfig(
          snapPoints: widget.snapPoints ?? [],
          snapRegionHalfWidth: (widget.maxValue - widget.minValue) * 0.02,
          snapBehavior: SnapBehavior.hard,
        ),
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(width: 70, child: Text(widget.label)),
        _buildKnob(
          label: 'X',
          segment: widget.xKey,
          knobKey: _xKnobKey,
          initialValue: widget.xValue,
          onChanged: (v) => _onKnobChanged(
            changedKey: widget.xKey,
            value: v,
            otherKnobKey: _yKnobKey,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: widget.defaultLinked
              ? GestureDetector(
                  onTap: _toggleLink,
                  child: Icon(
                    Icons.link,
                    size: 16,
                    color: _linked ? Colors.yellow : Colors.grey,
                  ),
                )
              : const SizedBox(width: 16),
        ),
        _buildKnob(
          label: 'Y',
          segment: widget.yKey,
          knobKey: _yKnobKey,
          initialValue: widget.yValue,
          onChanged: (v) => _onKnobChanged(
            changedKey: widget.yKey,
            value: v,
            otherKnobKey: _xKnobKey,
          ),
        ),
      ],
    );
  }
}

class Shape extends StatefulWidget {
  final int? pageNumber;

  const Shape({super.key, this.pageNumber});

  @override
  ShapeState createState() => ShapeState();
}

class ShapeState extends State<Shape> {
  final _rotationKey = GlobalKey<OscRotaryKnobState>();

  @override
  Widget build(BuildContext context) {
    // Only show rotation for Send 1 (pageNumber == 1)
    final showRotation = widget.pageNumber == null || widget.pageNumber == 1;

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        LinkableKnobPair(
          label: 'Scale',
          xKey: 'scaleX',
          yKey: 'scaleY',
          xValue: 1.0,
          yValue: 1.0,
          minValue: 0.0,
          maxValue: 4.0,
          snapPoints: const [0.0, 0.5, 1.0, 2.0, 4.0],
          precision: 3,
          defaultLinked: true,
        ),
        LinkableKnobPair(
          label: 'Position',
          xKey: 'posX',
          yKey: 'posY',
          xValue: 0.5,
          yValue: 0.5,
          minValue: 0.0,
          maxValue: 1.0,
          snapPoints: const [0.0, 0.5, 1.0],
          precision: 3,
        ),
        if (showRotation)
          OscPathSegment(
            segment: 'rotation',
            child: OscRotaryKnob(
              key: _rotationKey,
              initialValue: 180.0,
              minValue: 0.0,
              maxValue: 360.0,
              format: '%.1f',
              label: 'Rotation',
              defaultValue: 180.0,
              size: 55,
              snapConfig: SnapConfig(
                snapPoints: const [0.0, 90.0, 180.0, 270.0, 360.0],
                snapRegionHalfWidth: 7.2, // 2% of 360
                snapBehavior: SnapBehavior.hard,
              ),
            ),
          ),
      ],
    );
  }
}
