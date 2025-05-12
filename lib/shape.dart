import 'package:flutter/material.dart';
import 'osc_widget_binding.dart';
import 'numeric_slider.dart';

class LinkableSliderPair extends StatefulWidget {
  final String label;
  final String xKey;
  final String yKey;
  final double xValue;
  final double yValue;
  final RangeValues range;
  final List<double>? detents;
  final int precision;
  final void Function(String key, double value) onChanged;

  const LinkableSliderPair({
    super.key,
    required this.label,
    required this.xKey,
    required this.yKey,
    required this.xValue,
    required this.yValue,
    required this.range,
    required this.precision,
    required this.onChanged,
    this.detents,
  });

  @override
  State<LinkableSliderPair> createState() => _LinkableSliderPairState();
}

class _LinkableSliderPairState extends State<LinkableSliderPair> {
  bool _linked = false;

  final _xSliderKey = GlobalKey<NumericSliderState>();
  final _ySliderKey = GlobalKey<NumericSliderState>();

  String? _lastEditedKey;

  late final double _initialX = widget.xValue;
  late final double _initialY = widget.yValue;

  void _toggleLink() {
    setState(() {
      _linked = !_linked;
    });

    if (_linked && _lastEditedKey != null) {
      final sourceKey =
          _lastEditedKey == widget.xKey ? _xSliderKey : _ySliderKey;
      final targetKey =
          _lastEditedKey == widget.xKey ? _ySliderKey : _xSliderKey;
      final sourceVal = sourceKey.currentState?.value;

      if (sourceVal != null) {
        targetKey.currentState?.setValue(sourceVal, immediate: true);
        final targetParam =
            _lastEditedKey == widget.xKey ? widget.yKey : widget.xKey;
        widget.onChanged(targetParam, sourceVal);
      }
    }
  }

  void _resetValues() {
    _xSliderKey.currentState?.setValue(_initialX, immediate: true);
    _ySliderKey.currentState?.setValue(_initialY, immediate: true);
    widget.onChanged(widget.xKey, _initialX);
    widget.onChanged(widget.yKey, _initialY);
  }

  void _onSliderChanged({
    required String changedKey,
    required double value,
    required String otherKey,
    required GlobalKey<NumericSliderState> otherSliderKey,
  }) {
    _lastEditedKey = changedKey;
    widget.onChanged(changedKey, value);

    if (_linked) {
      otherSliderKey.currentState?.setValue(value, immediate: true);
      widget.onChanged(otherKey, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(widget.label)),
        SizedBox(
          height: 24,
          width: 60,
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
          child: GestureDetector(
            onTap: _toggleLink,
            child: Icon(
              Icons.link,
              size: 16,
              color: _linked ? Colors.yellow : Colors.grey,
            ),
          ),
        ),
        SizedBox(
          height: 24,
          width: 60,
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

void shapeChange(String key, double val) {
  // Callback stub
}

class Shape extends StatelessWidget {
  final void Function(String key, double value) onParamChanged = shapeChange;

  const Shape({super.key});

  Widget _labeledSlider({
    required String label,
    required String key,
    required double value,
    required RangeValues range,
    List<double>? detents,
    required int precision,
  }) {
    final sliderKey = GlobalKey<NumericSliderState>();
    final initialValue = value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: OscPathSegment(
            segment: label.toLowerCase(),
            child: NumericSlider(
              key: sliderKey,
              value: value,
              range: range,
              detents: detents,
              precision: precision,
              onChanged: (v) => onParamChanged(key, v),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            sliderKey.currentState?.setValue(initialValue, immediate: true);
            onParamChanged(key, initialValue);
          },
          child: const Icon(Icons.refresh, size: 16),
        ),
      ],
    );
  }

  Widget _rowWithHeight({required Widget child, double height = 25, double padding = 4}) {
  return SizedBox(
    height: height,
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: padding),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child,
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          const BoxConstraints(minHeight: 0, maxHeight: double.infinity),
      child: Column(
        children: [
          _rowWithHeight(child: LinkableSliderPair(
            label: 'Scale',
            xKey: 'scaleX',
            yKey: 'scaleY',
            xValue: 1.0,
            yValue: 1.0,
            range: const RangeValues(0.0, 4.0),
            detents: [0.0, 0.5, 1.0, 2.0, 4.0],
            precision: 3,
            onChanged: onParamChanged,
          )),
          _rowWithHeight(child: LinkableSliderPair(
            label: 'Position',
            xKey: 'posX',
            yKey: 'posY',
            xValue: 0.0,
            yValue: 0.0,
            range: const RangeValues(-1000, 1000),
            detents: [0.0],
            precision: 0,
            onChanged: onParamChanged,
          )),
          _rowWithHeight(child: _labeledSlider(
              label: "Rotation",
              key: "rotation",
              value: 0.0,
              range: const RangeValues(-180.0, 180.0),
              detents: const [0.0, 90.0, 180.0, -90.0, -180.0],
              precision: 3)),
          _rowWithHeight(child: _labeledSlider(
              label: "Pitch",
              key: "pitch",
              value: 0.0,
              range: const RangeValues(-90.0, 90.0),
              detents: const [0.0],
              precision: 3)),
          _rowWithHeight(child: _labeledSlider(
              label: "Yaw",
              key: "yaw",
              value: 0.0,
              range: const RangeValues(-180.0, 180.0),
              detents: const [0.0],
              precision: 3)),
        ],
      ),
    );
  }
}
