import 'dart:io';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';

import 'app_alert.dart';
import 'disconnected_scrim.dart';
import 'discovery.dart';
import 'network.dart';
import 'network_selection.dart';
import 'setup_page.dart';
import 'system_page.dart';
import 'video_format_selection.dart';
import 'send_page.dart';
import 'mixer_page.dart';
import 'return_page.dart';
import 'signal_colors.dart';
import 'lighting_settings.dart';
import 'global_rect_tracking.dart';
import 'lazy_page_layout.dart';

// A global messenger for surfacing errors unobtrusively during debugging.
final GlobalKey<ScaffoldMessengerState> globalScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Debug/testing toggle: set false to hide disconnected UI scrim + dimming.
const bool kShowDisconnectedOverlay = true;

/// House style for every hover tooltip in the app.
///
/// Set once on [ThemeData] rather than per-call: `Tooltip` is used at ~30 sites
/// (card preset icons, the LUT export/import icons, AppButton's `tooltip` and
/// `blockedReason`, …) and every one of them was rendering Material's default
/// grey slab, which matches nothing else here.
///
/// Follows the app alert (app_alert.dart): the same #2E2F34 face, hairline rim
/// and DINPro text, one step smaller and without the tone accent, since a
/// tooltip explains rather than announces. [waitDuration] keeps it from
/// flashing up on every incidental pass of the pointer.
final TooltipThemeData kScionTooltipTheme = TooltipThemeData(
  waitDuration: const Duration(milliseconds: 450),
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  margin: const EdgeInsets.symmetric(horizontal: 8),
  decoration: BoxDecoration(
    color: const Color(0xFF2E2F34),
    borderRadius: BorderRadius.circular(6),
    border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.28),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  textStyle: const TextStyle(
    fontFamily: 'DINPro',
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.08,
    color: Color(0xFFF1F1F3),
  ),
);

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
    showAppAlertOn(globalScaffoldMessengerKey.currentState,
        'Unhandled error: $msg', tone: AppAlertTone.error);
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
      fontFamily: 'DINPro',
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
      setWindowTitle('SCION Controller');
      // On Windows the initial size and minimum size are set natively in the
      // runner (windows/runner/main.cpp + win32_window.cpp). The window_size
      // plugin applies these logical values as physical pixels, so on displays
      // scaled above 100% the window — and the u-derived type — render too
      // small, and the minimum cannot be held. macOS/Linux size correctly here.
      if (!Platform.isWindows) {
        const Size initialSize = Size(1200, 800);
        setWindowMinSize(initialSize);
        setWindowFrame(const Rect.fromLTWH(0, 0, 1200, 800));
      }
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
          tooltipTheme: kScionTooltipTheme,
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
      // 6 → Setup (also holds Files and the OSC Log)
      SetupPage(isActive: selectedIndex == 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allPages = pages;
    final pageIndex = selectedIndex.clamp(0, allPages.length - 1);
    return LayoutBuilder(builder: (context, constraints) {
      final network = context.watch<Network>();
      final discovery = context.watch<ScionDiscovery>();
      final showDisconnectedOverlay = kShowDisconnectedOverlay &&
          !network.isConnected &&
          !discovery.demoMode;
      // The rail is always shown at full width; there is no collapsed mode.
      const double railWidth = 190;

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
                      width: railWidth,
                      child: Column(
                        children: [
                          Expanded(
                            child: SafeArea(
                              child: Padding(
                                // Extra right inset so the Network Address box
                                // and the row tabs clear the 12px neumorphic
                                // lip on the rail's right edge.
                                padding: const EdgeInsets.fromLTRB(9, 0, 16, 0),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // 16 = the 8 NavigationRail used to put
                                    // above its leading widget, plus 8.
                                    const SizedBox(height: 16),
                                    const NetworkConnectionSection(),
                                    const SizedBox(height: 16),
                                    const _FadedRailDivider(),
                                    const SizedBox(height: 8),
                                    for (int i = 0;
                                        i < _kRailEntries.length;
                                        i++)
                                      _RailItem(
                                        entry: _kRailEntries[i],
                                        selected: i == selectedIndex,
                                        onTap: () =>
                                            setState(() => selectedIndex = i),
                                      ),
                                  ],
                                ),
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
                            // IndexedStack lays out EVERY child and paints one,
                            // so all nine pages used to re-layout on each
                            // resize step. LazyPageLayout freezes the inactive
                            // ones at their last active constraints, which
                            // makes their layout a no-op during a drag while
                            // keeping them mounted (page state is preserved)
                            // and correctly sized.
                            child: IndexedStack(
                              index: pageIndex,
                              children: [
                                for (int i = 0; i < allPages.length; i++)
                                  LazyPageLayout(
                                    active: i == pageIndex,
                                    child: allPages[i],
                                  ),
                              ],
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

/// A nav rail entry.
///
/// Entries with a [solid] colour are always drawn as a solid tab of it: the
/// sends and the return in their signal colours, and the Mixer, which sits
/// between them, in a mid grey. The rest are a faint grey tint until selected.
class _RailEntry {
  final String label;
  final Color? solid;

  const _RailEntry(this.label, [this.solid]);
}

/// The Mixer's solid tab: a mid grey, darker than the light grey of a
/// selected System or Setup tab so the two never look alike.
const Color _kMixerRailColor = Color(0xFF9A9AA0);

/// The nav rail, top to bottom. Must stay in the same order as
/// `_MyHomePageState.pages`: an entry's position is the page it opens.
const List<_RailEntry> _kRailEntries = [
  _RailEntry('System'),
  _RailEntry('Send 1', kSendSignalColor),
  _RailEntry('Send 2', kSendSignalColor),
  _RailEntry('Send 3', kSendSignalColor),
  _RailEntry('Mixer', _kMixerRailColor),
  _RailEntry('Return', kReturnSignalColor),
  _RailEntry('Setup'),
];

/// One full-width row of the nav rail.
///
/// Every row is a slanted tab, like the SEND and RETURN tabs on the device
/// panel, labelled in capitals, and every row's text starts on the same line.
/// As on the panel, the Send tabs round their top-right corner and the Return
/// tab its bottom-left; the other rows round both.
///
/// Solid tabs (Send, Mixer, Return) carry their text in the rail colour, cut
/// out of the tab like the panel lettering, and show selection with a white
/// outline. The other tabs are a faint grey tint with grey text, and fill
/// solid light grey when selected.
class _RailItem extends StatefulWidget {
  final _RailEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _RailItem({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  static const double _rowHeight = 44;
  static const double _tabHeight = 30;

  /// Where every row's text starts: clear of the tab's slanted left end.
  static const double _textInset = _tabHeight * _RailTabPainter.slant + 8;

  /// The rail's own base colour, for text on a solid tab.
  static const Color _cutOutText = Color(0xFF404044);
  static const Color _neutral = Color(0xFFD2D2D4);

  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final label = widget.entry.label;
    final solid = widget.entry.solid;
    final selected = widget.selected;

    final Color fill = solid ??
        (selected ? _neutral : Colors.white.withValues(alpha: 0.10));
    final Color textColor =
        solid != null || selected ? _cutOutText : _neutral;

    final bool isSend = label.startsWith('Send');
    final bool isReturn = label == 'Return';

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: _rowHeight,
            child: Center(
              child: CustomPaint(
                painter: _RailTabPainter(
                  color: fill,
                  roundTopRight: !isReturn,
                  roundBottomLeft: !isSend,
                  outlined: selected && solid != null,
                  hovered: _hovered && !selected,
                ),
                child: SizedBox(
                  height: _tabHeight,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.only(left: _textInset),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label.toUpperCase(),
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'DINPro',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a nav rail tab: a parallelogram whose ends lean like a backslash,
/// matching the slanted section edges on the device panel (about 20° from
/// vertical), with its top-right and/or bottom-left corner rounded.
class _RailTabPainter extends CustomPainter {
  final Color color;
  final bool roundTopRight;
  final bool roundBottomLeft;

  /// Draw a white border just inside the tab's edge (the selected state of a
  /// solid tab).
  final bool outlined;
  final bool hovered;

  const _RailTabPainter({
    required this.color,
    required this.roundTopRight,
    required this.roundBottomLeft,
    required this.outlined,
    required this.hovered,
  });

  static const double slant = 0.36; // tan(20°)
  static const double _radius = 10;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = size.height * slant;
    final corners = [
      const Offset(0, 0),
      Offset(size.width - dx, 0),
      Offset(size.width, size.height),
      Offset(dx, size.height),
    ];
    final radii = [
      0.0,
      roundTopRight ? _radius : 0.0,
      0.0,
      roundBottomLeft ? _radius : 0.0,
    ];

    // Walk the corners; a rounded one is cut back [_radius] along both of its
    // edges and joined with a curve through the corner point.
    final path = Path();
    for (var i = 0; i < corners.length; i++) {
      final p = corners[i];
      final r = radii[i];
      Offset toward(Offset q) => p + (q - p) / (q - p).distance * r;
      final start = r == 0 ? p : toward(corners[(i + 3) % 4]);
      i == 0 ? path.moveTo(start.dx, start.dy) : path.lineTo(start.dx, start.dy);
      if (r != 0) {
        final end = toward(corners[(i + 1) % 4]);
        path.quadraticBezierTo(p.dx, p.dy, end.dx, end.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = color);
    if (hovered) {
      canvas.drawPath(
          path, Paint()..color = Colors.white.withValues(alpha: 0.08));
    }
    if (outlined) {
      // A 4px stroke clipped to the tab leaves 2px inside the edge, so the
      // outline never spills past the tab or shifts its text.
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_RailTabPainter old) =>
      old.color != color ||
      old.roundTopRight != roundTopRight ||
      old.roundBottomLeft != roundBottomLeft ||
      old.outlined != outlined ||
      old.hovered != hovered;
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
