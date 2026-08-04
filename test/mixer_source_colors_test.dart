import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/mixer_page.dart';
import 'package:SCION_Controller/signal_colors.dart';

void main() {
  test('every mixer column is tinted to match its own label', () {
    // The bug this guards: every column was tinted with the send colour, so
    // the Return column read as a fourth send.
    for (final source in MixerPage.sources) {
      final label = MixerPage.sourceLabel(source);
      final color = MixerPage.sourceColor(source);
      if (label == 'Return') {
        expect(color, kReturnSignalColor, reason: 'Return column must be blue');
      } else {
        expect(color, kSendSignalColor, reason: '$label must be amber');
      }
    }
  });

  test('exactly one column is the return', () {
    expect(MixerPage.sources.where(MixerPage.isReturn), hasLength(1));
    expect(MixerPage.sources.where((s) => !MixerPage.isReturn(s)), hasLength(3));
  });

  test('the two signal colours are distinct', () {
    expect(kSendSignalColor, isNot(kReturnSignalColor));
  });
}
