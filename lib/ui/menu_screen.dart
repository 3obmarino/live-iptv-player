import 'dart:io';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../autostart.dart';
import '../diag.dart';
import '../models.dart';
import 'channel_check_screen.dart';
import 'common.dart';
import 'epg_settings_screen.dart';
import 'player_settings_screen.dart';
import 'profiles_screen.dart';
import '../updater.dart';
import '../l10n.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([AppState.I, Autostart.I]),
      builder: (context, _) {
        final s = AppState.I;
        final p = s.active;
        final cs = Theme.of(context).colorScheme;
        final t = Theme.of(context).textTheme;

        String playlistSub() {
          if (s.loadingChannels) return tr('Updating channel list…');
          final parts = <String>[tr('{n} channels', {'n': s.channels.length})];
          if (p?.channelsUpdated != null) parts.add(tr('updated {t}', {'t': fmtDateTime(p!.channelsUpdated!)}));
          var out = parts.join(' · ');
          if (s.channelsError != null) out += '\n${tr('Last update failed: {e}', {'e': s.channelsError})}';
          return out;
        }

        String epgSub() {
          if (!s.settings.epgEnabled) return tr('Disabled');
          if (s.epgLoading) return tr('Updating TV guide…');
          final last = p?.epgUpdated;
          return '${tr(epgFrequencies[s.settings.epgRefreshHours] ?? '')}'
              '${last == null ? '' : ' · ${tr('last {t}', {'t': fmtDateTime(last)})}'}';
        }

        var firstItem = true;
        Widget item(IconData icon, String title, String? sub, VoidCallback onTap) {
          final auto = kTvBuild && firstItem;
          firstItem = false;
          return Column(
              children: [
                ListTile(
                  // TV: start with focus on the first entry so ▲▼ work at once
                  autofocus: auto,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  leading: Icon(icon),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: sub == null ? null : Text(sub),
                  trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                  onTap: onTap,
                ),
                const Divider(),
              ],
            );
        }

        final compact = isCompact(context);
        final profileInfo = <Widget>[
          CircleAvatar(
            radius: compact ? 28 : 36,
            backgroundColor: accentOf(context),
            child: Text(
              (p?.name.isNotEmpty ?? false) ? p!.name.substring(0, 1).toUpperCase() : '?',
              style: TextStyle(
                  color: onAccentOf(context), fontSize: compact ? 22 : 28, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(height: compact ? 12 : 20),
          Text(p?.name ?? tr('No profile'),
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (p != null)
            Text(p.host, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (p?.expDate != null)
            Text(tr('Expires {d}', {'d': fmtDate(p!.expDate!)}),
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          SizedBox(height: compact ? 12 : 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilesScreen())),
            icon: const Icon(Icons.manage_accounts_outlined, size: 18),
            label: Text(tr('Manage profiles')),
          ),
        ];
        final menuItems = <Widget>[
          item(Icons.playlist_play_rounded, tr('Playlist'), playlistSub(), () async {
            if (p == null) return;
            final err = await s.refreshChannels(p);
            if (context.mounted) toast(context, err ?? tr('Channel list updated'));
          }),
          item(Icons.play_circle_outline_rounded, tr('Video player settings'), null,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const PlayerSettingsScreen()))),
          item(Icons.calendar_view_week_rounded, 'EPG', epgSub(),
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const EpgSettingsScreen()))),
          item(Icons.dark_mode_outlined, tr('Theme'), _themeLabel(s.settings.themeMode),
              () => _pickTheme(context)),
          item(Icons.translate_rounded, tr('Language'), _langLabel(s.settings.language),
              () => _pickLanguage(context)),
          if (Autostart.supported)
            item(
                Icons.power_settings_new_rounded,
                tr('Start on boot'),
                !Autostart.I.enabled
                    ? tr('Off – open LiveTV Player when the device starts')
                    : Autostart.I.permitted
                        ? tr('On')
                        : tr('On – allow "Display over other apps" for LiveTV Player to finish'),
                () async {
              final turnOn = !Autostart.I.enabled;
              final ok = await Autostart.I.setEnabled(turnOn);
              if (!context.mounted) return;
              if (!ok) {
                toast(context,
                    tr('Open Android Settings > Apps > LiveTV Player and allow "Display over other apps"'));
              } else if (!turnOn) {
                toast(context, tr('Start on boot is off'));
              } else if (Autostart.I.permitted) {
                toast(context, tr('LiveTV Player will open when the device starts'));
              }
            }),
          if (!Platform.isAndroid)
            item(Icons.fact_check_outlined, tr('Check channels'),
                tr('Find channels that don\'t work'),
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const ChannelCheckScreen()))),
          if (Diag.enabled)
            item(Icons.receipt_long_outlined, tr('Share player log'),
                Platform.isWindows
                    ? tr('Open the log of what the player does')
                    : kTvBuild
                        ? tr('Save it to the Download folder, to help find playback problems')
                        : tr('Send it to help find playback problems'),
                () async {
              final msg = await Diag.share(tv: kTvBuild);
              if (context.mounted) toast(context, msg);
            }),
          item(Icons.system_update_alt_rounded, tr('Check for updates'), tr('Version {v}', {'v': appVersion}),
              () async {
            if (appBuild == 0) {
              toast(context, tr('This is a local development build'));
              return;
            }
            final u = await Updater.I.check();
            if (!context.mounted) return;
            if (u == null) {
              toast(context, tr('You have the latest version ({v})', {'v': appVersion}));
            } else {
              showUpdateDialog(context);
            }
          }),
        ];

        final about = Padding(
          padding: const EdgeInsets.only(top: 20, left: 8),
          child: Text('LiveTV Player $appVersion · © 2026 $kCompany',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        );

        if (compact) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: profileInfo),
              ),
              const SizedBox(height: 16),
              ...menuItems,
              about,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 320,
              color: cs.surfaceContainerLow,
              padding: const EdgeInsets.fromLTRB(36, 48, 24, 24),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: profileInfo),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(48, 24, 48, 24),
                children: [...menuItems, about],
              ),
            ),
          ],
        );
      },
    );
  }

  static String _themeLabel(String m) =>
      switch (m) { 'light' => tr('Light'), 'dark' => tr('Dark'), _ => tr('Follow system') };

  static String _langLabel(String m) => switch (m) {
        'da' => 'Dansk',
        'en' => 'English',
        _ => tr('Automatic (device language)'),
      };

  Future<void> _pickLanguage(BuildContext context) async {
    final s = AppState.I;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Language')),
        children: [
          for (final m in const ['auto', 'da', 'en'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(children: [
                Icon(s.settings.language == m
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                    color: s.settings.language == m ? accentOf(ctx) : null, size: 20),
                const SizedBox(width: 12),
                Text(_langLabel(m)),
              ]),
            ),
        ],
      ),
    );
    if (v != null) await s.updateSettings((x) => x.language = v);
  }

  Future<void> _pickTheme(BuildContext context) async {
    final s = AppState.I;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Theme')),
        children: [
          for (final m in const ['system', 'light', 'dark'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Row(children: [
                Icon(s.settings.themeMode == m
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                    color: s.settings.themeMode == m ? accentOf(ctx) : null, size: 20),
                const SizedBox(width: 12),
                Text(_themeLabel(m)),
              ]),
            ),
        ],
      ),
    );
    if (v != null) await s.updateSettings((x) => x.themeMode = v);
  }
}


/// "Version X is available" with Install button and download progress.
void showUpdateDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: Updater.I,
      builder: (ctx, _) {
        final u = Updater.I;
        final info = u.available;
        return AlertDialog(
          title: Text(info == null ? tr('Up to date') : tr('Version {v} is available', {'v': info.version})),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('You have {v}.', {'v': appVersion})),
                if (u.installing) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: u.progress),
                  const SizedBox(height: 8),
                  Text(tr('Downloading… {p}%', {'p': ((u.progress ?? 0) * 100).round()})),
                ],
                if (u.error != null) ...[
                  const SizedBox(height: 12),
                  Text(tr('Update failed: {e}', {'e': u.error}),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
                if (Platform.isAndroid && !u.installing) ...[
                  const SizedBox(height: 12),
                  Text(
                      tr('Android may ask you to allow LiveTV Player to install apps the first time.'),
                      style: TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Later'))),
            FilledButton(
              autofocus: true,
              onPressed: info == null || u.installing ? null : u.install,
              child: Text(tr('Install')),
            ),
          ],
        );
      },
    ),
  );
}
