// The mixer's opening A/B assignment: each row's identity source on A, the
// Return column on B, everything else unassigned.
//
// Tested against MixerPage.defaultGroup per (row, column) rather than by
// counting selected buttons in the tree — a count of "three A's" passes even
// if every row put A in the same wrong column, which is exactly the off-by-one
// worth catching.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/app_button.dart';
import 'package:SCION_Controller/mixer_page.dart';

import 'design_lab/harness.dart';

void main() {
  group('MixerPage.defaultGroup', () {
    test('every cell of every row', () {
      // Rows are sends 1-3; columns are sources [1, 2, 3, 4] with 4 = Return.
      const expected = <int, Map<int, ABGroup>>{
        1: {
          1: ABGroup.a,
          2: ABGroup.none,
          3: ABGroup.none,
          4: ABGroup.b,
        },
        2: {
          1: ABGroup.none,
          2: ABGroup.a,
          3: ABGroup.none,
          4: ABGroup.b,
        },
        3: {
          1: ABGroup.none,
          2: ABGroup.none,
          3: ABGroup.a,
          4: ABGroup.b,
        },
      };

      for (final row in expected.entries) {
        for (final cell in row.value.entries) {
          expect(
            MixerPage.defaultGroup(row.key, cell.key),
            cell.value,
            reason: 'Send ${row.key} row, '
                '${MixerPage.sourceLabel(cell.key)} column',
          );
        }
      }
    });

    test('identity and Return never collide', () {
      // Relied on by defaultGroup returning a single answer per cell: the
      // Return column is never a row's identity source.
      for (int targetSend = 1; targetSend <= 3; targetSend++) {
        expect(MixerPage.isReturn(targetSend), isFalse);
      }
    });

    test('every row opens with exactly one A and one B', () {
      for (int targetSend = 1; targetSend <= 3; targetSend++) {
        final groups = MixerPage.sources
            .map((s) => MixerPage.defaultGroup(targetSend, s))
            .toList();
        expect(groups.where((g) => g == ABGroup.a).length, 1);
        expect(groups.where((g) => g == ABGroup.b).length, 1);
      }
    });
  });

  testWidgets('the built page reflects those defaults', (tester) async {
    await loadAppFonts();
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(labScaffold(child: const MixerPage(), width: 1400));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    // The A/B toggle is the only AppButton in a mixer cell, so a selected one
    // names that cell's group. Three rows, one A and one B each.
    final selected = <String>[];
    void walk(Element e) {
      final w = e.widget;
      if (w is AppButton && w.selected && (w.label == 'A' || w.label == 'B')) {
        selected.add(w.label!);
      }
      e.visitChildren(walk);
    }

    tester.element(find.byType(MixerPage)).visitChildren(walk);

    expect(selected.where((s) => s == 'A').length, 3);
    expect(selected.where((s) => s == 'B').length, 3);
    expect(tester.takeException(), isNull);

    tester.view.reset();
    await tester.pump(const Duration(milliseconds: 300));
  });
}
