import 'dart:io';

import 'storage.dart';

/// Small local log of what the player does (Windows), to find playback
/// problems: %APPDATA%\Ukendt Software\LiveTV Player\player-log.txt.
/// Stays on this PC. Web addresses are removed, so no stream URL or login
/// ever ends up in it.
class Diag {
  static final _t0 = DateTime.now();
  static bool get enabled => Platform.isWindows;
  static final _url = RegExp(r'[a-z]+://\S+', caseSensitive: false);

  static void log(String msg) {
    if (!enabled) return;
    try {
      final f = Store.file('player-log.txt');
      if (f.existsSync() && f.lengthSync() > 300 * 1024) {
        f.writeAsStringSync('--- log restarted ---\n');
      }
      final ms = DateTime.now().difference(_t0).inMilliseconds;
      final line = msg.replaceAll(_url, '<url>');
      f.writeAsStringSync('${DateTime.now().toIso8601String().substring(11, 23)} '
          '+${(ms / 1000).toStringAsFixed(2)}s  $line\n', mode: FileMode.append);
    } catch (_) {}
  }
}
