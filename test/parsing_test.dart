import 'package:flutter_test/flutter_test.dart';
import 'package:live_tv_player/api.dart';
import 'package:live_tv_player/epg.dart';

void main() {
  test('parses M3U and skips movies/series', () {
    final r = parseM3u('#EXTM3U url-tvg="http://x/epg.xml"\n'
        '#EXTINF:-1 tvg-id="dr1.dk" tvg-logo="http://l/1.png" group-title="Denmark",DR 1\n'
        'http://x/live/u/p/1.ts\n'
        '#EXTINF:-1 group-title="Movies",Some film\n'
        'http://x/movie/u/p/9.mkv\n');
    expect(r.channels.length, 1);
    expect(r.channels.single.name, 'DR 1');
    expect(r.channels.single.epgId, 'dr1.dk');
    expect(r.epgUrl, 'http://x/epg.xml');
  });

  test('XMLTV time with offset', () {
    final ms = parseXmltvTime('20261123150000 +0100')!;
    expect(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        DateTime.utc(2026, 11, 23, 14));
  });

  test('server normalisation', () {
    expect(normalizeServer('example.com:8080/'), 'http://example.com:8080');
  });
}
