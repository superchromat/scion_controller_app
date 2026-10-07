// Every format row in the 2x2 source selector must render with identical text
// metrics, whichever tile it is in.
//
// The Return tile used to carry a local _greenText that restated the family and
// size and added fontWeight: w600, while inputs 1-3 used kInputRowStyle
// (regular weight, height 1.32, forced strut). The Return tile was visibly
// bolder and on different line spacing than its neighbours. Asserting on the
// style rather than a golden because Courier is not loaded in the test
// environment, so a rendered comparison is tofu and proves nothing about weight.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/input_label_field.dart';
import 'package:SCION_Controller/osc_registry.dart';
import 'package:SCION_Controller/send_source_selector.dart';

import 'design_lab/harness.dart';

void _seed() {
  final r = OscRegistry();
  void set(String a, Object v) {
    r.registerAddress(a);
    r.dispatch(a, <Object?>[v]);
  }

  for (final i in [1, 2, 3]) {
    set('/input/$i/connected', true);
    set('/input/$i/resolution', '1920x1080');
    set('/input/$i/framerate', 24.0);
    set('/input/$i/bit_depth', 8);
    set('/input/$i/colorspace', 'YUV');
    set('/input/$i/chroma_subsampling', '4:2:2');
  }
  set('/analog_format/resolution', '1920x1080');
  set('/analog_format/framerate', 24.0);
  set('/analog_format/bit_depth', 12);
  set('/analog_format/colorspace', 'YUV');
  set('/analog_format/chroma_subsampling', '4:4:4');
}

void main() {
  testWidgets('input and Return format rows share one text style',
      (tester) async {
    await loadAppFonts();
    _seed();

    await tester.pumpWidget(labScaffold(
      width: 800,
      child: const Center(
        child: SizedBox(
            width: 300, child: SendSourceSelector2x2(pageNumber: 1)),
      ),
    ));
    await tester.pumpAndSettle();

    // The format rows are the ones carrying kInputRowStyle's colour.
    final rows = tester
        .widgetList<Text>(find.byType(Text))
        .where((w) => w.style?.color == kInputRowStyle.color)
        .toList();

    // Five rows per tile — name, resolution, rate, depth, colourspace — across
    // three inputs and the Return. The Return used to render only four,
    // silently omitting the name row.
    expect(rows.length, 20,
        reason: 'four tiles x five rows, all on the same style');
    expect(
      rows.where((w) => w.data == 'Return').length,
      1,
      reason: "the Return tile carries a fixed name row like the inputs' "
          'editable one',
    );

    for (final row in rows) {
      final s = row.style!;
      expect(s.fontWeight, kInputRowStyle.fontWeight,
          reason: 'weight must not vary between tiles: "${row.data}"');
      expect(s.fontSize, kInputRowStyle.fontSize, reason: '"${row.data}"');
      expect(s.fontFamily, kInputRowStyle.fontFamily, reason: '"${row.data}"');
      expect(s.height, kInputRowStyle.height, reason: '"${row.data}"');
      expect(row.strutStyle, kInputRowStrut,
          reason: 'forced strut keeps rows evenly spaced: "${row.data}"');
    }
  });
}
