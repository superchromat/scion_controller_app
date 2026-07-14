import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/shape.dart';
import 'package:SCION_Controller/send_effects.dart';
import 'package:SCION_Controller/osc_widget_binding.dart';
import 'package:SCION_Controller/grid.dart';

import 'harness.dart';

Widget _sectionHeader(BuildContext context, String title) {
  final t = GridProvider.of(context);
  return Padding(
    padding: EdgeInsets.only(top: t.md, bottom: t.sm),
    child: Row(children: [
      Text(title, style: t.textLabel.copyWith(fontWeight: FontWeight.w700)),
      SizedBox(width: t.sm),
      Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.15))),
    ]),
  );
}

void main() {
  // BEFORE: the COMPLETE current Shape control set (Send 1) — the base Shape
  // (scale/pos/crop/rotation) plus the Warp — Affine and Warp — LUT panels,
  // exactly as send_page.dart composes them inside the Shape card.
  testWidgets('shape before — send 1', (tester) async {
    final child = Builder(builder: (context) {
      final t = GridProvider.of(context);
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(t.md),
          child: OscPathSegment(
            segment: 'send/1',
            child: LabeledCard(
              title: 'Shape',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Shape(pageNumber: 1),
                  _sectionHeader(context, 'Warp — Affine'),
                  const WarpAffinePanel(),
                  _sectionHeader(context, 'Warp — LUT'),
                  const WarpLutPanel(),
                ],
              ),
            ),
          ),
        ),
      );
    });
    await shoot(tester,
        child: child, size: const Size(680, 720),
        goldenPath: 'shots/shape_before_send1.png');
  });

  // AFTER: the integrated Shape control — big canvas on the entire left side,
  // ALL knobs (incl. affine/warp) stacked on the right, two-way bound.
  testWidgets('shape after — send 1', (tester) async {
    final child = Builder(builder: (context) {
      final t = GridProvider.of(context);
      return SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(t.md),
          child: const OscPathSegment(
            segment: 'send/1',
            child: LabeledCard(title: 'Shape', child: Shape(pageNumber: 1)),
          ),
        ),
      );
    });
    await shoot(tester,
        child: child, size: const Size(1180, 1120),
        goldenPath: 'shots/shape_after_send1.png');
  });
}
