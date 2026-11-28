import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'models.dart';
import 'storage.dart';

class Reminder {
  Reminder(this.channelId, this.channelName, this.title, this.start, this.stop);
  final String channelId;
  final String channelName;
  final String title;
  final int start; // epoch ms
  final int stop;

  String get key => '$channelId@$start';

  /// Small positive id for the Android alarm.
  int get alarmId => key.hashCode & 0x7fffffff;

  Map<String, dynamic> toJson() =>
      {'c': channelId, 'n': channelName, 't': title, 's': start, 'e': stop};
  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(j['c'] as String,
      j['n'] as String? ?? '', j['t'] as String? ?? '', (j['s'] as num).toInt(), (j['e'] as num).toInt());
}

/// "Remind me": a pop-up with "Watch now" when a programme starts.
/// While the app runs, a timer checks every 15 s. On Android an alarm also
/// brings the app to the front at the start time (needs "Display over other
/// apps", the same permission as Start on boot).
class Reminders extends ChangeNotifier {
  Reminders._();
  static final Reminders I = Reminders._();

  static const _ch = MethodChannel('livetv/boot');
  static const _file = 'reminders.json';

  List<Reminder> items = [];

  /// The reminder that just became due (the app shows the pop-up).
  final due = ValueNotifier<Reminder?>(null);
  Timer? _timer;

  Future<void> init() async {
    final j = await Store.readJson(_file);
    if (j is List) {
      items = [for (final r in j) Reminder.fromJson((r as Map).cast<String, dynamic>())];
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    items.removeWhere((r) => r.stop < now);
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    _check();
  }

  bool has(Channel c, Programme p) => items.any((r) => r.channelId == c.id && r.start == p.start);

  /// Adds or removes the reminder. Returns true when it was added.
  Future<bool> toggle(Channel c, Programme p) async {
    final i = items.indexWhere((r) => r.channelId == c.id && r.start == p.start);
    if (i >= 0) {
      final r = items.removeAt(i);
      _native('cancelReminder', {'id': r.alarmId});
      await _save();
      notifyListeners();
      return false;
    }
    final r = Reminder(c.id, c.name, p.title, p.start, p.stop);
    items.add(r);
    _native('scheduleReminder', {'id': r.alarmId, 'at': r.start - 60000});
    await _save();
    notifyListeners();
    return true;
  }

  void _check() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final fire = items.where((r) => r.start - 30000 <= now).toList();
    if (fire.isEmpty) return;
    items.removeWhere(fire.contains);
    _save();
    notifyListeners();
    // newest that is still on air
    final live = fire.where((r) => r.stop > now).toList()..sort((a, b) => b.start.compareTo(a.start));
    if (live.isNotEmpty) due.value = live.first;
  }

  Channel? channelFor(Reminder r) {
    for (final c in AppState.I.channels) {
      if (c.id == r.channelId) return c;
    }
    return null;
  }

  Future<void> _save() =>
      Store.writeJson(_file, [for (final r in items) r.toJson()]);

  void _native(String method, Map<String, Object> args) {
    if (!Platform.isAndroid) return;
    _ch.invokeMethod<void>(method, args).catchError((_) {});
  }
}
