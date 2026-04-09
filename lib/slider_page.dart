import 'package:flutter/material.dart';
import 'labeled_card.dart';
import 'neumorphic_slider.dart';

/// Demo page for the NeumorphicSlider widget.
class SliderPage extends StatefulWidget {
  const SliderPage({super.key});

  @override
  State<SliderPage> createState() => _SliderPageState();
}

class _SliderPageState extends State<SliderPage> {
  double _vertValue = 0.5;
  double _vertBipolar = 0.0;
  double _vertTall = 0.75;
  double _horizValue = 50;
  double _horizBipolar = 0.0;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LabeledCard(
          title: 'Vertical Sliders',
          networkIndependent: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              NeumorphicSlider(
                minValue: 0,
                maxValue: 1,
                value: _vertValue,
                label: 'Gain',
                format: '%.2f',
                defaultValue: 0.5,
                trackLength: 200,
                onChanged: (v) => setState(() => _vertValue = v),
              ),
              NeumorphicSlider(
                minValue: -1,
                maxValue: 1,
                value: _vertBipolar,
                label: 'Pan',
                format: '%+.2f',
                defaultValue: 0,
                isBipolar: true,
                trackLength: 200,
                onChanged: (v) => setState(() => _vertBipolar = v),
              ),
              NeumorphicSlider(
                minValue: 0,
                maxValue: 1,
                value: _vertTall,
                label: 'Level',
                format: '%.0f%%',
                defaultValue: 0.75,
                trackLength: 300,
                trackWidth: 8,
                thumbLength: 32,
                onChanged: (v) => setState(() => _vertTall = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LabeledCard(
          title: 'Horizontal Sliders',
          networkIndependent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeumorphicSlider(
                axis: SliderAxis.horizontal,
                minValue: 0,
                maxValue: 100,
                value: _horizValue,
                label: 'Width',
                format: '%.0f',
                defaultValue: 50,
                trackLength: 300,
                onChanged: (v) => setState(() => _horizValue = v),
              ),
              const SizedBox(height: 24),
              NeumorphicSlider(
                axis: SliderAxis.horizontal,
                minValue: -100,
                maxValue: 100,
                value: _horizBipolar,
                label: 'Offset',
                format: '%+.0f',
                defaultValue: 0,
                isBipolar: true,
                trackLength: 300,
                onChanged: (v) => setState(() => _horizBipolar = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
