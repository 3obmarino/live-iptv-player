import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../logo_cache.dart';
import '../models.dart';
import '../updater.dart' show kTvBuild;
import '../l10n.dart';
import '../reminders.dart';

/// "Matrix" green. Bright on dark surfaces; a deeper green on light ones
/// so text and icons stay readable. Text on top of kAccent uses kOnAccent.
const kAccent = Color(0xFF00FF41);
const kAccentDeep = Color(0xFF00802B);
const kOnAccent = Color(0xFF00170A);

Color accentOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? kAccent : kAccentDeep;
Color onAccentOf(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? kOnAccent : Colors.white;

// ------------------------------------------------------------------ theme

/// Windows' own UI font: crisp at small sizes, no bundling needed.
const _font = 'Segoe UI Variable Text';
const _fontFallback = ['Segoe UI', 'Inter', 'Roboto', 'Arial'];

ThemeData buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final bg = dark ? const Color(0xFF121214) : const Color(0xFFF7F7F8);
  final surface = dark ? const Color(0xFF1B1B1F) : Colors.white;
  final surfaceLow = dark ? const Color(0xFF17171A) : const Color(0xFFF0F0F2);
  final line = dark ? const Color(0xFF2A2A30) : const Color(0xFFE4E4E8);
  final text = dark ? const Color(0xFFF2F2F4) : const Color(0xFF16161A);
  final muted = dark ? const Color(0xFF9A9AA3) : const Color(0xFF6B6B75);
  final accent = dark ? kAccent : kAccentDeep;

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: b,
    primary: accent,
    onPrimary: dark ? kOnAccent : Colors.white,
    surface: surface,
    onSurface: text,
    onSurfaceVariant: muted,
    outlineVariant: line,
    surfaceContainerLow: surfaceLow,
    surfaceContainerHighest: dark ? const Color(0xFF26262C) : const Color(0xFFE9E9EC),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: _font,
    fontFamilyFallback: _fontFallback,
    scaffoldBackgroundColor: bg,
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
          fontFamily: _font,
          fontFamilyFallback: _fontFallback,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: line)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: bg,
      indicatorColor: accent.withOpacity(0.14),
      selectedIconTheme: IconThemeData(color: accent),
      unselectedIconTheme: IconThemeData(color: muted),
      selectedLabelTextStyle: TextStyle(
          color: accent, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: muted, fontSize: 12),
    ),
    tooltipTheme: const TooltipThemeData(waitDuration: Duration(milliseconds: 500)),
    // Clear focus for remotes and keyboards: a thick ring on the focused
    // button, and a stronger highlight on focused list rows.
    focusColor: kTvBuild ? accent.withOpacity(0.30) : null,
    filledButtonTheme: FilledButtonThemeData(style: _focusRing(text)),
    outlinedButtonTheme: OutlinedButtonThemeData(style: _focusRing(text)),
    textButtonTheme: TextButtonThemeData(style: _focusRing(text)),
    iconButtonTheme: IconButtonThemeData(style: _focusRing(text)),
  );
  return base;
}

ButtonStyle _focusRing(Color ring) => ButtonStyle(
      side: WidgetStateProperty.resolveWith((states) => states.contains(WidgetState.focused)
          ? BorderSide(color: ring, width: kTvBuild ? 4 : 2)
          : null),
    );

class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

// ------------------------------------------------------------- formatting

String two(int n) => n.toString().padLeft(2, '0');
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';
String fmtDateTime(DateTime d) => '${fmtDate(d)} – ${fmtTime(d)}';
String fmtMs(int ms) => fmtTime(DateTime.fromMillisecondsSinceEpoch(ms));

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return tr('Today');
  if (diff == 1) return tr('Tomorrow');
  if (diff == -1) return tr('Yesterday');
  return '${two(d.day)}/${two(d.month)}';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, width: 420));
}

// -------------------------------------------------------------- widgets

class ChannelLogo extends StatefulWidget {
  const ChannelLogo(this.channel, {super.key, this.size = 44});
  final Channel channel;
  final double size;

  @override
  State<ChannelLogo> createState() => _ChannelLogoState();
}

