import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny JSON file store in the app support folder
/// (%APPDATA%\<company>\live_tv_player on Windows).
class Store {
  static late Directory dir;
  static final Map<String, Future<void>> _pending = {};

  static Future<void> init() async {
    final base = await getApplicationSupportDirectory();
    dir = Directory(base.path);
    if (Platform.isWindows) await _moveOldWindowsData(dir);
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  static File file(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  static Future<dynamic> readJson(String name) async {
    final f = file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Writes are serialised per file and done atomically (tmp + rename).
  static Future<void> writeJson(String name, Object data) =>
      writeString(name, jsonEncode(data));

  static Future<void> writeString(String name, String text) {
    final prev = _pending[name] ?? Future<void>.value();
    final next = prev.then((_) {}, onError: (_) {}).then((_) async {
      final f = file(name);
      final tmp = file('$name.tmp');
      await tmp.writeAsString(text, flush: true);
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    });
    _pending[name] = next;
    return next;
  }

  static Future<void> delete(String name) async {
    final f = file(name);
    if (await f.exists()) await f.delete();
  }

  /// Older Windows versions kept their data elsewhere: up to 1.0.111 in
  /// %APPDATA%\dk.livetvplayer\live_tv_player, in 1.0.112 in
  /// %APPDATA%\Ukendt Software\Live TV Player. Now the folder follows the
  /// publisher and name: %APPDATA%\Ukendt Software\LiveTV Player. Move the
  /// newest old folder over once (profiles, encrypted login, guide, logos).
  static Future<void> _moveOldWindowsData(Directory target) async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return;
      if (await File('${target.path}\\state.json').exists()) return; // done
      final candidates = [
        Directory('$appData\\Ukendt Software\\Live TV Player'),
        Directory('$appData\\dk.livetvplayer\\live_tv_player'),
      ];
      for (final old in candidates) {
        if (old.path.toLowerCase() == target.path.toLowerCase()) continue;
        if (!await old.exists()) continue;
        await target.parent.create(recursive: true);
        if (await target.exists()) {
          if (!await target.list().isEmpty) return; // something there: leave both
          await target.delete();
        }
        await old.rename(target.path);
        final parent = old.parent;
        if (await parent.exists() && await parent.list().isEmpty) await parent.delete();
        return;
      }
    } catch (_) {
      // Worst case the app starts without profiles; the old folder is kept.
    }
  }
}
