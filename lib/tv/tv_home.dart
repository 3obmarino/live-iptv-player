import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_core.dart';
import '../ui/common.dart';
import '../ui/menu_screen.dart';
import '../updater.dart';
import 'tv_guide.dart';

enum _Mode { play, list, guide }

class _Cat {
  const _Cat(this.id, this.name);
  final String id; // '__fav__', '__all__', '__settings__' or category id
  final String name;
}

/// Google TV home: always-on fullscreen video with remote-driven overlays.
///
/// Playing:  ▲▼ / CH± zap · OK channel list · ▶ or BACK guide · BACK×2 exit
/// List:     ▲▼ move · OK play · hold OK favourite · ◀ categories · ▶ guide
/// Guide:    ▲▼ channel · ◀▶ programme · OK play
class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  final _core = PlayerCore();
  final _focus = FocusNode();
  final _listCtrl = ScrollController();
  final _catCtrl = ScrollController();
  final _guideKey = GlobalKey<TvGuideState>();

  _Mode _mode = _Mode.play;
  bool _catsFocus = false;
  int _cat = 1; // index into _cats(); 1 = All
  int _sel = 0;
  int _catSel = 1;
  List<Channel> _list = const [];
  String? _profileId;

  bool _banner = false;
  Timer? _bannerTimer;
  String? _toast;
  Timer? _toastTimer;
  DateTime? _lastBack;
  bool _okDown = false;
  bool _okLong = false;
  Timer? _clock;

  static const double _rowH = 64;

  @override
  void initState() {
    super.initState();
    _core.addListener(_refresh);
    AppState.I.addListener(_onState);
    Updater.I.addListener(_refresh);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onState());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// Rebuild the channel list when channels/profile change; autoplay once.
  void _onState() {
    if (!mounted) return;
    final s = AppState.I;
    if (_profileId != s.activeId) {
      _profileId = s.activeId;
      _cat = 1;
      _catSel = 1;
      _core.channel = null;
    }
    _rebuildList();
    if (_core.channel == null && s.channels.isNotEmpty) {
      final rec = s.recentChannels;
      final start = rec.isNotEmpty ? rec.first : s.channels.first;
      _play(start, showBanner: true);
    }
    setState(() {});
  }

  List<_Cat> _cats() {
    final s = AppState.I;
    final counts = <String, int>{};
    for (final c in s.channels) {
      counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
    }
    final favCats = s.active?.favoriteCategories ?? const <String>{};
    final cats = s.categories.where((c) => (counts[c.id] ?? 0) > 0).toList()
      ..sort((a, b) => (favCats.contains(a.id) ? 0 : 1).compareTo(favCats.contains(b.id) ? 0 : 1));
    return [
      const _Cat('__fav__', 'Favourites'),
      const _Cat('__all__', 'All channels'),
      for (final c in cats) _Cat(c.id, c.name),
      const _Cat('__settings__', 'Settings'),
    ];
  }

  void _rebuildList() {
    final s = AppState.I;
    final cats = _cats();
    if (_cat >= cats.length - 1) _cat = 1;
    final id = cats[_cat].id;
    final fav = s.active?.favorites ?? const <String>{};
    _list = switch (id) {
      '__fav__' => s.channels.where((c) => fav.contains(c.id)).toList(),
      '__all__' => s.channels,
      _ => s.channels.where((c) => c.categoryId == id).toList(),
    };
    if (_sel >= _list.length) _sel = _list.isEmpty ? 0 : _list.length - 1;
  }

  // -------------------------------------------------------------- actions

  void _play(Channel c, {bool showBanner = true}) {
    _core.play(c);
    final i = _list.indexWhere((x) => x.id == c.id);
    if (i >= 0) _sel = i;
    if (showBanner) _showBanner();
  }

  void _zap(int d) {
    if (_list.isEmpty) return;
    var i = _list.indexWhere((x) => x.id == _core.channel?.id);
    if (i < 0) i = _sel;
    i = (i + d) % _list.length;
    if (i < 0) i += _list.length;
    _play(_list[i]);
  }

  void _showBanner() {
    _bannerTimer?.cancel();
    setState(() => _banner = true);
    _bannerTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _banner = false);
    });
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _openList() {
    _rebuildList();
    final i = _list.indexWhere((x) => x.id == _core.channel?.id);
    _sel = i >= 0 ? i : 0;
    _catsFocus = false;
    setState(() => _mode = _Mode.list);
    _scrollTo(_listCtrl, _sel);
  }

  void _openGuide() {
    _rebuildList();
    setState(() {
      _banner = false;
      _mode = _Mode.guide;
    });
  }

  void _scrollTo(ScrollController c, int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!c.hasClients) return;
      final view = c.position.viewportDimension;
      final target = (index * _rowH - view / 2 + _rowH / 2)
          .clamp(0.0, c.position.maxScrollExtent)
          .toDouble();
      c.jumpTo(target);
    });
  }

  Future<void> _openSettings() async {
    setState(() => _mode = _Mode.play);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const MenuScreen(),
      ),
    ));
    if (mounted) _focus.requestFocus();
  }

  DateTime? _lastBackCall;

  void _back() {
    // Some remotes deliver BACK both as a key and as a system pop: debounce.
    final t = DateTime.now();
    if (_lastBackCall != null && t.difference(_lastBackCall!) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastBackCall = t;
    if (_mode == _Mode.list && _catsFocus) {
      setState(() => _catsFocus = false);
      return;
    }
    if (_mode != _Mode.play) {
      setState(() => _mode = _Mode.play);
      return;
    }
    final now = DateTime.now();
    if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    _showToast('Press BACK again to exit');
  }

  // ------------------------------------------------------------ remote keys

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;

    // OK: act on release so a long press can mean "favourite".
    if (_isOk(k)) {
      if (e is KeyDownEvent) {
        _okDown = true;
        _okLong = false;
      } else if (e is KeyRepeatEvent) {
        if (_okDown && !_okLong) {
          _okLong = true;
          _okLongPress();
        }
      } else if (e is KeyUpEvent) {
        if (_okDown && !_okLong) _okShortPress();
        _okDown = false;
      }
      return KeyEventResult.handled;
    }
    if (e is KeyUpEvent) return KeyEventResult.ignored;

    if (k == LogicalKeyboardKey.goBack || k == LogicalKeyboardKey.escape) {
      if (e is KeyDownEvent) _back();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.mediaPlay ||
        k == LogicalKeyboardKey.mediaPause) {
      _core.player.playOrPause();
      return KeyEventResult.handled;
    }

    switch (_mode) {
      case _Mode.play:
        if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
          _zap(-1);
        } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
          _zap(1);
        } else if (k == LogicalKeyboardKey.arrowRight) {
          _openGuide();
        } else if (k == LogicalKeyboardKey.arrowLeft) {
          _openList();
          setState(() => _catsFocus = true);
          _catSel = _cat;
          _scrollTo(_catCtrl, _catSel);
        } else if (k == LogicalKeyboardKey.info || k == LogicalKeyboardKey.contextMenu) {
          _showBanner();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;

      case _Mode.list:
        if (_catsFocus) {
          final cats = _cats();
          if (k == LogicalKeyboardKey.arrowUp) {
            setState(() => _catSel = (_catSel - 1 + cats.length) % cats.length);
            _scrollTo(_catCtrl, _catSel);
          } else if (k == LogicalKeyboardKey.arrowDown) {
            setState(() => _catSel = (_catSel + 1) % cats.length);
            _scrollTo(_catCtrl, _catSel);
          } else if (k == LogicalKeyboardKey.arrowRight) {
            _chooseCategory();
          }
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
          if (_list.isNotEmpty) {
            setState(() => _sel = (_sel - 1 + _list.length) % _list.length);
            _scrollTo(_listCtrl, _sel);
          }
        } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
          if (_list.isNotEmpty) {
            setState(() => _sel = (_sel + 1) % _list.length);
            _scrollTo(_listCtrl, _sel);
          }
        } else if (k == LogicalKeyboardKey.arrowLeft) {
          setState(() {
            _catsFocus = true;
            _catSel = _cat;
          });
          _scrollTo(_catCtrl, _catSel);
        } else if (k == LogicalKeyboardKey.arrowRight) {
          _openGuide();
        }
        return KeyEventResult.handled;

      case _Mode.guide:
        _guideKey.currentState?.handleKey(k);
        return KeyEventResult.handled;
    }
  }

  void _chooseCategory() {
    final cats = _cats();
    final c = cats[_catSel];
    if (c.id == '__settings__') {
      _openSettings();
      return;
    }
    setState(() {
      _cat = _catSel;
      _catsFocus = false;
      _sel = 0;
      _rebuildList();
    });
    _scrollTo(_listCtrl, 0);
  }

  void _okShortPress() {
    switch (_mode) {
      case _Mode.play:
        _openList();
      case _Mode.list:
        if (_catsFocus) {
          _chooseCategory();
        } else if (_list.isNotEmpty) {
          _play(_list[_sel]);
          setState(() => _mode = _Mode.play);
        }
      case _Mode.guide:
        _guideKey.currentState?.ok();
    }
  }

  void _okLongPress() {
    if (_mode == _Mode.list && !_catsFocus && _list.isNotEmpty) {
      final c = _list[_sel];
      AppState.I.toggleFavorite(c);
      _showToast(AppState.I.isFavorite(c)
          ? '★  ${c.name} added to favourites'
          : '${c.name} removed from favourites');
    } else if (_mode == _Mode.play && _core.channel != null) {
      final c = _core.channel!;
      AppState.I.toggleFavorite(c);
      _showToast(AppState.I.isFavorite(c)
          ? '★  ${c.name} added to favourites'
          : '${c.name} removed from favourites');
    }
  }

  @override
  void dispose() {
    _core.removeListener(_refresh);
    AppState.I.removeListener(_onState);
    Updater.I.removeListener(_refresh);
    _bannerTimer?.cancel();
    _toastTimer?.cancel();
    _clock?.cancel();
    _core.dispose();
    _focus.dispose();
    _listCtrl.dispose();
    _catCtrl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(controller: _core.controller, controls: NoVideoControls),
              if (s.channels.isEmpty) Center(child: _emptyState(s)),
              if (_core.status != null && _mode == _Mode.play) Center(child: _statusCard()),
              if (_mode == _Mode.play)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedOpacity(
                    opacity: _banner ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: _infoBanner(),
                  ),
                ),
              if (_mode == _Mode.list) _listOverlay(),
              if (_mode == _Mode.guide)
                TvGuide(
                  key: _guideKey,
                  channels: _list,
                  initialIndex: _list.indexWhere((x) => x.id == _core.channel?.id),
                  playingId: _core.channel?.id,
                  onPlay: (c) {
                    _play(c);
                    setState(() => _mode = _Mode.play);
                  },
                ),
              if (Updater.I.available != null && !Updater.I.dismissed && _mode == _Mode.list)
                Positioned(right: 32, top: 24, child: _updateChip()),
              if (_toast != null)
                Positioned(
                  top: 32,
                  left: 0,
                  right: 0,
                  child: Center(child: _pill(_toast!)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
            color: const Color(0xE6202026), borderRadius: BorderRadius.circular(24)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
      );

  Widget _emptyState(AppState s) => Column(mainAxisSize: MainAxisSize.min, children: [
        if (s.loadingChannels) ...[
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Loading channels…', style: TextStyle(color: Colors.white70, fontSize: 18)),
        ] else ...[
          Text(s.channelsError ?? 'No channels loaded',
              style: const TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Press OK, then ◀ and choose Settings',
              style: TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ]);

  Widget _statusCard() => Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xE6000000), borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!_core.failed)
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (_core.failed)
            const Text('Could not play this channel',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(_core.status ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
          if (_core.failed) ...[
            const SizedBox(height: 10),
            const Text('▲ ▼ to change channel',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ]),
      );

  ({Programme? cur, Programme? next}) _nowNext(Channel c, int now) {
    final ps = AppState.I.epg.forChannel(c);
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].isLiveAt(now)) {
        return (cur: ps[i], next: i + 1 < ps.length ? ps[i + 1] : null);
      }
      if (ps[i].start > now) return (cur: null, next: ps[i]);
    }
    return (cur: null, next: null);
  }

  Widget _infoBanner() {
    final c = _core.channel;
    if (c == null) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    final nn = _nowNext(c, now);
    final chNum = _list.indexWhere((x) => x.id == c.id) + 1;
    final fav = AppState.I.isFavorite(c);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 32),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xF0000000), Color(0x00000000)],
        ),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        ChannelLogo(c, size: 72),
        const SizedBox(width: 22),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (chNum > 0)
                  Text('$chNum  ',
                      style: const TextStyle(color: Colors.white54, fontSize: 22)),
                Flexible(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                ),
                if (fav) const Text('  ★', style: TextStyle(color: kAccent, fontSize: 20)),
              ]),
              const SizedBox(height: 6),
              if (nn.cur != null) ...[
                Text('${fmtMs(nn.cur!.start)} – ${fmtMs(nn.cur!.stop)}   ${nn.cur!.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 17)),
                const SizedBox(height: 8),
                SizedBox(
                  width: 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: nn.cur!.progressAt(now),
                      minHeight: 4,
                      color: kAccent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ] else
                const Text('No TV guide for this channel',
                    style: TextStyle(color: Colors.white60, fontSize: 16)),
              if (nn.next != null) ...[
                const SizedBox(height: 8),
                Text('Next  ${fmtMs(nn.next!.start)}   ${nn.next!.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontSize: 15)),
              ],
            ],
          ),
        ),
        Text(fmtTime(DateTime.now()),
            style: const TextStyle(color: Colors.white70, fontSize: 20)),
      ]),
    );
  }

  Widget _listOverlay() {
    final cats = _cats();
    final now = DateTime.now().millisecondsSinceEpoch;
    final playingId = _core.channel?.id;
    return Row(children: [
      if (_catsFocus)
        Container(
          width: 260,
          color: const Color(0xF7101013),
          padding: const EdgeInsets.fromLTRB(16, 28, 12, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 0, 14),
              child: Text('Categories',
                  style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: ListView.builder(
                controller: _catCtrl,
                itemExtent: _rowH,
                itemCount: cats.length,
                itemBuilder: (_, i) {
                  final sel = i == _catSel;
                  final active = i == _cat;
                  final c = cats[i];
                  final icon = switch (c.id) {
                    '__fav__' => Icons.star_rounded,
                    '__all__' => Icons.apps_rounded,
                    '__settings__' => Icons.settings_rounded,
                    _ => AppState.I.isFavoriteCategory(c.id) ? Icons.star_outline_rounded : null,
                  };
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: sel ? kAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: sel ? Colors.white : Colors.white60),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: sel || active ? Colors.white : Colors.white70,
                                fontSize: 16,
                                fontWeight: sel || active ? FontWeight.w700 : FontWeight.w500)),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ]),
        ),
      Container(
        width: 470,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xF5101013), Color(0xE6101013)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
            child: Row(children: [
              Expanded(
                child: Text(cats[_cat].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              Text('${_list.isEmpty ? 0 : _sel + 1} / ${_list.length}',
                  style: const TextStyle(color: Colors.white38, fontSize: 14)),
            ]),
          ),
          Expanded(
            child: _list.isEmpty
                ? Center(
                    child: Text(
                        cats[_cat].id == '__fav__'
                            ? 'No favourites yet.\nHold OK on a channel to add it.'
                            : 'No channels',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white54, fontSize: 16)),
                  )
                : ListView.builder(
                    controller: _listCtrl,
                    itemExtent: _rowH,
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final c = _list[i];
                      final sel = i == _sel && !_catsFocus;
                      final cur = currentProgramme(c, now);
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: sel ? kAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(children: [
                          SizedBox(
                            width: 38,
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: sel ? Colors.white : Colors.white38, fontSize: 14)),
                          ),
                          ChannelLogo(c, size: 38),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600)),
                                if (cur != null) ...[
                                  const SizedBox(height: 2),
                                  Text(cur.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: sel ? Colors.white : Colors.white54,
                                          fontSize: 13)),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(2),
                                    child: LinearProgressIndicator(
                                      value: cur.progressAt(now),
                                      minHeight: 2.5,
                                      color: sel ? Colors.white : kAccent,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (AppState.I.isFavorite(c))
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.star_rounded,
                                  size: 18, color: sel ? Colors.white : kAccent),
                            ),
                          if (c.id == playingId)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.volume_up_rounded,
                                  size: 18, color: sel ? Colors.white : kAccent),
                            ),
                        ]),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Text('OK watch   hold OK ★   ◀ categories   ▶ guide',
                style: TextStyle(color: Colors.white38, fontSize: 12.5)),
          ),
        ]),
      ),
    ]);
  }

  Widget _updateChip() {
    final u = Updater.I;
    final info = u.available!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: const Color(0xE6202026), borderRadius: BorderRadius.circular(12)),
      child: Text(
        u.installing
            ? 'Downloading update… ${((u.progress ?? 0) * 100).round()}%'
            : 'Update ${info.version} available – Settings › Check for updates',
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
    );
  }
}