class _ChannelLogoState extends State<ChannelLogo> {
  ImageProvider? _image;
  bool _failed = false;
  bool _fade = false; // only fade logos that arrived from the network

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ChannelLogo old) {
    super.didUpdateWidget(old);
    if (old.channel.logo != widget.channel.logo) _resolve();
  }

  void _resolve() {
    final url = widget.channel.logo;
    _failed = false;
    _fade = false;
    _image = url.isEmpty ? null : LogoCache.cached(url);
    if (url.isEmpty || _image != null) return;
    if (LogoCache.failed(url)) {
      _failed = true;
      return;
    }
    LogoCache.fetch(url).then((f) {
      if (!mounted || widget.channel.logo != url) return;
      setState(() {
        if (f == null) {
          _failed = true;
        } else {
          _image = LogoCache.provider(f);
          _fade = true;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final cs = Theme.of(context).colorScheme;
    final c = widget.channel;
    Widget fallback() => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8)),
          child: Text(
            c.name.isEmpty ? '?' : c.name.substring(0, 1).toUpperCase(),
            style: TextStyle(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontSize: size * 0.38),
          ),
        );
    if (c.logo.isEmpty || _failed) return fallback();
    final img = _image;
    return SizedBox(
      width: size,
      height: size,
      child: img == null
          ? null // still downloading: keep the space empty, no letter flash
          : Image(
              image: img,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => fallback(),
              frameBuilder: (_, child, frame, sync) {
                if (sync || !_fade) return child;
                return AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: child,
                );
              },
            ),
    );
  }
}

/// Current programme (or null) for a channel at [now].
Programme? currentProgramme(Channel c, int now) {
  for (final p in AppState.I.epg.forChannel(c)) {
    if (p.isLiveAt(now)) return p;
    if (p.start > now) break;
  }
  return null;
}

void showProgrammeDetails(BuildContext context, Channel c, Programme p,
    {VoidCallback? onWatch}) {
  final d = DateTime.fromMillisecondsSinceEpoch(p.start);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(p.title.isEmpty ? c.name : p.title),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${c.name}  ·  ${dayLabel(d)}  ${fmtMs(p.start)}–${fmtMs(p.stop)}',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Text(p.desc.isEmpty ? tr('No description.') : p.desc),
            ],
          ),
        ),
      ),
      actions: [
        if (p.start > DateTime.now().millisecondsSinceEpoch)
          ListenableBuilder(
            listenable: Reminders.I,
            builder: (_, __) {
              final on = Reminders.I.has(c, p);
              return TextButton.icon(
                onPressed: () async {
                  final added = await Reminders.I.toggle(c, p);
                  if (ctx.mounted) {
                    toast(ctx, added
                        ? tr('Reminder set: {t} at {h}', {'t': p.title, 'h': fmtMs(p.start)})
                        : tr('Reminder removed'));
                  }
                },
                icon: Icon(on ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
                label: Text(on ? tr('Cancel reminder') : tr('Remind me')),
              );
            },
          ),
        if (onWatch != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onWatch();
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(tr('Watch channel')),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
      ],
    ),
  );
}

void showChannelGuide(BuildContext context, Channel c, {VoidCallback? onWatch}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final progs =
      AppState.I.epg.forChannel(c).where((p) => p.stop > now).toList();
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Row(children: [
          ChannelLogo(c, size: 32),
          const SizedBox(width: 12),
          Expanded(child: Text(c.name)),
        ]),
        content: SizedBox(
          width: 560,
          height: 520,
          child: progs.isEmpty
              ? Center(child: Text(tr('No TV guide for this channel')))
              : ListView.separated(
                  itemCount: progs.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, i) {
                    final p = progs[i];
                    final live = p.isLiveAt(now);
                    final d = DateTime.fromMillisecondsSinceEpoch(p.start);
                    return ListTile(
                      dense: true,
                      leading: SizedBox(
                        width: 84,
                        child: Text('${dayLabel(d)}\n${fmtMs(p.start)}–${fmtMs(p.stop)}',
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                      title: Text(p.title,
                          style: TextStyle(
                              fontWeight: live ? FontWeight.w700 : FontWeight.w500,
                              color: live ? accentOf(ctx) : null)),
                      subtitle: p.desc.isEmpty
                          ? null
                          : Text(p.desc, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => showProgrammeDetails(ctx, c, p),
                    );
                  },
                ),
        ),
        actions: [
          if (onWatch != null)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                onWatch();
              },
              icon: const Icon(Icons.play_arrow),
              label: Text(tr('Watch')),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close'))),
        ],
      );
    },
  );
}

