import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'diag.dart';
import 'ui/common.dart';
import 'ui/live_screen.dart';
import 'ui/profiles_screen.dart';
import 'tv/tv_home.dart';
import 'updater.dart';

const appTitle = 'LiveTV Player';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle(appTitle);
    await windowManager.setMinimumSize(const Size(960, 600));
  }
  if (kTvBuild) {
    // Remote control = always draw focus highlights (Flutter otherwise
    // waits until it has decided the device is keyboard-driven).
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
    // Full screen: hides the status and navigation bars that Android TV
    // boxes and signage screens sometimes show over the picture.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
        // Remote control and text fields, see TvKeys.
        builder: kTvBuild
            ? (context, child) => TvKeys(child: child ?? const SizedBox.shrink())
            : null,
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
          AppState.I.active != null
              ? (kTvBuild ? const TvHome() : const HomeShell())
              // No profiles yet: go straight to the form, no empty page first.
              : AppState.I.profiles.isEmpty
                  ? const EditProfileScreen()
                  : const ProfilesScreen(),
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

/// Remote control keys around text fields (TV build).
/// - On-screen keyboard closed: ▲/▼ move between fields (a text field would
///   otherwise keep those keys). Typing happens in AppTextField's editor.
/// - On-screen keyboard open: the arrow keys and OK are left to the keyboard,
///   so you can move around in it. (Flutter sees keys before the keyboard
///   does; keys it doesn't handle go on to the keyboard.)
class TvKeys extends StatefulWidget {
  const TvKeys({super.key, required this.child});
  final Widget child;
  @override
  State<TvKeys> createState() => _TvKeysState();
}

class _TvKeysState extends State<TvKeys> {
  bool _kbOpen = false;

  static bool _inTextField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static final _navKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_inTextField() || !_navKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (_kbOpen) {
      // Not ours: let the on-screen keyboard have it.
      return KeyEventResult.skipRemainingHandlers;
    }
    return KeyEventResult.ignored; // ▲/▼ go to the Shortcuts below
  }

  @override
  Widget build(BuildContext context) {
    final open = MediaQuery.viewInsetsOf(context).bottom > 0;
    if (open != _kbOpen) Diag.log('[tv] on-screen keyboard ${open ? 'open' : 'closed'}');
    _kbOpen = open;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Shortcuts(
        shortcuts: open
            ? const <ShortcutActivator, Intent>{}
            : const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.arrowUp):
                    DirectionalFocusIntent(TraversalDirection.up, ignoreTextFields: false),
                SingleActivator(LogicalKeyboardKey.arrowDown):
                    DirectionalFocusIntent(TraversalDirection.down, ignoreTextFields: false),
              },
        child: widget.child,
      ),
    );
  }
}
