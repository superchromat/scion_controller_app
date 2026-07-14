import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/panel.dart';
import 'package:SCION_Controller/rotary_knob.dart';
import 'package:SCION_Controller/grid.dart';

import 'harness.dart';

void main() {
  testWidgets('probe: real card + knob render', (tester) async {
    final child = Builder(builder: (context) {
      final t = GridProvider.of(context);
      Widget knob(String label, double v) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RotaryKnob(
                value: v, minValue: 0, maxValue: 1, size: t.knobMd,
              ),
              SizedBox(height: t.xs),
              Text(label, style: t.textLabel),
            ],
          );
      return Padding(
        padding: EdgeInsets.all(t.md),
        child: LabeledCard(
          title: 'Shape',
          child: Panel(
            title: 'Scale',
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [knob('X', 0.7), knob('Y', 0.4), knob('Pos', 0.5)],
            ),
          ),
        ),
      );
    });
    await shoot(tester,
        child: child,
        size: const Size(520, 260),
        goldenPath: 'shots/probe.png');
  });
}
