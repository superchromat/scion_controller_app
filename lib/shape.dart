// shape.dart

import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'numeric_slider.dart';
// import 'osc_radiolist.dart';

class LinkableSliderPair extends StatefulWidget {
  final String label;
  final String xKey;
  final String yKey;
  final double xValue;
  final double yValue;
  final RangeValues range;
  final List<double>? detents;
  final int precision;
  /// If true, starts linked and shows the link icon
  final bool defaultLinked;

  const LinkableSliderPair({
    super.key,
    required this.label,
    required this.xKey,
    required this.yKey,
    required this.xValue,
    required this.yValue,
    required this.range,
    required this.precision,
    this.detents,
    this.defaultLinked = false,
  });

  @override
  State<LinkableSliderPair> createState() => _LinkableSliderPairState();
}

class _LinkableSliderPairState extends State<LinkableSliderPair> {
  late bool _linked = widget.defaultLinked;
  final _xSliderKey = GlobalKey<NumericSliderState>();
  final _ySliderKey = GlobalKey<NumericSliderState>();
  String? _lastEditedKey;
  late final double _initialX = widget.xValue;
  late final double _initialY = widget.yValue;

  void _toggleLink() {
    setState(() => _linked = !_linked);
    if (_linked && _lastEditedKey != null) {
      final sourceKey = _lastEditedKey == widget.xKey ? _xSliderKey : _ySliderKey;
      final targetKey = _lastEditedKey == widget.xKey ? _ySliderKey : _xSliderKey;
      final sourceVal = sourceKey.currentState?.value;
      if (sourceVal != null) {
        targetKey.currentState?.setValue(sourceVal, immediate: true);
      }
    }
  }

  void _resetValues() {
    _xSliderKey.currentState?.setValue(_initialX, immediate: true);
    _ySliderKey.currentState?.setValue(_initialY, immediate: true);
  }

  void _onSliderChanged({
    required String changedKey,
    required double value,
    required String otherKey,
    required GlobalKey<NumericSliderState> otherSliderKey,
  }) {
    _lastEditedKey = changedKey;
    if (_linked) {
      otherSliderKey.currentState?.setValue(value, immediate: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(widget.label)),
        SizedBox(
          height: 24, width: 60,
          child: OscPathSegment(
            segment: widget.xKey,
            child: NumericSlider(
              key: _xSliderKey,
              value: widget.xValue,
              range: widget.range,
              detents: widget.detents,
              precision: widget.precision,
              onChanged: (v) => _onSliderChanged(
                changedKey: widget.xKey,
                value: v,
                otherKey: widget.yKey,
                otherSliderKey: _ySliderKey,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
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
        SizedBox(
          height: 24, width: 60,
          child: OscPathSegment(
            segment: widget.yKey,
            child: NumericSlider(
              key: _ySliderKey,
              value: widget.yValue,
              range: widget.range,
              detents: widget.detents,
              precision: widget.precision,
              onChanged: (v) => _onSliderChanged(
                changedKey: widget.yKey,
                value: v,
                otherKey: widget.xKey,
                otherSliderKey: _xSliderKey,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _resetValues,
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }
}

class Shape extends StatefulWidget {
  const Shape({super.key});

  @override
  ShapeState createState() => ShapeState();
}

class ShapeState extends State<Shape> {
  final _rotationKey = GlobalKey<NumericSliderState>();
  // Pitch/Yaw removed

  Widget _labeledSlider({
    required String label,
    required String paramKey,
    required GlobalKey<NumericSliderState> sliderKey,
    required double value,
    required RangeValues range,
    List<double>? detents,
    required int precision,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24, width: 60,
          child: OscPathSegment(
            segment: paramKey,
            child: NumericSlider(
              key: sliderKey,
              value: value,
              range: range,
              detents: detents,
              precision: precision,
              onChanged: (v) {},
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            sliderKey.currentState?.setValue(value, immediate: true);
          },
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  Widget _row(Widget child) => SizedBox(
        height: 25,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: 0, maxHeight: double.infinity),
      child: Column(
        children: [
          _row(LinkableSliderPair(
            label: 'Scale',
            xKey: 'scaleX',
            yKey: 'scaleY',
            xValue: 1.0,
            yValue: 1.0,
            range: const RangeValues(0.0, 4.0),
            detents: [0.0, 0.5, 1.0, 2.0, 4.0],
            precision: 3,
            defaultLinked: true,
          )),
          _row(LinkableSliderPair(
            label: 'Position',
            xKey: 'posX',
            yKey: 'posY',
            xValue: 0.5,
            yValue: 0.5,
            range: const RangeValues(0, 1),
            detents: [0, 0.5, 1.0],
            precision: 3,
          )),
          // Zoom Mode removed
          _row(_labeledSlider(
            label: "Rotation",
            paramKey: "rotation",
            sliderKey: _rotationKey,
            value: 0.0,
            range: const RangeValues(0.0, 360.0),
            detents: const [0.0, 90.0, 180.0, 270.0, 360.0],
            precision: 3,
          )),
          // Pitch/Yaw removed
        ],
      ),
    );
  }
}
