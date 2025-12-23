import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';

import 'network.dart';
import 'network_selection.dart';
import 'file_selection.dart';
import 'setup_page.dart';
import 'send_page.dart';
import 'osc_log.dart';
import 'osc_registry_viewer.dart';
import 'return_page.dart';
import 'knob_page.dart';
import 'lighting_settings.dart';
import 'colorspace_wheel_page.dart';
import 'din_cable_page.dart';

// A global messenger for surfacing errors unobtrusively during debugging.
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void _showGlobalErrorSnack(Object error, StackTrace stack) {
  return; // JOSH TODO
  if (!kDebugMode) return;
  // Keep the snack concise; full details are printed to the console.
  final msg = error.toString().split('\n').first;
  // Schedule after a frame to avoid setState during build.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final messenger = globalScaffoldMessengerKey.currentState;
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Unhandled error: $msg'),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red[700],
      ),
    );
  });
}

void _installGlobalErrorHooks() {
  // Route Flutter framework errors into the Zone and console.
  FlutterError.onError = (FlutterErrorDetails details) {
    // Always dump a rich report to the console for devs.
    FlutterError.dumpErrorToConsole(details);
    final stack = details.stack ?? StackTrace.current;
    // Forward into the zone so runZonedGuarded can also observe.
    if (Zone.current != Zone.root) {
      Zone.current.handleUncaughtError(details.exception, stack);
    }
    // Show a brief UI hint in debug mode.
    _showGlobalErrorSnack(details.exception, stack);
  };

  // Catch errors that escape the framework (e.g., microtasks, platform).
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('Uncaught platform error: $error\n$stack');
    _showGlobalErrorSnack(error, stack);
    // Return true to mark as handled and avoid default crash behavior in debug.
    return true;
  };

  // Make red error widgets more informative in debug builds.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!kDebugMode) return ErrorWidget(details.exception);
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontFamily: 'monospace',
    );
    return Container(
      color: const Color(0xFFB00020),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Text(
          'Error: ${details.exceptionAsString()}\n\n${details.stack?.toString() ?? ''}',
          style: textStyle,
        ),
      ),
    );
  };
}

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      const Size initialSize = Size(1200, 800);
      setWindowMinSize(initialSize);
      setWindowFrame(const Rect.fromLTWH(0, 0, 1200, 800));
    }

    _installGlobalErrorHooks();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Network>.value(value: Network()),
          ChangeNotifierProvider<LightingSettings>(create: (_) => LightingSettings()),
        ],
        child: const MyApp(),
      ),
    );
  }, (Object error, StackTrace stack) {
    // Last‑chance handler for anything not caught by FlutterError.onError.
    debugPrint('Uncaught zone error: $error\n$stack');
    _showGlobalErrorSnack(error, stack);
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MyAppState(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'scion',
        scaffoldMessengerKey: globalScaffoldMessengerKey,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: const Color(0xFF1C1C1E),
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFFFFF176),
            secondary: Colors.grey[400]!,
            surface: const Color(0xFF2C2C2E),
            onTertiaryContainer: const Color(0xFF1A1A1A),
            onPrimary: Colors.black,
            onSurface: Colors.white,
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[400]!),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
              foregroundColor: Colors.grey[300],
              textStyle: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        home: const MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  @override
  void notifyListeners() => super.notifyListeners();
}

/// Neumorphic styled navigation rail wrapper with global position tracking
class _NeumorphicNavRail extends StatefulWidget {
  final LightingSettings lighting;
  final Widget child;

  const _NeumorphicNavRail({
    required this.lighting,
    required this.child,
  });

  @override
  State<_NeumorphicNavRail> createState() => _NeumorphicNavRailState();
}

class _NeumorphicNavRailState extends State<_NeumorphicNavRail> {
  final GlobalKey _key = GlobalKey();
  Rect? _globalRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());
  }

  void _updateGlobalRect() {
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.hasSize) {
      final position = renderBox.localToGlobal(Offset.zero);
      final newRect = position & renderBox.size;
      if (_globalRect != newRect) {
        setState(() => _globalRect = newRect);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGlobalRect());

    return CustomPaint(
      key: _key,
      painter: _NavRailPainter(
        lighting: widget.lighting,
        globalRect: _globalRect,
      ),
      child: widget.child,
    );
  }
}

