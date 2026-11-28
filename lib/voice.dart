import 'dart:io';

import 'package:flutter/services.dart';

import 'epg.dart';
import 'l10n.dart';
import 'models.dart';

/// Voice search with the device's own speech recognizer (Android phones and
/// Google TV). Nothing is recorded by the app itself.
class Voice {
  static const _ch = MethodChannel('livetv/boot');
  static bool? _available;

  static Future<bool> available() async {
    if (!Platform.isAndroid) return false;
    try {
      return _available ??= await _ch.invokeMethod<bool>('voiceAvailable') ?? false;
    } catch (_) {
      return _available = false;
    }
  }

  /// Listens once and returns what was said, or null.
  static Future<String?> listen() async {
    if (!await available()) return null;
    try {
      final text = await _ch.invokeMethod<String>('voiceSearch', {
        'language': L10n.isDanish ? 'da-DK' : null,
        'prompt': tr('Say a channel name'),
      });
      final t = text?.trim();
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  /// Text entry fallback (native dialog on TV) for when voice isn't there.
  static Future<String?> type(String label, String text, {String? hint}) async {
    try {
      return await _ch.invokeMethod<String>(
          'editText', {'label': label, 'text': text, 'kind': 'search', 'hint': hint ?? ''});
    } catch (_) {
      return null;
    }
  }
}

/// Channel names often differ a bit from what is spoken ("dr 1" vs "DR1",
/// "tv2" vs "TV 2"): compare without spaces and punctuation.
String searchKey(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[\s\-_.:|/\\()\[\]]+'), '');

bool matchesSearch(String name, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final n = name.toLowerCase();
  if (n.contains(q)) return true;
  // every spoken word must appear (in any order), or the squashed form
  final words = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  if (words.every((w) => n.contains(w))) return true;
  return searchKey(name).contains(searchKey(query));
}

/// Search result list: channels whose name matches first, then channels with
/// a programme (now or later in the TV guide) whose title matches, soonest
/// first. So "kessler" finds the channel showing a programme of that name.
List<Channel> searchChannels(List<Channel> channels, EpgData epg, String query) {
  final q = query.trim();
  if (q.isEmpty) return const <Channel>[];
  final now = DateTime.now().millisecondsSinceEpoch;
  final byName = <Channel>[];
  final byProg = <(Channel, int)>[];
  for (final c in channels) {
    if (matchesSearch(c.name, q)) {
      byName.add(c);
      continue;
    }
    for (final p in epg.forChannel(c)) {
      if (p.stop <= now) continue;
      if (matchesSearch(p.title, q)) {
        byProg.add((c, p.start));
        break;
      }
    }
  }
  byProg.sort((a, b) => a.$2.compareTo(b.$2));
  return [...byName, for (final e in byProg) e.$1];
}
