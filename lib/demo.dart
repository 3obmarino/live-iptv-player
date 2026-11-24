import 'dart:math' as math;

import 'epg.dart';
import 'models.dart';

/// Demo build (--dart-define=DEMO=true) used by the automated TV emulator
/// test: invented channels, a generated TV guide and free public test
/// streams. No provider data is involved.
const bool kDemo = bool.fromEnvironment('DEMO', defaultValue: false);

const _streams = [
  'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8',
];

const _cats = <String, List<String>>{
  'Denmark': ['Nordic One', 'Nordic Two', 'Kanal Øst', 'Kanal Vest', 'Fjord TV', 'Hygge HD',
      'Bølge 7', 'Lyngby Live', 'Aros TV', 'Skagen Plus'],
  'Sport': ['Sport 1', 'Sport 2', 'Sport X', 'Arena Live', 'Goal TV', 'Racing Plus',
      'Tennis Court', 'Fight Night'],
  'News': ['World News 24', 'Nordic News', 'Business Today', 'Weather Now'],
  'Kids': ['Kids Fun', 'Cartoon World', 'Junior TV', 'Toon Time [Multi-Audio]'],
  'Documentary': ['Planet Wild', 'Science One', 'History Vault', 'Deep Ocean', 'Space Station',
      'Machines [Multi-Sub]'],
};

const _titles = [
  'Morning Show', 'The Daily Match', 'Kitchen Heroes', 'Coastal Patrol', 'Deadline',
  'Hidden Treasures', 'Road Trip Nordic', 'Weekend Football Studio', 'Superliga Live',
  'Wild Arctic', 'Night News', 'The Big Quiz', 'Classic Movie', 'Car Rescue',
  'Ocean Giants', 'Tennis: Final', 'Cartoon Hour', 'Mysteries of the Past',
  'Builders', 'Late Talk', 'Market Watch', 'Weather Update', 'Space Frontier',
];

List<Category> demoCategories() => [for (final c in _cats.keys) Category(c, c)];

List<Channel> demoChannels() {
  final out = <Channel>[];
  var i = 0;
  _cats.forEach((cat, names) {
    for (final n in names) {
      out.add(Channel(
        id: 'demo$i',
        name: n,
        epgId: i % 9 == 8 ? '' : 'demo$i', // a few channels without guide
        categoryId: cat,
        num: i + 1,
        url: _streams[i % _streams.length],
      ));
      i++;
    }
  });
  return out;
}

EpgData demoEpg(List<Channel> channels) {
  final r = math.Random(42);
  const durations = [15, 25, 30, 45, 50, 60, 90, 120];
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day, now.hour).subtract(const Duration(hours: 2));
  final end = start.add(const Duration(hours: 14));
  final byId = <String, List<Programme>>{};
  for (final c in channels) {
    if (c.epgId.isEmpty) continue;
    final list = <Programme>[];
    var t = start.subtract(Duration(minutes: r.nextInt(40)));
    while (t.isBefore(end)) {
      final d = durations[r.nextInt(durations.length)];
      final stop = t.add(Duration(minutes: d));
      final title = _titles[r.nextInt(_titles.length)];
      list.add(Programme(
        t.millisecondsSinceEpoch,
        stop.millisecondsSinceEpoch,
        title,
        '$title on ${c.name}. A made-up programme description used to check how '
            'the TV guide lays out longer text across two or three lines.',
      ));
      t = stop;
    }
    byId[c.epgId.toLowerCase()] = list;
  }
  return EpgData(byId, const {});
}
