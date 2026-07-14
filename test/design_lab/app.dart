// Runnable design-lab prototype (NOT a golden test).
//
//   flutter run -t test/design_lab/app.dart -d macos     # native window
//   flutter run -t test/design_lab/app.dart -d chrome    # browser
//
// Shows the Send-1 "Signal Desk" and Return "Capture Desk" concepts live and
// resizable, using the real neumorphic design system + DINPro (bundled fonts
// load automatically when run as an app). Visual prototype only — the controls
// are not wired to a device.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:SCION_Controller/lighting_settings.dart';
import 'package:SCION_Controller/grid.dart';

import 'concept.dart';

void main() => runApp(const _DesignLabApp());

class _DesignLabApp extends StatefulWidget {
  const _DesignLabApp();
  @override
  State<_DesignLabApp> createState() => _DesignLabAppState();
}

class _DesignLabAppState extends State<_DesignLabApp> {
  int _surface = 0; // 0 = Send 1, 1 = Return

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LightingSettings>(
      create: (_) => LightingSettings(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF141416),
          fontFamily: 'DINPro',
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFF141416),
          body: Column(
            children: [
              _SurfaceSwitcher(
                index: _surface,
                onChanged: (i) => setState(() => _surface = i),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => GridProvider(
                    tokens: GridTokens(c.maxWidth),
                    child: _surface == 0 ? const SignalDesk() : const CaptureDesk(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SurfaceSwitcher extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  const _SurfaceSwitcher({required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(int i, String label) {
      final on = i == index;
      return GestureDetector(
        onTap: () => onChanged(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: on ? const Color(0xFFF0B830) : const Color(0xFF212124),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(label,
              style: TextStyle(
                  color: on ? Colors.black : const Color(0xFF9A9AA0),
                  fontFamily: 'DINPro',
                  fontWeight: FontWeight.w600)),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0E0E10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(children: [tab(0, 'Send 1'), tab(1, 'Return')]),
    );
  }
}
