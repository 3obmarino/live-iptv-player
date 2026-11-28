import 'dart:io';

import 'package:flutter/material.dart';

import '../backup.dart';
import '../l10n.dart';
import '../updater.dart' show kTvBuild;
import 'common.dart';

/// Settings > Backup and restore.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Backup and restore'))),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        ListTile(
          autofocus: kTvBuild,
          leading: const Icon(Icons.save_alt_rounded),
          title: Text(tr('Make a backup')),
          subtitle: Text(tr('Save or restore profiles, favourites and settings')),
          onTap: () => _export(context),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.settings_backup_restore_rounded),
          title: Text(tr('Restore a backup')),
          subtitle: Text(Platform.isAndroid
              ? tr('Put the backup file in the Download folder, or open it with LiveTV Player from a file manager.')
              : tr('Put the backup file in your Downloads folder.')),
          onTap: () => _restore(context),
        ),
      ]),
    );
  }

  Future<void> _export(BuildContext context) async {
    var logins = true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Make a backup')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: logins,
              onChanged: (v) => set(() => logins = v),
              title: Text(tr('Include usernames and passwords')),
            ),
            const SizedBox(height: 8),
            Text(logins
                ? tr('Keep the file private: it contains your logins.')
                : tr('Without logins you enter them again after restoring.')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
                autofocus: true,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Save'))),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;
    final msg = await Backup.export(logins: logins);
    if (context.mounted) toast(context, msg);
  }

  Future<void> _restore(BuildContext context) async {
    final found = await Backup.find();
    if (!context.mounted) return;
    const pickKey = '\u0000pick';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Choose a backup')),
        children: [
          if (found.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(tr('No backups found')),
            ),
          for (final f in found)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f.$1),
              child: Text(f.$1),
            ),
          if (Platform.isAndroid)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, pickKey),
              child: Text(tr('Choose a file…')),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    String? text;
    if (choice == pickKey) {
      text = await Backup.pick();
      if (text == '') {
        if (context.mounted) {
          toast(context,
              tr('Put the backup file in the Download folder, or open it with LiveTV Player from a file manager.'));
        }
        return;
      }
    } else {
      final f = found.firstWhere((x) => x.$1 == choice);
      text = await f.$2();
    }
    if (text == null || !context.mounted) return;
    await confirmRestore(context, text);
  }
}

/// Asks, then restores. Also used for a backup opened from a file manager.
Future<void> confirmRestore(BuildContext context, String text) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Restore this backup?')),
      content: Text(tr('Profiles and settings from the file replace the ones with the same name here.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
        FilledButton(
            autofocus: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Restore'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final msg = await Backup.restore(text);
  if (context.mounted) toast(context, msg);
}