class _NavRailPainter extends CustomPainter {
  final LightingSettings lighting;
  final Rect? globalRect;

  _NavRailPainter({
    required this.lighting,
    this.globalRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Base gradient fill using Phong diffuse shading with global position
    const baseColor = Color(0xFF404044);
    final gradient = lighting.createPhongSurfaceGradient(
      baseColor: baseColor,
      intensity: 0.04,
      globalRect: globalRect,
    );
    final gradientPaint = Paint()
      ..shader = gradient.createShader(rect);

    canvas.drawRect(rect, gradientPaint);

    // Right edge shadow/highlight for depth
    final edgePaint = Paint()
      ..strokeWidth = 1.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.08),
        ],
        stops: const [0.0, 0.3, 1.0],
      ).createShader(rect);

    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      edgePaint,
    );

    // Noise texture overlay
    if (lighting.noiseImage != null) {
      final noisePaint = Paint()
        ..shader = ImageShader(
          lighting.noiseImage!,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
        )
        ..blendMode = BlendMode.overlay;

      canvas.drawRect(rect, noisePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _NavRailPainter oldDelegate) {
    return oldDelegate.lighting.lightPhi != lighting.lightPhi ||
        oldDelegate.lighting.lightTheta != lighting.lightTheta ||
        oldDelegate.lighting.lightDistance != lighting.lightDistance ||
        oldDelegate.globalRect != globalRect ||
        oldDelegate.lighting.noiseImage != lighting.noiseImage;
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;

  List<Widget> get pages {
    return [
      // 0 → System
      const SystemPage(),
      // 1–3 → Send 1–3
      for (var i = 1; i <= 3; i++) SendPage(key: ValueKey(i), pageNumber: i),
      // 4 → Return
      const ReturnPage(),
      // 5 → Setup
      const SetupPage(),
      // 6 → DIN Cable
      const DinCablePage(),
      // 7 → OSC Log
      OscLogTable(
        key: oscLogKey,
        onDownload: (bytes) {/* … */},
        isActive: selectedIndex == 7,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allPages = pages;
    return LayoutBuilder(builder: (context, constraints) {
      // Determine whether rail is extended
      final bool isRailExtended = constraints.maxWidth >= 1000;
      // Use the same constants passed to NavigationRail:
      const double railCollapsedWidth = 100;
      const double railExtendedWidth = 222;

      final lighting = context.watch<LightingSettings>();

      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SafeArea(
                    child: _NeumorphicNavRail(
                      lighting: lighting,
                      child: NavigationRail(
                        backgroundColor: Colors.transparent,
                        minWidth: railCollapsedWidth,
                        minExtendedWidth: railExtendedWidth,
                        extended: isRailExtended,
                        // Precisely constrain the leading section to the rail width:
                        leading: SizedBox(
                          width: isRailExtended
                              ? railExtendedWidth
                              : railCollapsedWidth,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(9, 0, 9, 0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(height: 8),
                                NetworkConnectionSection(),
                                SizedBox(height: 16),
                                FileManagementSection(),
                                SizedBox(height: 8),
                                Divider(color: Colors.grey),
                              ],
                            ),
                          ),
                        ),
                        selectedIndex: selectedIndex,
                        onDestinationSelected: (value) {
                          setState(() => selectedIndex = value);
                        },
                        destinations: const [
                          NavigationRailDestination(
                            icon: Icon(Icons.memory),
                            label: Text('System', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.output),
                            label: Text('Send 1', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.output),
                            label: Text('Send 2', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.output),
                            label: Text('Send 3', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.input),
                            label: Text('Return', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings),
                            label: Text('Setup', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.cable),
                            label: Text('DIN Cable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.view_list),
                            label: Text('OSC Log', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: IndexedStack(
                        index: selectedIndex.clamp(0, allPages.length - 1),
                        children: allPages,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}
