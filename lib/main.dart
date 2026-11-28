import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app_state.dart';
import 'backup.dart';
import 'ui/backup_screen.dart';
import 'diag.dart';
import 'ui/common.dart';
import 'ui/live_screen.dart';
import 'ui/profiles_screen.dart';
import 'tv/tv_home.dart';
import 'updater.dart';
import 'l10n.dart';
import 'reminders.dart';

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
  await Reminders.I.init();
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
        navigatorKey: appNavigatorKey,
        home: const RootGate(),
      ),
    );
  }
}

final appNavigatorKey = GlobalKey<NavigatorState>();

/// Shows the profile setup until a profile exists, then the main shell.
/// Also picks up a backup file opened with "Open with LiveTV Player".
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOpenedBackup());
    Reminders.I.due.addListener(_onReminder);
  }

  /// A reminded programme starts: pop-up with "Watch now".
  Future<void> _onReminder() async {
    final r = Reminders.I.due.value;
    final ctx = appNavigatorKey.currentState?.overlay?.context;
    if (r == null || ctx == null || !ctx.mounted) return;
    Reminders.I.due.value = null;
    final c = Reminders.I.channelFor(r);
    final watch = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        icon: const Icon(Icons.notifications_active_rounded, size: 36),
        title: Text(r.title.isEmpty ? r.channelName : r.title),
        content: Text(tr('Starts now on {c}', {'c': r.channelName})),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(tr('Close'))),
          if (c != null)
            FilledButton.icon(
              autofocus: true,
              onPressed: () => Navigator.pop(dctx, true),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(tr('Watch now')),
            ),
        ],
      ),
    );
    if (watch == true && c != null) AppState.I.playRequest.value = c;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Reminders.I.due.removeListener(_onReminder);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkOpenedBackup();
  }

  Future<void> _checkOpenedBackup() async {
    final text = await Backup.takeOpenedFile();
    final ctx = appNavigatorKey.currentState?.overlay?.context;
    if (text == null || ctx == null || !ctx.mounted) return;
    await confirmRestore(ctx, text);
  }

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
                      ? tr('Downloading version {v}… {p}%', {'v': info.version, 'p': ((u.progress ?? 0) * 100).round()})
                      : u.error != null
                          ? tr('Update failed: {e}', {'e': u.error})
                          : tr('Version {v} is available (you have {c}).', {'v': info.version, 'c': appVersion}),
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w500),
                ),
              ),
              if (u.installing)
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(value: u.progress, color: accentOf(context)),
                )
              else ...[
                TextButton(onPressed: u.dismiss, child: Text(tr('Later'))),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: u.install,
                  child: Text(tr('Install')),
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

/// Android background refresh: started headless by the native job service
/// (RefreshJob) about every hour while the app is closed.
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('livetv/background');
  try {
    await AppState.I.backgroundRefresh().timeout(const Duration(minutes: 8));
  } catch (_) {}
  try {
    await ch.invokeMethod<void>('done');
  } catch (_) {}
}
