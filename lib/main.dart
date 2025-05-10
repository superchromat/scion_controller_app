import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'network.dart';
import 'status_bar.dart';
import 'SetupPage.dart';
import 'send_page.dart';
import 'osc_log.dart'; 
import 'file_selection.dart';

void main() {
  runApp(
    ChangeNotifierProvider<Network>.value(
      value: network,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => MyAppState(),
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
            background: const Color(0xFF1C1C1E),
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
  void notifyListeners() {}
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int selectedIndex = 0;

  List<Widget> get pages {
    final list = <Widget>[];

    list.add(const SetupPage());
    for (var i = 1; i < 5; i++) {
      list.add(SendPage(key: ValueKey(i), pageNumber: i));
    }
    list.add(const ReturnPage());

    list.add(
      OscLogTable(
        key: oscLogKey,     
        onDownload: (bytes) {
          // TODO: desktop file-save dialog here
        },
        isActive: selectedIndex == list.length,
      ),
    );

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final allPages = pages;
    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: Column(
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Row(
                children: [
                  SafeArea(
                    child: NavigationRail(
                      backgroundColor: const Color.fromARGB(255, 88, 88, 92),
                      minWidth: 72,
                      minExtendedWidth: 180,
                      extended: constraints.maxWidth >= 100,
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (value) {
                        setState(() => selectedIndex = value);
                      },
                      destinations: const [
                        NavigationRailDestination(
                            icon: Icon(Icons.settings), label: Text('Setup')),
                        NavigationRailDestination(
                            icon: Icon(Icons.output), label: Text('Send 1')),
                        NavigationRailDestination(
                            icon: Icon(Icons.output), label: Text('Send 2')),
                        NavigationRailDestination(
                            icon: Icon(Icons.output), label: Text('Send 3')),
                        NavigationRailDestination(
                            icon: Icon(Icons.output), label: Text('Send 4')),
                        NavigationRailDestination(
                            icon: Icon(Icons.input), label: Text('Return')),
                        NavigationRailDestination(
                            icon: Icon(Icons.view_list),
                            label: Text('OSC Log')),
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
