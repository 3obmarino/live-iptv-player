import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart' show describeError;

/// Build number baked in by CI (--dart-define=APP_BUILD=N). 0 = local build.
const int appBuild = int.fromEnvironment('APP_BUILD', defaultValue: 0);
const String appVersion = appBuild == 0 ? 'dev' : '1.0.$appBuild';
const String _repo = '3obmarino/live-iptv-player';

/// Set by the Google TV build (--dart-define=TV=true).
const bool kTvBuild = bool.fromEnvironment('TV', defaultValue: false);

class UpdateInfo {
  UpdateInfo(this.build, this.version, this.windowsUrl, this.apkUrl, this.pageUrl,
      {this.sha256 = const {}, this.sumsUrl});
  /// download URL -> expected lowercase hex SHA-256 (from GitHub's asset digest)
  final Map<String, String> sha256;
  /// SHA256SUMS.txt in the release (fallback when GitHub gives no digest)
  final String? sumsUrl;
  final int build;
  final String version;
  final String? windowsUrl;
  final String? apkUrl;
  final String pageUrl;
}

/// Checks GitHub Releases for a newer build and installs it.
class Updater extends ChangeNotifier {
  Updater._();
  static final Updater I = Updater._();

  UpdateInfo? available;
  bool dismissed = false;
  bool installing = false;
  double? progress;
  String? error;
  DateTime? lastCheck;
  Timer? _timer;

  void start() {
    _cleanOldDownloads();
    if (appBuild == 0) return;
    Timer(const Duration(seconds: 5), check);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(hours: 12), (_) => check());
  }

  /// Remove update installers left behind by earlier updates: %TEMP% on
  /// Windows, the app's cache on Android (a 50 MB APK per update adds up on
  /// TV boxes with little storage). A file still in use is simply skipped.
  void _cleanOldDownloads() {
    if (!Platform.isWindows && !Platform.isAndroid) return;
    Timer(const Duration(seconds: 30), () async {
      try {
        final dir = Platform.isWindows ? Directory.systemTemp : await getTemporaryDirectory();
        for (final f in dir.listSync()) {
          final name = f.uri.pathSegments.isEmpty ? '' : f.uri.pathSegments.last;
          if (f is File && name.startsWith('LiveTV-update-')) {
            try {
              f.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}
    });
  }

  /// Returns the newer release, or null if up to date / offline.
  Future<UpdateInfo?> check() async {
    lastCheck = DateTime.now();
    try {
      final r = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return available;
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final tag = j['tag_name'] as String? ?? '';
      final b = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
      if (b <= appBuild) {
        available = null;
        notifyListeners();
        return null;
      }
      String? win;
      String? apk;
      String? sums;
      final digests = <String, String>{};
      for (final a in (j['assets'] as List? ?? const [])) {
        if (a is! Map) continue;
        final name = a['name'] as String? ?? '';
        final url = a['browser_download_url'] as String?;
        final digest = a['digest'] as String?;
        if (url != null && digest != null && digest.startsWith('sha256:')) {
          digests[url] = digest.substring(7).toLowerCase();
        }
        if (name == 'SHA256SUMS.txt') sums = url;
        if (name.toLowerCase().endsWith('.exe')) win = url;
        final lower = name.toLowerCase();
        final isTvApk = lower.contains('-tv');
        if (lower.endsWith('.apk') && isTvApk == kTvBuild) apk = url;
      }
      final isNew = available?.build != b;
      available = UpdateInfo(b, tag.startsWith('v') ? tag.substring(1) : tag, win, apk,
          j['html_url'] as String? ?? 'https://github.com/$_repo/releases/latest',
          sha256: digests, sumsUrl: sums);
      if (isNew) dismissed = false;
      notifyListeners();
      return available;
    } catch (_) {
      return available;
    }
  }

  void show() {
    dismissed = false;
    notifyListeners();
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  /// Windows: download the installer, run it silently and quit (the
  /// installer closes this app if needed and starts the new version).
  /// Android / Google TV: download the APK and open the system installer.
  Future<void> install() async {
    final u = available;
    if (u == null || installing) return;
    final url = Platform.isWindows ? u.windowsUrl : (Platform.isAndroid ? u.apkUrl : null);
    if (url == null) {
      await launchUrl(Uri.parse(u.pageUrl), mode: LaunchMode.externalApplication);
      return;
    }
    installing = true;
    progress = 0;
    error = null;
    notifyListeners();
    try {
      final dir = Platform.isWindows ? Directory.systemTemp : await getTemporaryDirectory();
      final ext = Platform.isWindows ? 'exe' : 'apk';
      final file = File('${dir.path}${Platform.pathSeparator}LiveTV-update-${u.version}.$ext');
      await _download(url, file);
      await _verify(u, url, file);
      if (Platform.isWindows) {
        await Process.start(
          file.path,
          ['/SILENT', '/SUPPRESSMSGBOXES', '/CLOSEAPPLICATIONS', '/NORESTART'],
          mode: ProcessStartMode.detached,
        );
        exit(0);
      }
      final r = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      installing = false;
      progress = null;
      if (r.type != ResultType.done) error = r.message;
      notifyListeners();
    } catch (e) {
      installing = false;
      progress = null;
      error = describeError(e);
      notifyListeners();
    }
  }

  /// Refuses to install unless the file's SHA-256 matches what the release
  /// says. Protects against broken or tampered downloads.
  Future<void> _verify(UpdateInfo u, String url, File file) async {
    var expected = u.sha256[url];
    if (expected == null && u.sumsUrl != null) {
      final r = await http.get(Uri.parse(u.sumsUrl!)).timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) {
        final name = Uri.parse(url).pathSegments.last;
        for (final line in const LineSplitter().convert(r.body)) {
          final parts = line.trim().split(RegExp(r'\s+\*?'));
          if (parts.length >= 2 && parts.last == name) expected = parts.first.toLowerCase();
        }
      }
    }
    if (expected == null) {
      await file.delete().catchError((_) => file);
      throw Exception('Could not verify the update (no checksum published)');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      await file.delete().catchError((_) => file);
      throw Exception('The downloaded update failed verification and was deleted');
    }
  }

  Future<void> _download(String url, File file) async {
    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 60));
      if (resp.statusCode != 200) throw Exception('Download failed (HTTP ${resp.statusCode})');
      final total = resp.contentLength ?? 0;
      var got = 0;
      var lastPct = -1;
      final sink = file.openWrite();
      try {
        await for (final chunk in resp.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final pct = got * 100 ~/ total;
            if (pct != lastPct) {
              lastPct = pct;
              progress = got / total;
              notifyListeners();
            }
          }
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}
