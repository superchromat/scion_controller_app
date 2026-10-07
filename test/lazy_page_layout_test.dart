import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/lazy_page_layout.dart';

/// Records the constraints its build sees, and how many times it was laid out.
class _Probe extends StatelessWidget {
  final List<BoxConstraints> seen;
  const _Probe(this.seen);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          seen.add(constraints);
          return const SizedBox.expand();
        },
      );
}

void main() {
  Future<void> pumpStack(
    WidgetTester tester, {
    required int index,
    required List<BoxConstraints> a,
    required List<BoxConstraints> b,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: IndexedStack(
          index: index,
          children: [
            LazyPageLayout(active: index == 0, child: _Probe(a)),
            LazyPageLayout(active: index == 1, child: _Probe(b)),
          ],
        ),
      ),
    );
  }

  testWidgets('an inactive page is not re-laid-out when the window resizes',
      (tester) async {
    final a = <BoxConstraints>[];
    final b = <BoxConstraints>[];

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpStack(tester, index: 0, a: a, b: b);
    a.clear();
    b.clear();

    // Resize repeatedly with page 0 active.
    for (double w = 1210; w <= 1300; w += 10) {
      await tester.binding.setSurfaceSize(Size(w, 800));
      await tester.pump();
    }

    expect(a, isNotEmpty, reason: 'the active page must track the new width');
    expect(a.last.maxWidth, 1300);
    expect(b, isEmpty,
        reason: 'the inactive page must not re-layout during a resize');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('a page picks up the current width when it becomes active',
      (tester) async {
    final a = <BoxConstraints>[];
    final b = <BoxConstraints>[];

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpStack(tester, index: 0, a: a, b: b);

    // Page 1 was laid out once, at 1200, while it was inactive.
    expect(b.single.maxWidth, 1200);
    b.clear();

    await tester.binding.setSurfaceSize(const Size(1600, 800));
    await tester.pump();
    expect(b, isEmpty, reason: 'still inactive, so still frozen');

    // Switching to it must hand it the CURRENT width, not the frozen one.
    await pumpStack(tester, index: 1, a: a, b: b);
    expect(b, isNotEmpty);
    expect(b.last.maxWidth, 1600);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('an inactive page still occupies its slot', (tester) async {
    final a = <BoxConstraints>[];
    final b = <BoxConstraints>[];

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    await pumpStack(tester, index: 0, a: a, b: b);

    // Both LazyPageLayouts must be sized by the stack, so nothing downstream
    // reads an unset size.
    for (final e in find.byType(LazyPageLayout).evaluate()) {
      final box = e.renderObject! as RenderBox;
      expect(box.hasSize, isTrue);
      expect(box.size, const Size(1200, 800));
    }

    await tester.binding.setSurfaceSize(null);
  });
}
