import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'l10n.dart';

/// Backup and restore of profiles, favourites and settings as a small JSON
/// file in the device's Download folder. The file only goes where you put it.
class Backup {
  static const _ch = MethodChannel('livetv/boot');
  static const prefix = 'LiveTV-Player-backup-';

  static String _fileName() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '$prefix${d.year}-${two(d.month)}-${two(d.day)}_${two(d.hour)}${two(d.minute)}.json';
  }

  /// Writes the backup. Returns a message for the user.
  static Future<String> export({required bool logins}) async {
    final text = const JsonEncoder.withIndent('  ')
        .convert(AppState.I.backupJson(logins: logins));
    final name = _fileName();
    if (Platform.isAndroid) {
      try {
        final path = await _ch.invokeMethod<String>('saveToDownloads',
            {'name': name, 'text': text, 'mime': 'application/json'});
        if (path != null) return tr('Backup saved to {p}', {'p': path});
      } catch (_) {}
      return tr('Could not save the backup');
    }
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final f = File('${dir.path}${Platform.pathSeparator}$name');
    await f.writeAsString(text);
    return tr('Backup saved to {p}', {'p': f.path});
  }

  /// Backups the app can find by itself, newest first: name -> reader.
  static Future<List<(String, Future<String?> Function())>> find() async {
    final out = <(String, Future<String?> Function())>[];
    if (Platform.isAndroid) {
      try {
        final list = await _ch.invokeListMethod<Map>('listBackups', {'prefix': prefix}) ?? [];
        for (final m in list) {
          final uri = '${m['uri']}';
          out.add(('${m['name']}', () => _ch.invokeMethod<String>('readUri', {'uri': uri})));
        }
      } catch (_) {}
    } else {
      final dir = await getDownloadsDirectory();
      if (dir != null && await dir.exists()) {
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.uri.pathSegments.last.startsWith(prefix) && f.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
        for (final f in files) {
          out.add((f.uri.pathSegments.last, () => f.readAsString()));
        }
      }
    }
    out.sort((a, b) => b.$1.compareTo(a.$1)); // names carry date and time
    return out;
  }

  /// Android: the system's file picker (phones; many TVs have none).
  /// Returns the file's text, '' if no picker exists, or null if cancelled.
  static Future<String?> pick() async {
    if (!Platform.isAndroid) return '';
    try {
      return await _ch.invokeMethod<String>('pickFile');
    } catch (_) {
      return '';
    }
  }

  /// A backup opened with "Open with LiveTV Player" in a file manager.
  static Future<String?> takeOpenedFile() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _ch.invokeMethod<String>('takeOpenedFile');
    } catch (_) {
      return null;
    }
  }

  /// Restores from the file's text. Returns a message for the user.
  static Future<String> restore(String text) async {
    try {
      final j = jsonDecode(text);
      if (j is! Map) throw const FormatException();
      final n = await AppState.I.restoreBackup(j.cast<String, dynamic>());
      return tr('Restored {n} profiles', {'n': n});
    } catch (_) {
      return tr('This file is not a LiveTV Player backup');
    }
  }
}
