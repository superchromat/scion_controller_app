// The crossfader's two take-time knobs: linked by default so an auto take is
// symmetric, unlinkable so each end can be set on its own.
//
// Driven through the rendered knobs rather than the private state, since the
// thing worth pinning is that turning one knob while linked moves the other —
// which is a wiring property, not a stored value.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/mixer_page.dart';
import 'package:SCION_Controller/rotary_knob.dart';

import 'design_lab/harness.dart';

const _defaultTake = 1.0;
const _minTake = 0.1;
const _maxTake = 5.0;

// Identified by range, not label: the take knobs carry no label of their own —
// the fader row supplies the caption so it lands on the shared baseline.
List<RotaryKnob> _takeKnobs(WidgetTester tester) => tester
    .widgetList<RotaryKnob>(find.byType(RotaryKnob))
    .where((k) => k.minValue == _minTake && k.maxValue == _maxTake)
    .toList();

Future<void> _pumpMixer(WidgetTester tester) async {
  await loadAppFonts();
  tester.view.physicalSize = const Size(1600, 2200);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(labScaffold(child: const MixerPage(), width: 1600));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('two take knobs per row, defaulting to 1s', (tester) async {
    await _pumpMixer(tester);

    final knobs = _takeKnobs(tester);
    // Three rows, one knob at each end of each fader.
    expect(knobs.length, 6);
    for (final k in knobs) {
      expect(k.value, _defaultTake, reason: 'keeps the old fixed 1s take');
      expect(k.minValue, _minTake);
      expect(k.maxValue, _maxTake);
    }

    tester.view.reset();
    await tester.pump(const Duration(milliseconds: 300));
  });

  // Two knobs were inserted into a row that previously held only the labels,
  // AUTO buttons and the fader, inside a FractionallySizedBox(3/4). Overflow
  // is the obvious way for that to go wrong, and it is silent in release.
  for (final width in <double>[1024, 1400, 1948]) {
    testWidgets('the fader row lays out without overflow at $width',
        (tester) async {
      await loadAppFonts();
      tester.view.physicalSize = Size(width, 2200);
      tester.view.devicePixelRatio = 1.0;
      await tester
          .pumpWidget(labScaffold(child: const MixerPage(), width: width));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(_takeKnobs(tester).length, 6);

      tester.view.reset();
      await tester.pump(const Duration(milliseconds: 300));
    });
  }

  testWidgets('linked by default: turning one end moves the other',
      (tester) async {
    await _pumpMixer(tester);

    // Drive the first row's left knob through its onChanged, which is what a
    // drag ultimately calls.
    final before = _takeKnobs(tester);
    before.first.onChanged!(2.5);
    await tester.pumpAndSettle();

    final after = _takeKnobs(tester);
    expect(after[0].value, 2.5);
    expect(after[1].value, 2.5,
        reason: 'linked, so the far end follows and the take stays symmetric');

    // Other rows are independent of this one.
    expect(after[2].value, _defaultTake);

    tester.view.reset();
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('unlinking lets the two ends differ, relinking resyncs them',
      (tester) async {
    await _pumpMixer(tester);

    // One icon beside each knob: two per row, six in all, linked at start.
    final links = find.byIcon(Icons.link);
    expect(links, findsNWidgets(6));
    await tester.tap(links.first, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Both of that row's icons flip together — they show one shared state.
    expect(find.byIcon(Icons.link_off), findsNWidgets(2));

    _takeKnobs(tester).first.onChanged!(3.0);
    await tester.pumpAndSettle();

    var knobs = _takeKnobs(tester);
    expect(knobs[0].value, 3.0);
    expect(knobs[1].value, _defaultTake,
        reason: 'unlinked, so the far end holds its own value');

    // Re-link: the far end adopts A's time rather than staying visibly
    // different while the icon claims they are linked. Either icon does it.
    await tester.tap(find.byIcon(Icons.link_off).last, warnIfMissed: false);
    await tester.pumpAndSettle();

    knobs = _takeKnobs(tester);
    expect(knobs[0].value, 3.0);
    expect(knobs[1].value, 3.0);

    tester.view.reset();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
