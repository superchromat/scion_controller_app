// Design-lab render harness.
//
// Renders self-contained layout experiments to PNGs via the golden pipeline
// (`flutter test --update-goldens`). Reuses the REAL design-system primitives
// (grid tokens, neumorphic card/inset, panel, typography, rotary knob) so the
// aesthetics match the shipping app, while standing in lightweight static
// controls for the network-coupled ones.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:SCION_Controller/lighting_settings.dart';
import 'package:SCION_Controller/network.dart';
import 'package:SCION_Controller/grid.dart';

const Color kAppBackground = Color(0xFF232326);

bool _fontsLoaded = false;

Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final dir = Directory.current.path;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
    }
    await loader.load();
  }

  // Two weights, matching pubspec.yaml. Keep in step with it.
  await load('DINPro', [
    'assets/fonts/FF_DIN_Pro_Regular_Italic.otf',
    'assets/fonts/FF_DIN_Pro_Bold_Italic.otf',
  ]);
}

/// Wrap a page-level widget in the providers + grid it expects, at a fixed size.
Widget labScaffold({required Widget child, required double width}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LightingSettings>(create: (_) => LightingSettings()),
      // Bare, unconnected Network — only opens a socket on connect(), so it's
      // inert here but satisfies widgets that read<Network>() (e.g. OSC knobs).
      ChangeNotifierProvider<Network>(create: (_) => Network()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kAppBackground,
        fontFamily: 'DINPro',
      ),
      // NO GridProvider here. The real app (main.dart) has none above its
      // pages — each page installs its own from its own LayoutBuilder. An
      // outer provider here silently supplied tokens to every widget that
      // resolves them outside a page's provider, hiding the exact fallback
      // divergence that shows up in production.
      //
      // The nav rail is subtracted for the same reason: pages see the width
      // left over after the rail, not the window width.
      home: Scaffold(
        backgroundColor: kAppBackground,
        body: Row(
          children: [
            SizedBox(width: width >= 1000 ? 190.0 : 84.0),
            Expanded(child: child),
          ],
        ),
      ),
    ),
  );
}

/// Pump [child] at [size] and write a golden PNG at [goldenPath].
Future<void> shoot(
  WidgetTester tester, {
  required Widget child,
  required Size size,
  required String goldenPath,
}) async {
  await loadAppFonts();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(labScaffold(child: child, width: size.width));
  await tester.pump(const Duration(milliseconds: 50));
  await expectLater(
    find.byType(MediaQuery).first,
    matchesGoldenFile(goldenPath),
  );
}
