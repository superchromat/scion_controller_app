import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:SCION_Controller/labeled_card.dart';
import 'package:SCION_Controller/lighting_settings.dart';
import 'package:SCION_Controller/network.dart';
import 'package:SCION_Controller/send_source_selector.dart';

/// The Input Source card's five source tiles (4 inputs + Return).
///
/// Guards a regression: wrapping the tile in a Stack to overlay its border made
/// the tile size to its own content instead of to its grid cell, because Stack
/// defaults to StackFit.loose. The Return tile collapsed — its content has
/// nothing making it fill, unlike an input's.
void main() {
  testWidgets('all five source tiles fill their cells equally',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Network>(create: (_) => Network()),
          ChangeNotifierProvider<LightingSettings>(
              create: (_) => LightingSettings()),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SendSourceSelector(pageNumber: 1)),
        ),
      ),
    );
    await tester.pump();

    // One NeumorphicInset per tile face.
    final faces = find.byType(NeumorphicInset).evaluate().toList();
    expect(faces, hasLength(5), reason: '4 inputs + Return');

    final sizes = faces.map((e) => (e.renderObject! as RenderBox).size).toList();

    // Every tile is given the row's full height by its cell. A tile that sizes
    // to its own content instead of its cell shows up here as a short tile.
    // (Widths legitimately differ a little: five span-3 cells in a 12-column
    // grid do not divide evenly.)
    final heights = sizes.map((s) => s.height).toSet();
    expect(heights, hasLength(1),
        reason: 'every tile must fill its cell height; got $sizes');

    // And none collapsed.
    expect(heights.single, greaterThan(50));
    for (final s in sizes) {
      expect(s.width, greaterThan(50), reason: 'got $sizes');
    }
  });
}
