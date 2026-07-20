// Card titles are measured by eye against the card's edges, so what has to be
// right is where the INK lands, not where the layout box lands. These tests
// measure painted positions.
//
// Panel titles no longer take part in that left edge at all — they are centred
// caps legends (see GridTokens.textPanelTitle), so what is tested here is that
// they sit on the panel's true centre.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:SCION_Controller/font_metrics.dart';
import 'package:SCION_Controller/grid.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/lighting_settings.dart';
import 'package:SCION_Controller/panel.dart';
import 'package:SCION_Controller/grade_wheels.dart';
import 'package:SCION_Controller/network.dart';

const double _width = 1200; // u = 12

Widget _harness(List<String> cardTitles, List<String> panelTitles) {
  return MaterialApp(
    home: ChangeNotifierProvider<LightingSettings>(
      create: (_) => LightingSettings(),
      child: GridProvider(
        tokens: GridTokens(_width),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: _width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cardTitle in cardTitles)
                  LabeledCard(
                    title: cardTitle,
                    child: GridRow(
                      columns: 12,
                      cells: [
                        for (final t in panelTitles)
                          (
                            span: 12 ~/ panelTitles.length,
                            child: Panel(
                              title: t,
                              child: const SizedBox(height: 40),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Where [title]'s first glyph actually starts painting: the (already
/// bearing-corrected) layout box, plus the bearing the font then adds back.
double _inkLeft(WidgetTester tester, String title, TextStyle style) {
  return tester.getTopLeft(find.text(title)).dx +
      FontMetrics.leftBearing(title, style);
}

void main() {
  final t = GridTokens(_width);
  final edge = t.cardTitleAlignToPanelTitle; // 3u = 36 at u = 12

  testWidgets(
      'card titles agree across first letters of very different bearing',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(_width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // 'H' is 0.103em and 'V' is 0.008em in DIN Pro — the widest spread in the
    // uppercase alphabet, and 2.3px apart at a 2.0u card title on u = 12.
    const titles = ['Hue', 'Video', 'Texture', 'Color'];
    await tester.pumpWidget(_harness(titles, ['Global']));
    await tester.pump(const Duration(milliseconds: 300)); // resize debounce

    for (final title in titles) {
      // Sub-pixel tolerance: all four derive from the same tokens, so any real
      // drift is a whole pixel or more.
      expect(_inkLeft(tester, title, t.textTitle),
          moreOrLessEquals(edge, epsilon: 0.01),
          reason: 'card title "$title"');
    }
  });

  testWidgets('card title sits as far from the card top as from its left',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(_width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(['DAC'], ['Global']));
    await tester.pump(const Duration(milliseconds: 300));

    final cardTop = tester.getTopLeft(find.byType(LabeledCard).first).dy;
    final box = tester.getRect(find.text('DAC'));

    // Top of the CAPITALS, not of the line box: the ascender reaches higher
    // than cap height and no reader measures to it.
    final probe = TextPainter(
      text: TextSpan(text: 'DAC', style: t.textTitle.copyWith(height: 1.0)),
      textDirection: TextDirection.ltr,
      textHeightBehavior: CapCenteredText.trim,
      maxLines: 1,
    )..layout();
    final capTop = box.top +
        probe.computeDistanceToActualBaseline(TextBaseline.alphabetic) -
        CapCenteredText.capHeightEm * t.textTitle.fontSize!;

    expect(capTop - cardTop, moreOrLessEquals(edge, epsilon: 0.01));
  });

  testWidgets('panel title is centred on the panel, caps, at caption size',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(_width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(['Color'], ['Global', 'Per-channel']));
    await tester.pump(const Duration(milliseconds: 300));

    // Uppercased at the widget, so the source keeps its readable casing.
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('Global'), findsNothing);

    final style = tester.widget<Text>(find.text('GLOBAL')).style!;
    expect(style.fontSize, t.textPanelTitle.fontSize);

    final panel = tester.getRect(find.byType(Panel).first);
    final box = tester.getRect(find.text('GLOBAL'));
    // Glyph centre, not box centre: trailing letterSpacing pads the box on the
    // right only, so the two differ by half a tracking step.
    final inkCentre = box.center.dx - t.panelTitleTracking / 2;

    expect(inkCentre, moreOrLessEquals(panel.center.dx, epsilon: 0.01));
  });

  test('the space above a panel legend is the space left of its content', () {
    expect(t.panelTitleCapTop, t.panelContentInset);
  });

  testWidgets('every panel legend sits the same distance below its panel top',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(_width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(['Color'], ['Global', 'Blur']));
    await tester.pump(const Duration(milliseconds: 300));

    final capInset = CapCenteredText.capTopInset(t.textPanelTitle);
    for (final (i, label) in ['GLOBAL', 'BLUR'].indexed) {
      final panelTop = tester.getRect(find.byType(Panel).at(i)).top;
      final capTop = tester.getRect(find.text(label)).top + capInset;
      expect(capTop - panelTop,
          moreOrLessEquals(t.panelTitleCapTop, epsilon: 0.01),
          reason: label);
    }
  });

  testWidgets('a GradeZone legend sits where a Panel legend does',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(_width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        // Material: the zones' knobs contain TextFields, which assert
        // without one.
        home: Material(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LightingSettings>(
                  create: (_) => LightingSettings()),
              ChangeNotifierProvider<Network>(create: (_) => Network()),
            ],
            child: GridProvider(
              tokens: GridTokens(_width),
              child: const SizedBox(
                height: 500,
                child: GradeWheels(basePath: '/send/1'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final capInset = CapCenteredText.capTopInset(t.textPanelTitle);
    for (final (i, label) in ['SHADOWS', 'MIDTONES', 'HIGHLIGHTS'].indexed) {
      final zoneTop = tester.getRect(find.byType(GradeZone).at(i)).top;
      final capTop = tester.getRect(find.text(label)).top + capInset;
      expect(
          capTop - zoneTop, moreOrLessEquals(t.panelTitleCapTop, epsilon: 0.01),
          reason: label);
    }
  });
}
