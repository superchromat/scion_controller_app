// shape.dart

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'osc_rotary_knob.dart';
import 'rotary_knob.dart';
import 'labeled_card.dart';
import 'grid.dart';

// Local aliases for AppGrid tokens used in this file.
const double _dialSize = AppGrid.knobSize;
const double _knobGap = AppGrid.knobGap;
const EdgeInsets _panelPadding = AppGrid.panelPadding;
const TextStyle _knobLabelStyle = AppGrid.knobLabelStyle;

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
        Expanded(
          child: Center(
            child: _buildKnob(
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
        Expanded(
          child: Center(
            child: _buildKnob(
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
        GridRow(
          columns: 2,
          cells: [
            (
              span: 1,
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
            (
              span: 1,
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
        if (showRotation) ...[
          const SizedBox(height: 8),
          GridRow(
            columns: 2,
            cells: [
              (
                span: 1,
                child: NeumorphicInset(
                  padding: _panelPadding,
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: OscPathSegment(
                            segment: 'rotation',
                            child: OscRotaryKnob(
                              key: _rotationKey,
                              initialValue: 180.0,
                              minValue: 0.0,
                              maxValue: 360.0,
                              format: '%.1f',
                              label: 'Rotation',
                              defaultValue: 180.0,
                              size: _dialSize,
                              labelStyle: _knobLabelStyle,
                              snapConfig: SnapConfig(
                                snapPoints: const [0.0, 90.0, 180.0, 270.0, 360.0],
                                snapRegionHalfWidth: 7.2,
                                snapBehavior: SnapBehavior.hard,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ),
              (span: 1, child: const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}
