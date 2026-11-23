import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'api.dart';
import 'epg.dart';
import 'models.dart';
import 'storage.dart';

/// Single app-wide state object. Widgets listen with ListenableBuilder.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState I = AppState._();

  Settings settings = Settings();
  List<Profile> profiles = [];
  String? activeId;

  List<Category> categories = [];
  List<Channel> channels = [];
  bool loadingChannels = false;
  String? channelsError;
  DateTime? _lastChannelAttempt;

  EpgData _epgRaw = EpgData.empty();
  EpgData epg = EpgData.empty();
  bool epgLoading = false;
  String? epgError;
  DateTime? _lastEpgAttempt;

  Timer? _ticker;

  Profile? get active {
    for (final p in profiles) {
      if (p.id == activeId) return p;
    }
    return null;
  }

  ThemeMode get themeMode => switch (settings.themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ---------------------------------------------------------------- startup

  Future<void> init() async {
    await Store.init();
    final j = await Store.readJson('state.json');
    if (j is Map<String, dynamic>) {
      final sj = j['settings'];
      if (sj is Map) settings = Settings.fromJson(sj.cast<String, dynamic>());
      final pl = j['profiles'];
      if (pl is List) {
        profiles = [
          for (final p in pl) Profile.fromJson((p as Map).cast<String, dynamic>())
        ];
      }
      activeId = j['active'] as String?;
    }
    if (active == null && profiles.isNotEmpty) activeId = profiles.first.id;
    await _loadActiveCaches();

    // The scheduler. This is what fixes the "auto refresh never happens" bug:
    // every minute we check whether the EPG is older than the chosen
    // frequency and refresh it. It also catches up after sleep/hibernate,
    // because "due" is computed from the saved last-refresh time, not from
    // a one-shot timer.
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    Timer(const Duration(seconds: 2), _tick);
  }

  Future<void> _loadActiveCaches() async {
    final p = active;
    channels = [];
    categories = [];
    _epgRaw = EpgData.empty();
    epg = EpgData.empty();
    channelsError = null;
    epgError = null;
    if (p == null) {
      notifyListeners();
      return;
    }
    final cj = await Store.readJson('channels_${p.id}.json');
    if (cj is Map<String, dynamic>) {
      categories = [
        for (final c in (cj['categories'] as List? ?? const []))
          Category.fromJson((c as Map).cast<String, dynamic>())
      ];
      channels = [
        for (final c in (cj['channels'] as List? ?? const []))
          Channel.fromJson((c as Map).cast<String, dynamic>())
      ];
    }
    final cached = await readEpgCache(Store.file('epg_${p.id}.json').path);
    if (cached != null) _epgRaw = cached;
    _applyShift();
    notifyListeners();
  }

  void _applyShift() {
    epg = _epgRaw.shifted(settings.epgTimeShiftHours * 3600000);
  }

  Future<void> save() => Store.writeJson('state.json', {
        'settings': settings.toJson(),
        'profiles': [for (final p in profiles) p.toJson()],
        'active': activeId,
      });

  // -------------------------------------------------------------- scheduler

  void _tick() {
    final p = active;
    if (p == null) return;
    final now = DateTime.now();
    final channelsStale = channels.isEmpty ||
        p.channelsUpdated == null ||
        now.difference(p.channelsUpdated!) > const Duration(hours: 24);
    final mayRetry = _lastChannelAttempt == null ||
        now.difference(_lastChannelAttempt!) > const Duration(minutes: 15);
    if (!loadingChannels && channelsStale && mayRetry) {
      refreshChannels(p, silent: true);
      return; // EPG check runs on a later tick, once channels exist
    }
    if (epgDue) refreshEpg();
  }

  /// When the next automatic EPG refresh will happen (null = never).
  DateTime? get nextEpgRefresh {
    final p = active;
    if (p == null || !settings.epgEnabled || settings.epgRefreshHours <= 0) {
      return null;
    }
    final last = p.epgUpdated;
    if (last == null) return DateTime.now();
    return last.add(Duration(hours: settings.epgRefreshHours));
  }

  bool get epgDue {
    final p = active;
    if (p == null || !settings.epgEnabled || epgLoading || channels.isEmpty) {
      return false;
    }
    if (p.effectiveEpgUrl.isEmpty) return false;
    // After a failed attempt, wait 15 minutes before trying again.
    if (_lastEpgAttempt != null &&
        DateTime.now().difference(_lastEpgAttempt!) <
            const Duration(minutes: 15)) {
      return false;
    }
    // Never loaded: always fetch once, even if auto refresh is disabled.
    if (_epgRaw.isEmpty && p.epgUpdated == null) return true;
    final next = nextEpgRefresh;
    return next != null && !DateTime.now().isBefore(next);
  }

  // ----------------------------------------------------------------- loading

  /// Returns an error message, or null on success.
  Future<String?> refreshChannels(Profile p, {bool silent = false}) async {
    if (loadingChannels) return null;
    loadingChannels = true;
    _lastChannelAttempt = DateTime.now();
    if (p.id == activeId) channelsError = null;
    notifyListeners();
    try {
      final r = p.isXtream
          ? await loadXtream(p, settings.userAgent)
          : await loadM3u(p, settings.userAgent);
      if (r.expDate != null) p.expDate = r.expDate;
      if (!p.isXtream) p.playlistEpgUrl = r.epgUrl;
      p.channelsUpdated = DateTime.now();
      await Store.writeJson('channels_${p.id}.json', {
        'categories': [for (final c in r.categories) c.toJson()],
        'channels': [for (final c in r.channels) c.toJson()],
      });
      if (p.id == activeId) {
        categories = r.categories;
        channels = r.channels;
        // Channel list changed: rebuild the EPG lookup memo.
        _applyShift();
      }
      await save();
      return null;
    } catch (e) {
      final msg = describeError(e);
      if (p.id == activeId) channelsError = msg;
      return msg;
    } finally {
      loadingChannels = false;
      notifyListeners();
    }
  }

  /// Downloads and parses the EPG for the active profile.
  /// Returns an error message, or null on success.
  Future<String?> refreshEpg() async {
    final p = active;
    if (p == null) return 'No profile selected';
    if (epgLoading) return null;
    final url = p.effectiveEpgUrl;
    if (url.isEmpty) return 'This profile has no EPG URL';
    if (channels.isEmpty) return 'Load the channel list first';

    epgLoading = true;
    epgError = null;
    _lastEpgAttempt = DateTime.now();
    notifyListeners();
    final tmp = Store.file('epg_download.tmp');
    try {
      await downloadEpg(url, settings.userAgent, tmp);
      final ids = <String>{
        for (final c in channels)
          if (c.epgId.isNotEmpty) c.epgId
      };
      final names = <String>{for (final c in channels) normalizeName(c.name)};
      final data = await parseEpgFile(tmp.path, ids, names);
      if (data.isEmpty) {
        throw Exception('The EPG contained no programmes for your channels');
      }
      await Store.writeString('epg_${p.id}.json', await encodeEpg(data));
      p.epgUpdated = DateTime.now();
      if (p.id == activeId) {
        _epgRaw = data;
        _applyShift();
      }
      await save();
      return null;
    } catch (e) {
      epgError = describeError(e);
      return epgError;
    } finally {
      epgLoading = false;
      try {
        if (await tmp.exists()) await tmp.delete();
      } on FileSystemException catch (_) {}
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- settings

  Future<void> updateSettings(void Function(Settings s) change) async {
    final oldShift = settings.epgTimeShiftHours;
    change(settings);
    if (settings.epgTimeShiftHours != oldShift) _applyShift();
    notifyListeners();
    await save();
    _tick(); // e.g. a shorter frequency may make a refresh due right now
  }

  // ---------------------------------------------------------------- profiles

  Future<void> addOrUpdateProfile(Profile p) async {
    final i = profiles.indexWhere((x) => x.id == p.id);
    if (i >= 0) {
      profiles[i] = p;
    } else {
      profiles.add(p);
    }
    activeId ??= p.id;
    await save();
    notifyListeners();
  }

  Future<void> profileChanged(Profile p) async {
    await save();
    notifyListeners();
  }

  Future<void> deleteProfile(Profile p) async {
    profiles.removeWhere((x) => x.id == p.id);
    await Store.delete('channels_${p.id}.json');
    await Store.delete('epg_${p.id}.json');
    if (activeId == p.id) {
      activeId = profiles.isEmpty ? null : profiles.first.id;
      await _loadActiveCaches();
    }
    await save();
    notifyListeners();
  }

  Future<void> setActive(Profile p) async {
    if (activeId == p.id) return;
    activeId = p.id;
    _lastEpgAttempt = null;
    _lastChannelAttempt = null;
    await _loadActiveCaches();
    await save();
    _tick();
  }

  // ------------------------------------------------------ favourites/recents

  bool isFavorite(Channel c) => active?.favorites.contains(c.id) ?? false;

  void toggleFavorite(Channel c) {
    final p = active;
    if (p == null) return;
    if (!p.favorites.remove(c.id)) p.favorites.add(c.id);
    notifyListeners();
    save();
  }

  bool isFavoriteCategory(String id) =>
      active?.favoriteCategories.contains(id) ?? false;

  void toggleFavoriteCategory(String id) {
    final p = active;
    if (p == null) return;
    if (!p.favoriteCategories.remove(id)) p.favoriteCategories.add(id);
    notifyListeners();
    save();
  }

  void addRecent(Channel c) {
    final p = active;
    if (p == null) return;
    p.recents.remove(c.id);
    p.recents.insert(0, c.id);
    if (p.recents.length > 30) p.recents.removeRange(30, p.recents.length);
    save();
  }

  List<Channel> get recentChannels {
    final byId = {for (final c in channels) c.id: c};
    return [
      for (final id in active?.recents ?? const <String>[])
        if (byId[id] != null) byId[id]!
    ];
  }

  String streamUrlFor(Channel c) =>
      streamUrl(active!, c, settings.streamFormat);
}
