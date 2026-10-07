// Every tile on the System Overview shows the same five text rows on the same
// slots and in the same style.
//
// The Send/Return/Out tiles previously used a local _systemTextStyle that
// restated the metrics with fontWeight: w600 and no strut, and carried no name
// row at all — four rows against the input tiles' five, in a heavier font, on
// different line spacing. Asserted rather than golden-compared because Courier
// is not loaded in the test environment, so a render proves nothing about
// weight.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/input_label_field.dart';
import 'package:SCION_Controller/osc_registry.dart';
import 'package:SCION_Controller/system_overview_tiles.dart';

import 'design_lab/harness.dart';

void _seed() {
  final r = OscRegistry();
  void set(String a, Object v) {
    r.registerAddress(a);
    r.dispatch(a, <Object?>[v]);
  }

  set('/output/connected', true);
  set('/output/resolution', '1920x1080');
  set('/output/framerate', 24.0);
  set('/output/bit_depth', 10);
  set('/output/colorspace', 'YUV');
  set('/output/chroma_subsampling', '4:4:4');
}

void main() {
  testWidgets('the Out tile carries five rows in the shared style',
      (tester) async {
    await loadAppFonts();
    _seed();

    await tester.pumpWidget(labScaffold(
      width: 400,
      child: const Center(child: HDMIOutTile()),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'a fifth row must still fit the 100px tile');

    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .where((w) => w.style?.fontFamily == kInputRowStyle.fontFamily)
        .toList();

    // name, resolution, rate, depth, colourspace, subsampling — the last two
    // share a slot, so six Texts across five rows.
    expect(rows.map((w) => w.data), contains('Out'),
        reason: 'the Out tile names itself like the inputs do');

    for (final row in rows) {
      final s = row.style!;
      expect(s.fontWeight, kInputRowStyle.fontWeight,
          reason: 'weight must match the input tiles: "${row.data}"');
      expect(s.fontSize, kInputRowStyle.fontSize, reason: '"${row.data}"');
      expect(s.height, kInputRowStyle.height, reason: '"${row.data}"');
    }
  });

  testWidgets('Send and Return tiles keep their four rows', (tester) async {
    await loadAppFonts();
    _seed();

    // Deliberately NOT given a name row: the request was to change the Out
    // tile only. VideoFormatTile backs all three, so this pins the scope.
    for (final tile in <Widget>[
      const AnalogSendTile(index: 1),
      const ReturnTile(),
    ]) {
      await tester
          .pumpWidget(labScaffold(width: 400, child: Center(child: tile)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final names =
          tester.widgetList<Text>(find.byType(Text)).map((w) => w.data);
      expect(names.contains('Send 1'), isFalse, reason: '$names');
      expect(names.contains('Return'), isFalse, reason: '$names');
    }
  });
}
