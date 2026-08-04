import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:SCION_Controller/arrow.dart';

/// Two tiles side by side in a keyed Stack, laid out so their positions depend
/// on the surface width — the same way the System Overview tiles flex.
class _Diagram extends StatelessWidget {
  final GlobalKey spaceKey, aKey, bKey;
  const _Diagram(
      {required this.spaceKey, required this.aKey, required this.bKey});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          key: spaceKey,
          children: [
            Column(
              children: [
                Row(children: [
                  Expanded(child: SizedBox(key: aKey, height: 40)),
                  const Expanded(child: SizedBox(height: 40)),
                ]),
                Row(children: [
                  const Expanded(child: SizedBox(height: 40)),
                  Expanded(child: SizedBox(key: bKey, height: 40)),
                ]),
              ],
            ),
          ],
        ),
      );
}

void main() {
  testWidgets('cable endpoints follow the tiles as the window width changes',
      (tester) async {
    final spaceKey = GlobalKey();
    final aKey = GlobalKey();
    final bKey = GlobalKey();

    final painter = ArrowsPainter(
      spaceKey: spaceKey,
      connections: [
        ArrowConnection(
          fromKey: aKey,
          toKey: bKey,
          fromFrac: const Offset(0.5, 1),
          toFrac: const Offset(0.5, 0),
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(800, 600));
    await tester
        .pumpWidget(_Diagram(spaceKey: spaceKey, aKey: aKey, bKey: bKey));

    final narrow = painter.resolve();
    expect(narrow, hasLength(1));
    // Tile A spans the left half (0..400), so its bottom-centre is x=200;
    // tile B spans the right half, so its top-centre is x=600.
    expect(narrow.single.from.dx, 200);
    expect(narrow.single.to.dx, 600);

    // Widen: with no rebuild of the painter, resolving again must give the new
    // geometry. This is what makes the cables track a drag.
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pump();

    final wide = painter.resolve();
    expect(wide.single.from.dx, 300);
    expect(wide.single.to.dx, 900);

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('resolves to nothing before the tiles have been laid out',
      (tester) async {
    final painter = ArrowsPainter(
      spaceKey: GlobalKey(),
      connections: [
        ArrowConnection(
          fromKey: GlobalKey(),
          toKey: GlobalKey(),
          fromFrac: Offset.zero,
          toFrac: Offset.zero,
        ),
      ],
    );
    expect(painter.resolve(), isEmpty);
  });
}