/// Phone-sized layout (Pixel 7 portrait is ~412 dp wide).
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 720;

/// A text field that works with a TV remote.
///
/// On a phone or PC it is a normal TextField. On TV the field itself only
/// shows the value: ▲/▼ move past it and OK opens a small editor with the
/// on-screen keyboard. Inside the editor every remote key goes to the
/// keyboard (the app no longer takes ▲/▼ to jump to the next field), the
/// keyboard's →| / Done key saves, and Back saves and closes.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
  });
  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!kTvBuild) {
      return TextField(
        controller: controller,
        decoration: decoration,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        autofocus: autofocus,
        enabled: enabled,
      );
    }
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, e) {
        final ok = e.logicalKey == LogicalKeyboardKey.select ||
            e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter;
        if (!ok) return KeyEventResult.ignored;
        if (e is KeyUpEvent && enabled) _edit(context);
        return KeyEventResult.handled;
      },
      child: TextField(
        controller: controller,
        decoration: decoration,
        obscureText: obscureText,
        readOnly: true, // no keyboard just because the field got focus
        showCursor: false,
        enableInteractiveSelection: false,
        autofocus: autofocus,
        enabled: enabled,
        onTap: () => _edit(context),
      ),
    );
  }

  static const _native = MethodChannel('livetv/boot');

  Future<void> _edit(BuildContext context) async {
    // Android's own input dialog: the TV keyboard and remote work there like
    // in other TV apps. The Flutter editor below is only a fallback.
    String? value;
    var nativeOk = false;
    try {
      value = await _native.invokeMethod<String>('editText', {
        'label': decoration.labelText ?? decoration.hintText ?? '',
        'text': controller.text,
        'kind': obscureText
            ? 'password'
            : keyboardType == TextInputType.url
                ? 'url'
                : 'text',
      });
      nativeOk = true;
    } catch (_) {}
    if (!nativeOk && context.mounted) {
      value = await showDialog<String>(
      context: context,
      builder: (_) => _TvEditDialog(
        label: decoration.labelText ?? decoration.hintText ?? '',
        hint: decoration.hintText,
        initial: controller.text,
        keyboardType: keyboardType,
        obscureText: obscureText,
      ),
    );
    }
    if (value == null || !context.mounted) return;
    if (value != controller.text) {
      controller.text = value;
      onChanged?.call(value);
    }
    if (textInputAction == TextInputAction.next) {
      FocusScope.of(context).nextFocus();
    } else if (textInputAction == TextInputAction.done || textInputAction == TextInputAction.go) {
      onSubmitted?.call(value);
    }
  }
}

class _TvEditDialog extends StatefulWidget {
  const _TvEditDialog(
      {required this.label,
      required this.initial,
      this.hint,
      this.keyboardType,
      this.obscureText = false});
  final String label;
  final String? hint;
  final String initial;
  final TextInputType? keyboardType;
  final bool obscureText;
  @override
  State<_TvEditDialog> createState() => _TvEditDialogState();
}

class _TvEditDialogState extends State<_TvEditDialog> {
  late final _ctl = TextEditingController(text: widget.initial);
  late bool _hide = widget.obscureText;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static final _keyboardKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
  };

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // Back (after the keyboard is closed) keeps what was typed.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_ctl.text);
      },
      child: Dialog(
        alignment: Alignment.topCenter,
        insetPadding: const EdgeInsets.fromLTRB(80, 48, 80, 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Focus(
              skipTraversal: true,
              canRequestFocus: false,
              // Every remote key goes on to the on-screen keyboard. OK also
              // reopens the keyboard if it was closed with Back.
              onKeyEvent: (node, e) {
                if (!_keyboardKeys.contains(e.logicalKey)) return KeyEventResult.ignored;
                final ok = e.logicalKey == LogicalKeyboardKey.select ||
                    e.logicalKey == LogicalKeyboardKey.enter ||
                    e.logicalKey == LogicalKeyboardKey.numpadEnter;
                if (ok && e is KeyDownEvent) {
                  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
                }
                return KeyEventResult.skipRemainingHandlers;
              },
              child: TextField(
                controller: _ctl,
                autofocus: true,
                obscureText: _hide,
                keyboardType: widget.keyboardType,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 22),
                decoration: InputDecoration(hintText: widget.hint),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('Press →| on the keyboard when done. Back also saves.'),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
