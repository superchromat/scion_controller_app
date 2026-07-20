import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';

import 'about.dart';
import 'disconnected_scrim.dart';
import 'discovery.dart';
import 'network.dart';
import 'network_selection.dart';
import 'setup_page.dart';
import 'system_page.dart';
import 'video_format_selection.dart';
import 'asset_files_page.dart';
import 'send_page.dart';
import 'mixer_page.dart';
import 'osc_log.dart';
import 'return_page.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';

// A global messenger for surfacing errors unobtrusively during debugging.
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Debug/testing toggle: set false to hide disconnected UI scrim + dimming.
const bool kShowDisconnectedOverlay = true;

/// Returns true for network noise we expect during idle auto-reconnects
/// (e.g., no device reachable on the network). These should not surface a
/// user-facing snackbar while the app silently retries.
bool _shouldSilenceError(Object error) {
  // All socket/OS errors are network-level; the reconnect logic handles them.
  if (error is SocketException) return true;
  if (error is OSError) return true;
  return false;
}

void _showGlobalErrorSnack(Object error, StackTrace stack) {
  if (!kDebugMode) return;
  if (_shouldSilenceError(error)) return;
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
      fontSize: 11,
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
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (!kIsWeb && Platform.isAndroid) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      const Size initialSize = Size(1200, 800);
      setWindowMinSize(initialSize);
      setWindowFrame(const Rect.fromLTWH(0, 0, 1200, 800));
    }

    _installGlobalErrorHooks();

    // Seed the analog Send/Return format defaults so the send/return tiles show
    // a real format in demo mode (before any device /sync). Harmless when a
    // device is present — it only fills empty entries, so /sync still wins.
    seedAnalogFormatDefaults();

    final network = Network();
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<Network>.value(value: network),
          // Continuously discovers SCION devices and auto-connects (starts
          // immediately, not lazily).
          ChangeNotifierProvider<ScionDiscovery>(
            create: (_) => ScionDiscovery(network),
            lazy: false,
          ),
          ChangeNotifierProvider<LightingSettings>(
              create: (_) => LightingSettings()),
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
        title: 'SCION',
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

