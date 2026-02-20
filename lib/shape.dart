// shape.dart

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'labeled_card.dart';

// Grid constants — shared with send_texture.dart
const double _dialSize = 50;
const double _knobGap = 12;
const EdgeInsets _panelPadding = EdgeInsets.fromLTRB(6, 6, 6, 4);

const TextStyle _knobLabelStyle = TextStyle(
  fontSize: 11,
  color: Color(0xFF999999),
);

const Color _iconColor = Color(0xFF888888);
const double _iconSize = 14;

class LinkableKnobPair extends StatefulWidget {
  final String label;
  final IconData icon;
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
    required this.icon,
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
        size: _dialSize,
        labelStyle: _knobLabelStyle,
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
      children: [
        Tooltip(
          message: widget.label,
          child: Icon(widget.icon, size: _iconSize, color: _iconColor),
        ),
        const SizedBox(width: 2),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              widget.defaultLinked
                  ? GestureDetector(
                      onTap: _toggleLink,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: SizedBox(
                          width: _knobGap,
                          child: Center(
                            child: Icon(
                              _linked ? Icons.link : Icons.link_off,
                              size: 16,
                              color: _linked
                                  ? const Color(0xFFFFF176)
                                  : Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    )
                  : SizedBox(width: _knobGap),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: NeumorphicInset(
                  padding: _panelPadding,
                  child: LinkableKnobPair(
                    label: 'Scale',
                    icon: Icons.zoom_out_map,
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
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: NeumorphicInset(
                  padding: _panelPadding,
                  child: LinkableKnobPair(
                    label: 'Position',
                    icon: Icons.open_with,
                    xKey: 'posX',
                    yKey: 'posY',
                    xValue: 0.5,
                    yValue: 0.5,
                    minValue: 0.0,
                    maxValue: 1.0,
                    snapPoints: const [0.0, 0.5, 1.0],
                    precision: 3,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showRotation) ...[
          const SizedBox(height: 8),
          NeumorphicInset(
            padding: _panelPadding,
            child: Row(
              children: [
                Tooltip(
                  message: 'Rotation',
                  child: Icon(Icons.rotate_right, size: _iconSize, color: _iconColor),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OscPathSegment(
                        segment: 'rotation',
                        child: OscRotaryKnob(
                          key: _rotationKey,
                          initialValue: 180.0,
                          minValue: 0.0,
                          maxValue: 360.0,
                          format: '%.1f',
                          label: '',
                          defaultValue: 180.0,
                          size: _dialSize,
                          labelStyle: _knobLabelStyle,
                          snapConfig: SnapConfig(
                            snapPoints: const [0.0, 90.0, 180.0, 270.0, 360.0],
                            snapRegionHalfWidth: 7.2, // 2% of 360
                            snapBehavior: SnapBehavior.hard,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
