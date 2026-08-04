import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/rotary_knob.dart';

const double _barWidth = 400;
const double _range = 100;
const double _start = 50;
const double _px = 40; // drag distance per test

void main() {
  late double value;
  var generation = 0;

  /// A knob spanning 0..100 over [_barWidth] pixels.
  ///
  /// Keyed by a counter so each call builds a FRESH knob: pumping an identical
  /// tree reuses the existing State, and with it the value left behind by the
  /// previous drag.
  Future<void> pumpKnob(WidgetTester tester) async {
    value = _start;
    generation++;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RotaryKnob(
              key: ValueKey(generation),
              label: 'Test',
              minValue: 0,
              maxValue: _range,
              value: _start,
              dragBarWidth: _barWidth,
              onChanged: (v) => value = v,
            ),
          ),
        ),
      ),
    );
  }

  /// Drags from the knob's centre by [offset] and returns the change in value.
  ///
  /// Moves in steps, not one jump: a single large move is swallowed getting the
  /// pan recogniser past its slop, so no update is ever delivered.
  ///
  /// Returns a DELTA, and every expectation below compares deltas to each other
  /// rather than to an absolute figure, because the recogniser's slop eats the
  /// first stretch of any drag — a dead zone that is not this widget's doing
  /// and that applies to every direction alike.
  Future<double> dragBy(WidgetTester tester, Offset offset) async {
    const steps = 10;
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(RotaryKnob)));
    for (int i = 0; i < steps; i++) {
      await gesture.moveBy(offset / steps.toDouble());
      await tester.pump();
    }
    await gesture.up();
    // Past the double-tap recogniser's timer, which otherwise outlives the test.
    await tester.pump(const Duration(milliseconds: 500));
    return value - _start;
  }

  testWidgets('left/right still change the value', (tester) async {
    await pumpKnob(tester);
    final right = await dragBy(tester, const Offset(_px, 0));
    expect(right, greaterThan(0));

    await pumpKnob(tester);
    final left = await dragBy(tester, const Offset(-_px, 0));
    expect(left, closeTo(-right, 0.001), reason: 'left must mirror right');
  });

  testWidgets('up increases and down decreases', (tester) async {
    await pumpKnob(tester);
    final up = await dragBy(tester, const Offset(0, -_px));
    expect(up, greaterThan(0), reason: 'dragging up must increase the value');

    await pumpKnob(tester);
    final down = await dragBy(tester, const Offset(0, _px));
    expect(down, closeTo(-up, 0.001), reason: 'down must mirror up');
  });

  testWidgets('up and right have the same sensitivity', (tester) async {
    await pumpKnob(tester);
    final right = await dragBy(tester, const Offset(_px, 0));
    await pumpKnob(tester);
    final up = await dragBy(tester, const Offset(0, -_px));
    expect(up, closeTo(right, 0.001),
        reason: 'the same distance must move the value the same amount '
            'whichever way it is dragged');
  });

  testWidgets('diagonals combine the two axes', (tester) async {
    await pumpKnob(tester);
    final right = await dragBy(tester, const Offset(_px, 0));

    // Up AND right both increase, so together they move further than either.
    await pumpKnob(tester);
    final upRight = await dragBy(tester, const Offset(_px, -_px));
    expect(upRight, greaterThan(right));

    // Down-right is right (increase) against down (decrease) in equal measure,
    // so they cancel at every point of the drag and the value never moves.
    await pumpKnob(tester);
    final downRight = await dragBy(tester, const Offset(_px, _px));
    expect(downRight, 0);
  });

  testWidgets('the knob face has no editable field until double-tapped',
      (tester) async {
    await pumpKnob(tester);

    // Nothing to type into: the whole face is drag surface, so a press near
    // the number cannot open an editor instead of starting a drag.
    expect(find.byType(TextField), findsNothing);

    // A drag that starts dead centre — right on top of the number — still
    // turns the knob.
    expect(await dragBy(tester, const Offset(_px, 0)), greaterThan(0));
  });

  testWidgets('double-tapping raises an editor and focuses it', (tester) async {
    await pumpKnob(tester);

    final knob = find.byType(RotaryKnob);
    await tester.tap(knob);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(knob);
    // Two pumps: one to insert the overlay entry, one for it to build, which
    // is also when the focus request lands.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final field = find.byType(TextField);
    expect(field, findsOneWidget, reason: 'the overlay editor should be up');
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue,
        reason: 'and ready to type into');
  });
}
