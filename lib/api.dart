import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'l10n.dart';

class PlaylistResult {
  PlaylistResult(this.categories, this.channels,
      {this.expDate, this.epgUrl = ''});
  final List<Category> categories;
  final List<Channel> channels;
  final DateTime? expDate;
  final String epgUrl;
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

String describeError(Object e) {
  if (e is TimeoutException) return tr('The server did not respond in time');
  if (e is SocketException) return tr('Network error: {e}', {'e': e.message});
  if (e is http.ClientException) return tr('Network error: {e}', {'e': e.message});
  if (e is ApiException) return e.message;
  if (e is FormatException) return tr('Invalid data: {e}', {'e': e.message});
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

/// "example.com:8080" -> "http://example.com:8080" (no trailing slash/path).
String normalizeServer(String input) {
  var s = input.trim();
  if (s.isEmpty) return s;
  if (!s.contains('://')) s = 'http://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty) return s;
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null)
      .toString();
}

Map<String, String> _headers(String ua) =>
    ua.isEmpty ? <String, String>{} : <String, String>{'User-Agent': ua};

String _str(Object? v) => v == null ? '' : '$v'.trim();

Future<dynamic> _getJson(Uri uri, Map<String, String> headers) async {
  final r = await http
      .get(uri, headers: headers)
      .timeout(const Duration(seconds: 60));
  if (r.statusCode != 200) {
    throw ApiException(tr('The server responded with HTTP {c}', {'c': r.statusCode}));
  }
  try {
    return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
  } catch (_) {
    throw ApiException(tr('The server returned an invalid response'));
  }
}

Future<PlaylistResult> loadXtream(Profile p, String ua) async {
  final h = _headers(ua);
  Uri api([Map<String, String> extra = const {}]) =>
      Uri.parse('${p.server}/player_api.php').replace(queryParameters: {
        'username': p.username,
        'password': p.password,
        ...extra,
      });

  final info = await _getJson(api(), h);
  DateTime? exp;
  if (info is Map) {
    final ui = info['user_info'];
    if (ui is Map) {
      if (_str(ui['auth']) == '0') {
        throw ApiException(tr('Login was rejected by the server'));
      }
      final e = int.tryParse(_str(ui['exp_date']));
      if (e != null && e > 0) {
        exp = DateTime.fromMillisecondsSinceEpoch(e * 1000);
      }
    }
  }

  final cats = await _getJson(api({'action': 'get_live_categories'}), h);
  final streams = await _getJson(api({'action': 'get_live_streams'}), h);

  final categories = <Category>[];
  if (cats is List) {
    for (final c in cats) {
      if (c is Map) {
        categories.add(Category(_str(c['category_id']), _str(c['category_name'])));
      }
    }
  }
  final channels = <Channel>[];
  if (streams is List) {
    for (final s in streams) {
      if (s is! Map) continue;
      final id = _str(s['stream_id']);
      if (id.isEmpty) continue;
      channels.add(Channel(
        id: id,
        name: _str(s['name']),
        logo: _str(s['stream_icon']),
        epgId: _str(s['epg_channel_id']),
        categoryId: _str(s['category_id']),
        added: int.tryParse(_str(s['added'])) ?? 0,
        number: int.tryParse(_str(s['num'])) ?? 0,
      ));
    }
  }
  if (channels.isEmpty) throw ApiException(tr('No live channels were returned'));
  return PlaylistResult(categories, channels, expDate: exp);
}

Future<PlaylistResult> loadM3u(Profile p, String ua) async {
  final r = await http
      .get(Uri.parse(p.m3uUrl.trim()), headers: _headers(ua))
      .timeout(const Duration(seconds: 120));
  if (r.statusCode != 200) {
    throw ApiException(tr('The server responded with HTTP {c}', {'c': r.statusCode}));
  }
  final result = parseM3u(utf8.decode(r.bodyBytes, allowMalformed: true));
  if (result.channels.isEmpty) {
    throw ApiException(tr('No live channels found in the playlist'));
  }
  return result;
}

final _attrRe = RegExp(r'([A-Za-z0-9_-]+)="([^"]*)"');

PlaylistResult parseM3u(String text) {
  var epgUrl = '';
  final channels = <Channel>[];
  final groupOrder = <String>[];
  final groupSet = <String>{};
  Map<String, String>? attrs;
  var name = '';

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      for (final m in _attrRe.allMatches(line)) {
        final k = m.group(1)!.toLowerCase();
        if ((k == 'url-tvg' || k == 'x-tvg-url') && epgUrl.isEmpty) {
          epgUrl = m.group(2)!.split(',').first.trim();
        }
      }
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      final a = <String, String>{};
      for (final m in _attrRe.allMatches(line)) {
        a[m.group(1)!.toLowerCase()] = m.group(2)!;
      }
      attrs = a;
      final q = line.lastIndexOf('"');
      final c = line.indexOf(',', q < 0 ? 0 : q);
      name = c >= 0 ? line.substring(c + 1).trim() : '';
      continue;
    }
    if (line.startsWith('#')) continue;
    final a = attrs;
    if (a == null) continue;
    attrs = null;

    final url = line;
    final lower = url.toLowerCase();
    if (lower.contains('/movie/') || lower.contains('/series/')) continue;

    final group = (a['group-title'] ?? '').trim();
    final g = group.isEmpty ? 'Uncategorised' : group;
    if (groupSet.add(g)) groupOrder.add(g);
    channels.add(Channel(
      id: url,
      name: name.isNotEmpty ? name : (a['tvg-name'] ?? url),
      logo: a['tvg-logo'] ?? '',
      epgId: a['tvg-id'] ?? '',
      categoryId: g,
      number: channels.length + 1,
      url: url,
    ));
  }
  return PlaylistResult([for (final g in groupOrder) Category(g, g)], channels,
      epgUrl: epgUrl);
}

String streamUrl(Profile p, Channel c, String format) {
  if (!p.isXtream) return c.url;
  final ext = format == 'm3u8' ? 'm3u8' : 'ts';
  return '${p.server}/live/${Uri.encodeComponent(p.username)}/'
      '${Uri.encodeComponent(p.password)}/${c.id}.$ext';
}
