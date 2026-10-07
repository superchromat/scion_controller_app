// A NeumorphicSlider paints amber only while it is the one being dragged.
//
// The bug this pins: _onPointerUp/_onPointerCancel cleared _dragging with a
// bare assignment instead of setState, so the flag was correct in state but no
// rebuild was scheduled and the slider stayed painted amber after release.
// Every slider touched in a session ended up looking active at once.
//
// Asserted through the live painter rather than internal state, because state
// was never the broken part — the missing rebuild was. _SliderPainter is
// private, so the probe is shouldRepaint(): a press or release that changes
// nothing else must still report the paint as dirty. With the bug the widget
// is not rebuilt at all, the same painter instance is still mounted, and
// shouldRepaint against itself is false.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/neumorphic_slider.dart';

import 'design_lab/harness.dart';

CustomPainter _sliderPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.descendant(
      of: find.byType(NeumorphicSlider),
      matching: find.byType(CustomPaint),
    ))
    .map((c) => c.painter)
    .whereType<CustomPainter>()
    .firstWhere((p) => p.runtimeType.toString().contains('SliderPainter'));

void main() {
  testWidgets('the amber active highlight clears on release', (tester) async {
    await loadAppFonts();

    double value = 0.5;
    await tester.pumpWidget(labScaffold(
      width: 800,
      child: Center(
        child: SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (context, setState) => NeumorphicSlider(
              axis: SliderAxis.horizontal,
              minValue: 0,
              maxValue: 1,
              value: value,
              label: '',
              format: '',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final slider = find.byType(NeumorphicSlider);
    expect(slider, findsOneWidget);
    final centre = tester.getCenter(slider);

    // First press/release settles the value at wherever `centre` maps to, so
    // the second round can flip isActive with every other field held equal.
    var gesture = await tester.startGesture(centre);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    final idle = _sliderPainter(tester);

    // Press again on the identical point: the value cannot change now, so
    // isActive is the only field left that can differ.
    gesture = await tester.startGesture(centre);
    await tester.pump();
    final dragging = _sliderPainter(tester);
    expect(dragging.shouldRepaint(idle), isTrue,
        reason: 'pressing must light the slider amber');

    await gesture.up();
    await tester.pump();
    final released = _sliderPainter(tester);
    expect(released.shouldRepaint(dragging), isTrue,
        reason: 'releasing must clear the amber — this is the regression');

    await tester.pumpAndSettle();
  });

  testWidgets('a cancelled drag clears it too', (tester) async {
    await loadAppFonts();

    double value = 0.5;
    await tester.pumpWidget(labScaffold(
      width: 800,
      child: Center(
        child: SizedBox(
          width: 400,
          child: StatefulBuilder(
            builder: (context, setState) => NeumorphicSlider(
              axis: SliderAxis.horizontal,
              minValue: 0,
              maxValue: 1,
              value: value,
              label: '',
              format: '',
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final centre = tester.getCenter(find.byType(NeumorphicSlider));
    var gesture = await tester.startGesture(centre);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    gesture = await tester.startGesture(centre);
    await tester.pump();
    final dragging = _sliderPainter(tester);

    await gesture.cancel();
    await tester.pump();
    expect(_sliderPainter(tester).shouldRepaint(dragging), isTrue);

    await tester.pumpAndSettle();
  });
}
