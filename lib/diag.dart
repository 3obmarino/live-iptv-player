import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_state.dart';
import 'storage.dart';
import 'l10n.dart';

/// Small local log of what the player does, to find playback problems
/// (Windows, phone and TV): player-log.txt in the app's data folder, at
/// most ~300 KB (it starts over when full). It never leaves the device by
/// itself; Settings > Share player log hands it over on request.
/// Web addresses, Xtream paths and the profile's username/password are
/// removed before anything is written.
class Diag {
  static final _t0 = DateTime.now();
  static bool get enabled => Platform.isWindows || Platform.isAndroid;
  static const fileName = 'player-log.txt';
  static File get file => Store.file(fileName);

  static final _url = RegExp(r'[a-z]+://\S+', caseSensitive: false);
  static final _xtream =
      RegExp(r'/(live|movie|series|timeshift)/[^/\s]+/[^/\s]+/', caseSensitive: false);

  static String redact(String s) {
    var out = s.replaceAll(_url, '<url>').replaceAllMapped(_xtream, (m) => '/${m[1]}/<user>/<pass>/');
    final p = AppState.I.active;
    if (p != null) {
      for (final secret in [p.password, p.username]) {
        if (secret.length >= 3) out = out.replaceAll(secret, '<hidden>');
      }
    }
    return out;
  }

  static void log(String msg) {
    if (!enabled) return;
    try {
      final f = file;
      if (f.existsSync() && f.lengthSync() > 300 * 1024) {
        f.writeAsStringSync('--- log restarted ---\n');
      }
      final ms = DateTime.now().difference(_t0).inMilliseconds;
      f.writeAsStringSync(
          '${DateTime.now().toIso8601String().substring(0, 23)} '
          '+${(ms / 1000).toStringAsFixed(2)}s  ${redact(msg)}\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  static const _ch = MethodChannel('livetv/boot');

  /// Settings > Share player log. Windows: opens the file. Phone: Android's
  /// share menu. TV / no share menu: a copy in the Download folder.
  /// Returns a short message for the user.
  static Future<String> share({required bool tv}) async {
    final f = file;
    if (!f.existsSync() || f.lengthSync() == 0) {
      return tr('The log is empty – play a channel first');
    }
    if (Platform.isWindows) {
      await launchUrl(Uri.file(f.path));
      return tr('Opened {p}', {'p': f.path});
    }
    var text = await f.readAsString();
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
    if (!tv) {
      // Share menus choke on very large texts: send the newest 150 KB.
      final share = text.length > 150000 ? text.substring(text.length - 150000) : text;
      try {
        final ok = await _ch.invokeMethod<bool>(
            'shareText', {'text': share, 'subject': 'LiveTV Player log $stamp'});
        if (ok == true) return 'Choose where to send the log';
      } catch (_) {}
    }
    try {
      final path = await _ch.invokeMethod<String>(
          'saveToDownloads', {'name': 'LiveTV-Player-log-$stamp.txt', 'text': text});
      if (path != null) return tr('Saved to {p}', {'p': path});
    } catch (_) {}
    return tr('Could not share or save the log');
  }
}
