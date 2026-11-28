import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

import 'models.dart';
import 'l10n.dart';

/// Loose channel-name key used to match playlist channels to XMLTV
/// display-names when the playlist has no (or a wrong) EPG id.
String normalizeName(String s) {
  var n = s.toLowerCase();
  n = n.replaceAll(RegExp(r'\[[^\]]*\]|\([^)]*\)'), ' ');
  n = n.replaceFirst(RegExp(r'^\s*[a-z]{2,3}\s*[:|]\s*'), '');
  n = n.replaceAll(RegExp(r'\b(uhd|fhd|hd|sd|4k|hevc)\b'), ' ');
  n = n.replaceAll(RegExp(r'[^a-z0-9æøå]'), '');
  return n;
}

/// "20261123150000 +0100" -> epoch ms. No offset = UTC (XMLTV spec).
int? parseXmltvTime(String s) {
  s = s.trim();
  if (s.length < 14) return null;
  final y = int.tryParse(s.substring(0, 4));
  final mo = int.tryParse(s.substring(4, 6));
  final d = int.tryParse(s.substring(6, 8));
  final h = int.tryParse(s.substring(8, 10));
  final mi = int.tryParse(s.substring(10, 12));
  final se = int.tryParse(s.substring(12, 14));
  if (y == null || mo == null || d == null || h == null || mi == null || se == null) {
    return null;
  }
  var ms = DateTime.utc(y, mo, d, h, mi, se).millisecondsSinceEpoch;
  final rest = s.substring(14).trim();
  if (rest.length >= 5 && (rest[0] == '+' || rest[0] == '-')) {
    final oh = int.tryParse(rest.substring(1, 3)) ?? 0;
    final om = int.tryParse(rest.substring(3, 5)) ?? 0;
    final sign = rest[0] == '+' ? 1 : -1;
    ms -= sign * (oh * 60 + om) * 60000;
  }
  return ms;
}

class EpgData {
  EpgData(this.byId, this.nameToId);
  EpgData.empty()
      : byId = <String, List<Programme>>{},
        nameToId = <String, String>{};

  /// Lower-cased XMLTV channel id -> programmes sorted by start.
  final Map<String, List<Programme>> byId;

  /// normalizeName(display-name) -> XMLTV channel id.
  final Map<String, String> nameToId;
  final Map<String, List<Programme>> _memo = {};

  bool get isEmpty => byId.isEmpty;

  List<Programme> forChannel(Channel c) {
    return _memo.putIfAbsent(c.id, () {
      if (c.epgId.isNotEmpty) {
        final l = byId[c.epgId.toLowerCase()];
        if (l != null) return l;
      }
      final id = nameToId[normalizeName(c.name)];
      if (id != null) return byId[id] ?? const <Programme>[];
      return const <Programme>[];
    });
  }

  EpgData shifted(int ms) => ms == 0
      ? EpgData(byId, nameToId)
      : EpgData({
          for (final e in byId.entries)
            e.key: [for (final p in e.value) p.shifted(ms)]
        }, nameToId);

  Map<String, dynamic> toJson() => {
        'v': 1,
        'c': {
          for (final e in byId.entries)
            e.key: [
              for (final p in e.value) [p.start, p.stop, p.title, p.desc]
            ]
        },
        'n': nameToId,
      };

  factory EpgData.fromJson(Map<String, dynamic> j) {
    final byId = <String, List<Programme>>{};
    final c = (j['c'] as Map?) ?? const {};
    c.forEach((k, v) {
      byId[k as String] = [
        for (final e in (v as List))
          Programme((e[0] as num).toInt(), (e[1] as num).toInt(),
              e[2] as String, e[3] as String)
      ];
    });
    final n = <String, String>{};
    ((j['n'] as Map?) ?? const {}).forEach((k, v) => n[k as String] = v as String);
    return EpgData(byId, n);
  }
}

/// Streams the XMLTV file to disk (it can be tens of MB).
Future<void> downloadEpg(String url, String ua, File target) async {
  final client = http.Client();
  try {
    final req = http.Request('GET', Uri.parse(url));
    if (ua.isNotEmpty) req.headers['User-Agent'] = ua;
    final resp = await client.send(req).timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw Exception(tr('The EPG server responded with HTTP {c}', {'c': resp.statusCode}));
    }
    final sink = target.openWrite();
    try {
      await sink.addStream(resp.stream.timeout(const Duration(seconds: 60)));
    } finally {
      await sink.close();
    }
  } finally {
    client.close();
  }
}

