import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'ui/common.dart';
import 'ui/live_screen.dart';
import 'ui/profiles_screen.dart';
import 'tv/tv_home.dart';
import 'updater.dart';

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
  Updater.I.start();
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
        themeMode: kTvBuild ? ThemeMode.dark : AppState.I.themeMode,
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
          AppState.I.active == null
              ? const ProfilesScreen()
              : (kTvBuild ? const TvHome() : const HomeShell()),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // We are always on Live TV: no navigation rail/bar. The Menu opens from
  // the icon at the top right of the Live screen.
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          UpdateBar(),
          Expanded(child: LiveScreen()),
        ]),
      ),
    );
  }
}

/// Thin strip at the top of the app when a newer version is released.
class UpdateBar extends StatelessWidget {
  const UpdateBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Updater.I,
      builder: (context, _) {
        final u = Updater.I;
        final info = u.available;
        if (info == null || u.dismissed) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Material(
          color: accentOf(context).withOpacity(0.10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(children: [
              Icon(Icons.system_update_alt_rounded, color: accentOf(context), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  u.installing
                      ? 'Downloading version ${info.version}… ${((u.progress ?? 0) * 100).round()}%'
                      : u.error != null
                          ? 'Update failed: ${u.error}'
                          : 'Version ${info.version} is available (you have $appVersion).',
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
              ),
              if (u.installing)
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(value: u.progress, color: accentOf(context)),
                )
              else ...[
                TextButton(onPressed: u.dismiss, child: const Text('Later')),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: u.install,
                  child: const Text('Install'),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}
