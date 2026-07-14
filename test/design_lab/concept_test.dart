import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';
import 'concept.dart';

void main() {
  testWidgets('concept: signal desk (send 1)', (tester) async {
    await shoot(tester,
        child: const SignalDesk(),
        size: const Size(1680, 1050),
        goldenPath: 'shots/concept_signal_desk.png');
  });

  testWidgets('concept: capture desk (return)', (tester) async {
    await shoot(tester,
        child: const CaptureDesk(),
        size: const Size(1680, 1000),
        goldenPath: 'shots/concept_capture_desk.png');
  });
}