/// Parses in a background isolate so the UI never freezes.
Future<EpgData> parseEpgFile(
        String path, Set<String> wantedIds, Set<String> wantedNames) =>
    Isolate.run(() => _parse(path, wantedIds, wantedNames));

Future<EpgData?> readEpgCache(String path) => Isolate.run(() async {
      final f = File(path);
      if (!await f.exists()) return null;
      try {
        return EpgData.fromJson(
            jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      } catch (_) {
        return null;
      }
    });

Future<String> encodeEpg(EpgData d) => Isolate.run(() => jsonEncode(d.toJson()));

String? _attr(XmlStartElementEvent e, String name) {
  for (final a in e.attributes) {
    if (a.name == name) return a.value;
  }
  return null;
}

Future<EpgData> _parse(
    String path, Set<String> wantedIds, Set<String> wantedNames) async {
  final file = File(path);
  final raf = await file.open();
  final head = await raf.read(2);
  await raf.close();
  Stream<List<int>> bytes = file.openRead();
  if (head.length == 2 && head[0] == 0x1f && head[1] == 0x8b) {
    bytes = bytes.transform(gzip.decoder);
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final from = now - const Duration(hours: 12).inMilliseconds;
  final to = now + const Duration(days: 8).inMilliseconds;
  final ids = <String>{for (final i in wantedIds) i.toLowerCase()};
  final nameToId = <String, String>{};
  final byId = <String, List<Programme>>{};

  String? chId;
  var inDisplayName = false;
  final dn = StringBuffer();

  String? pCh;
  var pStart = 0, pStop = 0;
  var inTitle = false, inDesc = false, titleDone = false, descDone = false;
  final title = StringBuffer();
  final desc = StringBuffer();

  void text(String v) {
    if (inDisplayName) {
      dn.write(v);
    } else if (inTitle) {
      title.write(v);
    } else if (inDesc) {
      desc.write(v);
    }
  }

  final events = bytes
      .transform(const Utf8Decoder(allowMalformed: true))
      .toXmlEvents();

  await for (final batch in events) {
    for (final e in batch) {
      if (e is XmlStartElementEvent) {
        final n = e.name;
        if (n == 'channel') {
          chId = e.isSelfClosing ? null : _attr(e, 'id')?.toLowerCase();
        } else if (n == 'display-name') {
          if (chId != null && !e.isSelfClosing) {
            inDisplayName = true;
            dn.clear();
          }
        } else if (n == 'programme') {
          pCh = null;
          final c = _attr(e, 'channel')?.toLowerCase();
          final s = parseXmltvTime(_attr(e, 'start') ?? '');
          final st = parseXmltvTime(_attr(e, 'stop') ?? '');
          if (!e.isSelfClosing &&
              c != null &&
              ids.contains(c) &&
              s != null &&
              st != null &&
              st > s &&
              st > from &&
              s < to) {
            pCh = c;
            pStart = s;
            pStop = st;
            title.clear();
            desc.clear();
            titleDone = false;
            descDone = false;
          }
        } else if (n == 'title') {
          if (pCh != null && !titleDone && !e.isSelfClosing) inTitle = true;
        } else if (n == 'desc') {
          if (pCh != null && !descDone && !e.isSelfClosing) inDesc = true;
        }
      } else if (e is XmlTextEvent) {
        text(e.value);
      } else if (e is XmlCDATAEvent) {
        text(e.value);
      } else if (e is XmlEndElementEvent) {
        final n = e.name;
        if (n == 'display-name') {
          if (inDisplayName) {
            inDisplayName = false;
            final key = normalizeName(dn.toString());
            final id = chId;
            if (id != null && key.isNotEmpty && wantedNames.contains(key)) {
              nameToId.putIfAbsent(key, () => id);
              ids.add(id);
            }
          }
        } else if (n == 'channel') {
          chId = null;
        } else if (n == 'title') {
          if (inTitle) {
            inTitle = false;
            titleDone = true;
          }
        } else if (n == 'desc') {
          if (inDesc) {
            inDesc = false;
            descDone = true;
          }
        } else if (n == 'programme') {
          final c = pCh;
          if (c != null) {
            (byId[c] ??= <Programme>[]).add(Programme(
                pStart, pStop, title.toString().trim(), desc.toString().trim()));
          }
          pCh = null;
        }
      }
    }
  }
  for (final l in byId.values) {
    l.sort((a, b) => a.start.compareTo(b.start));
  }
  return EpgData(byId, nameToId);
}
