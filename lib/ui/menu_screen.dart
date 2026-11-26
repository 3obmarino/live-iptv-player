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
          if (s.loadingChannels) return 'Updating channel list…';
          final parts = <String>['${s.channels.length} channels'];
          if (p?.channelsUpdated != null) parts.add('updated ${fmtDateTime(p!.channelsUpdated!)}');
          var out = parts.join(' · ');
          if (s.channelsError != null) out += '\nLast update failed: ${s.channelsError}';
          return out;
        }

        String epgSub() {
          if (!s.settings.epgEnabled) return 'Disabled';
          if (s.epgLoading) return 'Updating TV guide…';
          final last = p?.epgUpdated;
          return '${epgFrequencies[s.settings.epgRefreshHours] ?? ''}'
              '${last == null ? '' : ' · last ${fmtDateTime(last)}'}';
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
          Text(p?.name ?? 'No profile',
              style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (p != null)
            Text(p.host, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          if (p?.expDate != null)
            Text('Expires ${fmtDate(p!.expDate!)}',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          SizedBox(height: compact ? 12 : 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ProfilesScreen())),
            icon: const Icon(Icons.manage_accounts_outlined, size: 18),
            label: const Text('Manage profiles'),
          ),
        ];
        final menuItems = <Widget>[
          item(Icons.playlist_play_rounded, 'Playlist', playlistSub(), () async {
            if (p == null) return;
            final err = await s.refreshChannels(p);
            if (context.mounted) toast(context, err ?? 'Channel list updated');
          }),
          item(Icons.play_circle_outline_rounded, 'Video player settings', null,
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const PlayerSettingsScreen()))),
          item(Icons.calendar_view_week_rounded, 'EPG', epgSub(),
              () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const EpgSettingsScreen()))),
          item(Icons.dark_mode_outlined, 'Theme', _themeLabel(s.settings.themeMode),
              () => _pickTheme(context)),
          if (Autostart.supported)
            item(
                Icons.power_settings_new_rounded,
                'Start on boot',
                !Autostart.I.enabled
                    ? 'Off – open LiveTV Player when the device starts'
                    : Autostart.I.permitted
                        ? 'On'
                        : 'On – allow "Display over other apps" for LiveTV Player to finish',
                () async {
              final turnOn = !Autostart.I.enabled;
              final ok = await Autostart.I.setEnabled(turnOn);
              if (!context.mounted) return;
              if (!ok) {
                toast(context,
                    'Open Android Settings > Apps > LiveTV Player and allow "Display over other apps"');
              } else if (!turnOn) {
                toast(context, 'Start on boot is off');
              } else if (Autostart.I.permitted) {
                toast(context, 'LiveTV Player will open when the device starts');
              }
            }),
          if (!Platform.isAndroid)
            item(Icons.fact_check_outlined, 'Check channels',
                'Find channels that don\'t work',
                () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => const ChannelCheckScreen()))),
          if (Diag.enabled)
            item(Icons.receipt_long_outlined, 'Share player log',
                Platform.isWindows
                    ? 'Open the log of what the player does'
                    : kTvBuild
                        ? 'Save it to the Download folder, to help find playback problems'
                        : 'Send it to help find playback problems',
                () async {
              final msg = await Diag.share(tv: kTvBuild);
              if (context.mounted) toast(context, msg);
            }),
          item(Icons.system_update_alt_rounded, 'Check for updates', 'Version $appVersion',
              () async {
            if (appBuild == 0) {
              toast(context, 'This is a local development build');
              return;
            }
            final u = await Updater.I.check();
            if (!context.mounted) return;
            if (u == null) {
              toast(context, 'You have the latest version ($appVersion)');
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
      switch (m) { 'light' => 'Light', 'dark' => 'Dark', _ => 'Follow system' };

  Future<void> _pickTheme(BuildContext context) async {
    final s = AppState.I;
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Theme'),
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
          title: Text(info == null ? 'Up to date' : 'Version ${info.version} is available'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You have $appVersion.'),
                if (u.installing) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: u.progress),
                  const SizedBox(height: 8),
                  Text('Downloading… ${((u.progress ?? 0) * 100).round()}%'),
                ],
                if (u.error != null) ...[
                  const SizedBox(height: 12),
                  Text('Update failed: ${u.error}',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
                if (Platform.isAndroid && !u.installing) ...[
                  const SizedBox(height: 12),
                  const Text(
                      'Android may ask you to allow LiveTV Player to install apps the first time.',
                      style: TextStyle(fontSize: 13)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
            FilledButton(
              autofocus: true,
              onPressed: info == null || u.installing ? null : u.install,
              child: const Text('Install'),
            ),
          ],
        );
      },
    ),
  );
}
