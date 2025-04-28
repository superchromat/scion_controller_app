import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'LUTEditor.dart';

void main() {
  runApp(const MyApp());
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
          scaffoldBackgroundColor: const Color(0xFF1C1C1E), // dark grey
          useMaterial3: true,
          colorScheme: ColorScheme.dark(
            primary: const Color(0xFFFFF176), // pastel yellow highlight
            secondary: Colors.grey[400]!,
            surface: const Color(0xFF2C2C2E), // lighter grey surfaces
            onTertiaryContainer: Color(0xFF1A1A1A),
            background: const Color(0xFF1C1C1E),
            onPrimary: Colors.black, // icons on yellow
            onSurface: Colors.white, // default text on grey
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.grey[400]!),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(6), // less pill, more rectangle
              ),
              foregroundColor: Colors.grey[300],
              textStyle: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        home: MyHomePage(),
      ),
    );
  }
}

class MyAppState extends ChangeNotifier {
  notifyListeners();
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class StatusBarRow extends StatelessWidget {
  final String leftText;
  final String rightText;

  const StatusBarRow({
    super.key,
    required this.leftText,
    required this.rightText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: DefaultTextStyle(
        style: const TextStyle(
          fontFamily: 'courier',
          fontSize: 12,
          letterSpacing: 1.0,
          color: Colors.white, 
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(leftText),
            Text(rightText),
          ],
        ),
      ),
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  var selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    Widget page;
    switch (selectedIndex) {
      case 0:
        page = const DemoPage();
      default:
        page = const DemoPage();
    }

    return LayoutBuilder(builder: (context, constraints) {
      return Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              fit: FlexFit.loose,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SafeArea(
                    child: NavigationRail(
                      backgroundColor: const Color.fromARGB(255, 88, 88, 92),
                      extended: constraints.maxWidth >= 100,
                      destinations: [
                        const NavigationRailDestination(
                          icon: Icon(Icons.settings),
                          label: Text('Setup'),
                        ),
                        for (var i = 1; i < 5; i++)
                          NavigationRailDestination(
                            icon: const Icon(Icons.launch),
                            label: Text('Send $i'),
                          ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.exit_to_app),
                          label: Text('Return'),
                        ),
                      ],
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (value) {
                        setState(() {
                          selectedIndex = value;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Theme.of(context).colorScheme.surface,
                      child: page,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: Theme.of(context).colorScheme.onTertiaryContainer,
              padding: const EdgeInsets.all(8),
              child: const StatusBarRow(
                leftText: "Status Left",
                rightText: "Status Right",
              ),
            ),
          ],
        ),
      );
    });
  }
}

class DemoPage extends StatelessWidget {
  const DemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return const LUTEditor();
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
