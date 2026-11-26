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

  /// Up to 1.0.111 the Windows app kept its data in
  /// %APPDATA%\dk.livetvplayer\live_tv_player. Since the publisher became
  /// "Ukendt Software" it is %APPDATA%\Ukendt Software\Live TV Player:
  /// move the old folder over once (profiles, encrypted login, guide, logos).
  static Future<void> _moveOldWindowsData(Directory target) async {
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData == null) return;
      final oldParent = Directory('$appData\\dk.livetvplayer');
      final old = Directory('${oldParent.path}\\live_tv_player');
      if (old.path.toLowerCase() == target.path.toLowerCase()) return;
      if (!await old.exists()) return;
      if (await File('${target.path}\\state.json').exists()) return; // already moved
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        if (await target.list().isEmpty) {
          await target.delete();
        } else {
          return; // something already there: leave both alone
        }
      }
      await old.rename(target.path);
      if (await oldParent.list().isEmpty) await oldParent.delete();
    } catch (_) {
      // Worst case the app starts without profiles; the old folder is kept.
    }
  }
}
