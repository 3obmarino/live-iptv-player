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
}
