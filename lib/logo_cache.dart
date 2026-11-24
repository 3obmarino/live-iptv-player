import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import 'storage.dart';

/// Channel logos cached on disk, so they are downloaded once instead of on
/// every app start. All sizes share one decoded image in memory.
class LogoCache {
  LogoCache._();

  /// Every logo is decoded at this width, whatever size it is shown at, so
  /// the guide, info panel and tiles reuse the same in-memory image.
  static const decodeWidth = 220;

  static Directory? _dir;
  static final Map<String, File> _ready = {}; // url -> file on disk
  static final Map<String, Future<File?>> _loading = {};
  static final Set<String> _failed = {};
  static int _active = 0;
  static final List<MapEntry<String, Completer<void>>> _queue = [];

  static Directory get _folder =>
      _dir ??= Directory('${Store.dir.path}${Platform.pathSeparator}logos')
        ..createSync(recursive: true);

  static File _fileFor(String url) => File(
      '${_folder.path}${Platform.pathSeparator}${sha1.convert(utf8.encode(url))}');

  /// The image for [url] if it is already on disk (no waiting), else null.
  static ImageProvider? cached(String url) {
    var f = _ready[url];
    if (f == null) {
      final candidate = _fileFor(url);
      if (candidate.existsSync()) _ready[url] = f = candidate;
    }
    return f == null ? null : provider(f);
  }

  static ImageProvider provider(File f) =>
      ResizeImage(FileImage(f), width: decodeWidth, allowUpscaling: false);

  static bool failed(String url) => _failed.contains(url);

  /// Download [url] to disk (at most 6 downloads at a time). Logos on
  /// screen ([visible]) jump ahead of the background prefetch.
  static Future<File?> fetch(String url, {bool visible = true}) {
    final done = _ready[url];
    if (done != null) return Future.value(done);
    if (_failed.contains(url)) return Future.value(null);
    final running = _loading[url];
    if (running != null) {
      if (visible) {
        final i = _queue.indexWhere((e) => e.key == url);
        if (i > 0) _queue.insert(0, _queue.removeAt(i));
      }
      return running;
    }
    return _loading[url] =
        _download(url, visible).whenComplete(() => _loading.remove(url));
  }

  static Future<File?> _download(String url, bool visible) async {
    final f = _fileFor(url);
    if (await f.exists()) return _ready[url] = f;
    if (_active >= 6) {
      final e = MapEntry(url, Completer<void>());
      visible ? _queue.insert(0, e) : _queue.add(e);
      await e.value.future;
    }
    _active++;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) throw 'HTTP ${r.statusCode}';
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(r.bodyBytes, flush: true);
      await tmp.rename(f.path);
      return _ready[url] = f;
    } catch (_) {
      _failed.add(url); // retried on next app start
      return null;
    } finally {
      _active--;
      if (_queue.isNotEmpty) _queue.removeAt(0).value.complete();
    }
  }

  /// Download every logo in the background, so scrolling the guide never
  /// waits for the network.
  static void prefetch(Iterable<String> urls) {
    for (final u in urls.toSet()) {
      if (u.isNotEmpty) fetch(u, visible: false);
    }
  }
}
