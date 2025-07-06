import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_size/window_size.dart';

import 'network.dart';
import 'network_selection.dart';
import 'file_selection.dart';
import 'status_bar.dart';
import 'setup_page.dart';
import 'send_page.dart';
import 'osc_log.dart';
import 'osc_registry_viewer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    const Size initialSize = Size(1200, 800);
    setWindowMinSize(initialSize);
    setWindowFrame(const Rect.fromLTWH(0, 0, 1200, 800));
  }

  runApp(
    ChangeNotifierProvider<Network>.value(
      value: Network(),
      child: const MyApp(),
    ),
  );
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

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;

  List<Widget> get pages {
    return [
      // 0 → Setup
      const SetupPage(),
      // 1–3 → Send 1–3
      for (var i = 1; i <= 3; i++) SendPage(key: ValueKey(i), pageNumber: i),
      // 4 → Return
      const ReturnPage(),
      // 5 → OSC Log
      OscLogTable(
        key: oscLogKey,
        onDownload: (bytes) {/* … */},
        isActive: selectedIndex == 5,
      ),
      // 6 → Registry Viewer
      const OscRegistryViewer(),
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

      return Scaffold(
        body: Column(
          children: [
            Expanded(
              child: Row(
                children: [
                  SafeArea(
                    child: NavigationRail(
                      backgroundColor: const Color.fromARGB(255, 88, 88, 92),
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
                          icon: Icon(Icons.settings),
                          label: Text('Setup'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.output),
                          label: Text('Send 1'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.output),
                          label: Text('Send 2'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.output),
                          label: Text('Send 3'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.output),
                          label: Text('Send 4'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.input),
                          label: Text('Return'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.view_list),
                          label: Text('OSC Log'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.storage),
                          label: Text('Registry'),
                        ),
                      ],
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
            Container(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
              child: const StatusBarRow(
                rightText: "Status Right",
              ),
            ),
          ],
        ),
      );
    });
  }
}

class ReturnPage extends StatelessWidget {
  const ReturnPage({super.key});
  @override
  Widget build(BuildContext context) => const Placeholder();
}
