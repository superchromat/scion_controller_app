// The T-bar fills from the bus it was last fully mixed to, like a hardware
// mixer's LEDs — not always from the left.
//
// Two things this pins:
//  * the fill origin flips only when the bar actually reaches an end, not
//    while it is in transit;
//  * it survives a take, which is the path that moves the bar automatically.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/app_button.dart';
import 'package:SCION_Controller/mixer_page.dart';
import 'package:SCION_Controller/neumorphic_slider.dart';

import 'design_lab/harness.dart';

SliderFillOrigin _originOfFirstRow(WidgetTester tester) => tester
    .widgetList<NeumorphicSlider>(find.byType(NeumorphicSlider))
    .firstWhere((s) => s.axis == SliderAxis.horizontal)
    .fillOrigin;

void main() {
  testWidgets('fill origin follows the end the bar was last parked at',
      (tester) async {
    await loadAppFonts();
    tester.view.physicalSize = const Size(1600, 2200);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(labScaffold(child: const MixerPage(), width: 1600));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    // Opens parked on A (crossfade 0.0), so the fill grows from the left.
    expect(_originOfFirstRow(tester), SliderFillOrigin.start);

    // Take to B on the first row. Both groups are assigned by default, so the
    // crossfade guard lets it run.
    final autos = find.widgetWithText(AppButton, 'AUTO');
    expect(autos, findsNWidgets(6), reason: 'two per row');
    await tester.tap(autos.at(1), warnIfMissed: false); // row 1, B end

    // Mid-transition: not yet parked, so the origin must not have flipped.
    await tester.pump(const Duration(milliseconds: 300));
    expect(_originOfFirstRow(tester), SliderFillOrigin.start,
        reason: 'the bar is still in transit');

    // Past the 1s default take.
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(_originOfFirstRow(tester), SliderFillOrigin.end,
        reason: 'parked on B, so the fill now grows from the right');

    // And back again.
    await tester.tap(autos.at(0), warnIfMissed: false); // row 1, A end
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
    expect(_originOfFirstRow(tester), SliderFillOrigin.start);

    tester.view.reset();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
