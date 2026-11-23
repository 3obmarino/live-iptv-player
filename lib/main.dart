import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'ui/common.dart';
import 'ui/live_screen.dart';
import 'ui/menu_screen.dart';
import 'ui/profiles_screen.dart';

const appTitle = 'Live TV Player';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(appTitle);
    await windowManager.setMinimumSize(const Size(960, 600));
  }
  await AppState.I.init();
  runApp(const TvApp());
}

class TvApp extends StatelessWidget {
  const TvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) => MaterialApp(
        title: appTitle,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: AppState.I.themeMode,
        scrollBehavior: const AppScrollBehavior(),
        home: const RootGate(),
      ),
    );
  }
}

/// Shows the profile setup until a profile exists, then the main shell.
class RootGate extends StatelessWidget {
  const RootGate({super.key});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (_, __) =>
          AppState.I.active == null ? const ProfilesScreen() : const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _i,
            onDestinationSelected: (i) => setState(() => _i = i),
            labelType: NavigationRailLabelType.all,
            groupAlignment: 0,
            minWidth: 88,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.live_tv_outlined),
                selectedIcon: Icon(Icons.live_tv),
                label: Text('TV Live'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.menu_rounded),
                label: Text('Menu'),
              ),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _i,
              children: const [LiveScreen(), MenuScreen()],
            ),
          ),
        ],
      ),
    );
  }
}
