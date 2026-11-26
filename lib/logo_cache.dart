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

  /// Download [url] to disk (a few downloads at a time). Logos on screen
  /// ([visible]) always go before the background prefetch of the whole list.
  static Future<File?> fetch(String url, {bool visible = true}) {
    final done = _ready[url];
    if (done != null) return Future.value(done);
    if (_failed.contains(url)) return Future.value(null);
    if (visible) _wanted.add(url);
    return _loading[url] ??=
        _download(url).whenComplete(() => _loading.remove(url));
  }

  static const _maxParallel = 8;
  static final Set<String> _wanted = {}; // urls shown on screen

  static Future<void> _acquire(String url) async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(MapEntry(url, c));
    await c.future; // the slot is handed over by _release
  }

  static void _release() {
    if (_queue.isEmpty) {
      _active--;
      return;
    }
    // On-screen logos first, then the rest in list order. (Checking at
    // release time matters: after a channel refresh the whole list is
    // queued before the screen asks for its logos.)
    var i = _queue.indexWhere((e) => _wanted.contains(e.key));
    if (i < 0) i = 0;
    _queue.removeAt(i).value.complete();
  }

  static Future<File?> _download(String url) async {
    final f = _fileFor(url);
    if (await f.exists()) return _ready[url] = f;
    await _acquire(url);
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
      _wanted.remove(url);
      _release();
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