class _NeumorphicNavRailState extends State<_NeumorphicNavRail>
    with GlobalRectTracking<_NeumorphicNavRail> {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: globalRectKey,
      painter: _NavRailPainter(
        lighting: widget.lighting,
        globalRect: trackedGlobalRect,
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
    final gradientPaint = Paint()..shader = gradient.createShader(rect);

    canvas.drawRect(rect, gradientPaint);

    // Left edge shadow/highlight to sit on the same depth plane as raised cards
    final leftBandRect = Rect.fromLTWH(0, 0, 10, size.height);
    final leftBandPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.black.withValues(alpha: 0.16),
          Colors.black.withValues(alpha: 0.08),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 1.0],
      ).createShader(leftBandRect);
    canvas.drawRect(leftBandRect, leftBandPaint);

    final leftEdgePaint = Paint()
      ..strokeWidth = 1.0
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.035),
          Colors.white.withValues(alpha: 0.02),
          Colors.black.withValues(alpha: 0.05),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawLine(
      const Offset(0.5, 0),
      Offset(0.5, size.height),
      leftEdgePaint,
    );

    // Right edge: a soft neumorphic lip using the same shading as the control
    // slots — a gentle highlight on the raised face rolling into a darker edge —
    // so the rail reads as a rounded panel edge the page sits just below.
    const double lipW = 12.0;
    final lipRect = Rect.fromLTWH(size.width - lipW, 0, lipW, size.height);
    // Highlight on the lit face, peaking just inside the edge.
    final lipHighlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.05),
          Colors.white.withValues(alpha: 0.09),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6, 0.85, 1.0],
      ).createShader(lipRect);
    canvas.drawRect(lipRect, lipHighlightPaint);
    // Darker roll-off right at the edge for depth.
    final edgeShadowRect = Rect.fromLTWH(size.width - 3, 0, 3, size.height);
    final edgeShadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.28),
        ],
      ).createShader(edgeShadowRect);
    canvas.drawRect(edgeShadowRect, edgeShadowPaint);

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
      // 4 → Mixer
      const MixerPage(),
      // 5 → Return
      const ReturnPage(),
      // 6 → Setup
      SetupPage(isActive: selectedIndex == 6),
      // 7 → Files
      AssetFilesPage(isActive: selectedIndex == 7),
      // 8 → OSC Log
      OscLogTable(
        key: oscLogKey,
        onDownload: (bytes) {/* … */},
        isActive: selectedIndex == 8,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allPages = pages;
    return LayoutBuilder(builder: (context, constraints) {
      final network = context.watch<Network>();
      final discovery = context.watch<ScionDiscovery>();
      final showDisconnectedOverlay = kShowDisconnectedOverlay &&
          !network.isConnected &&
          !discovery.demoMode;
      // Determine whether rail is extended
      final bool isRailExtended = constraints.maxWidth >= 1000;
      // Use the same constants passed to NavigationRail:
      const double railCollapsedWidth = 84;
      const double railExtendedWidth = 190;
      const selectedRailLabelStyle = TextStyle(
        fontFamily: 'DINPro',
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.10,
        color: Color(0xFFF1F1F3),
      );
      const unselectedRailLabelStyle = TextStyle(
        fontFamily: 'DINPro',
        fontSize: 17,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.10,
        color: Color(0xFFD2D2D4),
      );

      final lighting = context.watch<LightingSettings>();

      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  _NeumorphicNavRail(
                    lighting: lighting,
                    child: SizedBox(
                      width: isRailExtended
                          ? railExtendedWidth
                          : railCollapsedWidth,
                      child: Column(
                        children: [
                          Expanded(
                            child: SafeArea(
                              child: NavigationRail(
                                backgroundColor: Colors.transparent,
                                minWidth: railCollapsedWidth,
                                minExtendedWidth: railExtendedWidth,
                                extended: isRailExtended,
                                groupAlignment: -1.0,
                                selectedLabelTextStyle: selectedRailLabelStyle,
                                unselectedLabelTextStyle:
                                    unselectedRailLabelStyle,
                                leading: SizedBox(
                                  width: isRailExtended
                                      ? railExtendedWidth
                                      : railCollapsedWidth,
                                  child: Padding(
                                    // Extra right inset so the Network Address box clears
                                    // the 12px neumorphic lip on the rail's right edge.
                                    padding:
                                        const EdgeInsets.fromLTRB(9, 0, 16, 0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: const [
                                        SizedBox(height: 8),
                                        NetworkConnectionSection(),
                                        SizedBox(height: 16),
                                        _FadedRailDivider(),
                                      ],
                                    ),
                                  ),
                                ),
                                selectedIndex: selectedIndex,
                                onDestinationSelected: (value) {
                                  setState(() => selectedIndex = value);
                                },
                                destinations: [
                                  const NavigationRailDestination(
                                    icon: Icon(Icons.memory),
                                    label: Text('System'),
                                  ),
                                  NavigationRailDestination(
                                    icon: const Icon(Icons.output,
                                        color: Color(0xFFC9B066)),
                                    label: const Text('Send 1',
                                        style: TextStyle(
                                            color: Color(0xFFC9B066))),
                                  ),
                                  NavigationRailDestination(
                                    icon: const Icon(Icons.output,
                                        color: Color(0xFFC9B066)),
                                    label: const Text('Send 2',
                                        style: TextStyle(
                                            color: Color(0xFFC9B066))),
                                  ),
                                  NavigationRailDestination(
                                    icon: const Icon(Icons.output,
                                        color: Color(0xFFC9B066)),
                                    label: const Text('Send 3',
                                        style: TextStyle(
                                            color: Color(0xFFC9B066))),
                                  ),
                                  const NavigationRailDestination(
                                    icon: Icon(Icons.tune),
                                    label: Text('Mixer'),
                                  ),
                                  NavigationRailDestination(
                                    icon: const Icon(Icons.input,
                                        color: Color(0xFF83A6C9)),
                                    label: const Text('Return',
                                        style: TextStyle(
                                            color: Color(0xFF83A6C9))),
                                  ),
                                  const NavigationRailDestination(
                                    icon: Icon(Icons.settings),
                                    label: Text('Setup'),
                                  ),
                                  const NavigationRailDestination(
                                    icon: Icon(Icons.folder_open),
                                    label: Text('Files'),
                                  ),
                                  const NavigationRailDestination(
                                    icon: Icon(Icons.view_list),
                                    label: Text('OSC Log'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (discovery.demoMode) const _DemoModeBanner(),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        AnimatedOpacity(
                          opacity: showDisconnectedOverlay ? 0.4 : 1.0,
                          duration: const Duration(milliseconds: 220),
                          child: Container(
                            color: Theme.of(context).colorScheme.surface,
                            child: IndexedStack(
                              index:
                                  selectedIndex.clamp(0, allPages.length - 1),
                              children: allPages,
                            ),
                          ),
                        ),
                        if (showDisconnectedOverlay)
                          const Positioned.fill(child: DisconnectedScrim()),
                      ],
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

/// Full-width amber strip pinned to the bottom of the sidebar while demo mode
/// is on. Tap to exit.
class _DemoModeBanner extends StatelessWidget {
  const _DemoModeBanner();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0B830),
      child: InkWell(
        onTap: () => context.read<ScionDiscovery>().exitDemoMode(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_circle_outline,
                      color: Colors.black, size: 15),
                  SizedBox(width: 6),
                  Text('DEMO MODE',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.5)),
                ],
              ),
              SizedBox(height: 2),
              Text('tap to exit',
                  style: TextStyle(
                      color: Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

class _FadedRailDivider extends StatelessWidget {
  const _FadedRailDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Center(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.34),
                Colors.white.withValues(alpha: 0.34),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.18, 0.82, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
