import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';

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
  );
  return base;
}

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
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${two(d.day)}/${two(d.month)}';
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, width: 420));
}

// -------------------------------------------------------------- widgets

class ChannelLogo extends StatelessWidget {
  const ChannelLogo(this.channel, {super.key, this.size = 44});
  final Channel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      child: Text(
        channel.name.isEmpty ? '?' : channel.name.substring(0, 1).toUpperCase(),
        style: TextStyle(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            fontSize: size * 0.38),
      ),
    );
    if (channel.logo.isEmpty) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        channel.logo,
        fit: BoxFit.contain,
        cacheWidth: (size * 2).round(),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => fallback,
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
              Text(p.desc.isEmpty ? 'No description.' : p.desc),
            ],
          ),
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
            label: const Text('Watch channel'),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
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
              ? const Center(child: Text('No TV guide for this channel'))
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
              label: const Text('Watch'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      );
    },
  );
}

/// Phone-sized layout (Pixel 7 portrait is ~412 dp wide).
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 720;
