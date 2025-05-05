import 'package:flutter/material.dart';

import 'NumericSlider.dart';

void shapeChange(String key, double val) {
  // Callback stub
}

class Shape extends StatelessWidget {
  final void Function(String key, double value) onParamChanged = shapeChange;

  const Shape({super.key});

  Widget _lockedSliders({
    required String label,
    required String xKey,
    required String yKey,
    required double xValue,
    required double yValue,
    required RangeValues range,
    List<double>? detents,
    bool showLinkIcon = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: NumericSlider(
            value: xValue,
            range: range,
            detents: detents,
            onChanged: (v) => onParamChanged(xKey, v),
          ),
        ),
        if (showLinkIcon)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.link, size: 16, color: Colors.grey),
          ),
        SizedBox(
          height: 24,
          width: 60,
          child: NumericSlider(
            value: yValue,
            range: range,
            detents: detents,
            onChanged: (v) => onParamChanged(yKey, v),
          ), 
        ),
        const SizedBox(width: 8),
        const Icon(Icons.adjust, size: 16),
        const SizedBox(width: 8),
        const Icon(Icons.refresh, size: 16),
      ],
    );
  }

  Widget _labeledSlider({
    required String label,
    required String key,
    required double value,
    required RangeValues range,
    List<double>? detents,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 80, child: Text(label)),
        SizedBox(
          height: 24,
          width: 60,
          child: NumericSlider(
            value: value,
            range: range,
            detents: detents,
            onChanged: (v) => onParamChanged(key, v),
          ),
        ),
        const SizedBox(width: 8),
        const Icon(Icons.adjust, size: 16),
        const SizedBox(width: 8),
        const Icon(Icons.refresh, size: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 0, maxHeight: double.infinity),
      child: Column(
        children: [
          _lockedSliders(
            label: "Zoom",
            xKey: "zoomX",
            yKey: "zoomY",
            xValue: 1.1,
            yValue: 1.1,
            range: const RangeValues(0.1, 3.0),
            detents: const [1.0],
            showLinkIcon: true,
          ),
          _lockedSliders(
            label: "Position",
            xKey: "posX",
            yKey: "posY",
            xValue: -14.0,
            yValue: 0.0,
            range: const RangeValues(-100.0, 100.0),
            detents: const [0.0],
          ),
          _labeledSlider(
            label: "Rotation Angle",
            key: "rotation",
            value: 0.0,
            range: const RangeValues(-180.0, 180.0),
            detents: const [0.0, 90.0, 180.0, -90.0, -180.0],
          ),
          _lockedSliders(
            label: "Anchor Point",
            xKey: "anchorX",
            yKey: "anchorY",
            xValue: 0.0,
            yValue: 0.0,
            range: const RangeValues(-1.0, 1.0),
            detents: const [0.0],
          ),
          _labeledSlider(
            label: "Pitch",
            key: "pitch",
            value: 0.0,
            range: const RangeValues(-90.0, 90.0),
            detents: const [0.0],
          ),
          _labeledSlider(
            label: "Yaw",
            key: "yaw",
            value: 0.0,
            range: const RangeValues(-180.0, 180.0),
            detents: const [0.0],
          ),
          const SizedBox(height: 8),
          Row(
            children: const [
              SizedBox(width: 80, child: Text("Flip")),
              Icon(Icons.skip_previous, size: 20),
              SizedBox(width: 16),
              Icon(Icons.swap_vert, size: 20),
            ],
          ),
        ],
      ),
    );
  }
}
