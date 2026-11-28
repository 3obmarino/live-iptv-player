import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../app_state.dart';
import '../models.dart';
import '../player_core.dart';
import '../ui/common.dart';
import '../ui/menu_screen.dart';
import '../updater.dart';
import 'tv_guide.dart';
import '../l10n.dart';
import '../voice.dart';
import '../reminders.dart';

enum _Mode { play, info, guide, sidebar }

class _Cat {
  const _Cat(this.id, this.name);
  final String id; // '__fav__', '__all__' or a category id
  final String name;
}

/// Google TV home (TiviMate-style), always built around the live video:
///
/// Watching   ▲▼/CH± zap · OK info panel · BACK guide
/// Info       ◀▶ tiles · OK open tile · ▲▼ zap · BACK close
/// Guide      ▲▼ channel · ◀▶ programme · OK preview / 2nd OK fullscreen ·
///            hold OK favourite · ◀ at now or BACK sidebar
/// Sidebar    ▲▼ category · OK/▶ open · ◀ settings · BACK watch
/// HOME leaves the app.
class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  final _core = PlayerCore();
  final _focus = FocusNode();
  final _catCtrl = ScrollController();
  final _guideKey = GlobalKey<TvGuideState>();

  _Mode _mode = _Mode.play;
  // index into _cats(): 0 = Search, 1 = Favourites, 2 = All, then categories
  static const _allIdx = 2;
  int _cat = _allIdx;
  int _catSel = _allIdx;
  String _searchQuery = '';
  bool _railFocus = false;
  int _tile = 0;
  List<Channel> _list = const [];
  int _guideStart = 0;
  String? _profileId;
  bool _openFirstCategory = false; // after switching profile

  Timer? _infoTimer;
  String? _toast;
  Timer? _toastTimer;
  Timer? _clock;
  bool _okDown = false;
  bool _okLong = false;
  DateTime? _lastBackCall;
  final List<StreamSubscription<dynamic>> _subs = [];
  final _tileCtrl = ScrollController();
  bool _tilesOn = false;

  static const double _sideW = 300;

  @override
  void initState() {
    super.initState();
    _core.addListener(_refresh);
    AppState.I.addListener(_onState);
    AppState.I.playRequest.addListener(_onPlayRequest);
    Reminders.I.addListener(_refresh);
    Updater.I.addListener(_refresh);
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    final st = _core.player.stream;
    _subs.add(st.videoParams.listen((_) => _refresh()));
    _subs.add(st.audioParams.listen((_) => _refresh()));
    _subs.add(st.track.listen((_) => _refresh()));
    WidgetsBinding.instance.addPostFrameCallback((_) => _onState());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onState() {
    if (!mounted) return;
    final s = AppState.I;
    if (_profileId != s.activeId) {
      // Switched profile (not the first start): open its first category.
      _openFirstCategory = _profileId != null;
      _profileId = s.activeId;
      _cat = _allIdx;
      _catSel = _allIdx;
      _searchQuery = '';
      _core.channel = null;
    }
    if (_openFirstCategory) {
      final first = s.firstCategoryId();
      if (first != null) {
        final i = _cats().indexWhere((c) => c.id == first);
        if (i >= 0) {
          _cat = i;
          _catSel = i;
        }
        _openFirstCategory = false;
      }
    }
    _rebuildList();
    if (_core.channel == null && s.channels.isNotEmpty) {
      final rec = s.recentChannels;
      _play(rec.isNotEmpty ? rec.first : s.channels.first, showInfo: true);
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
      ..sort((a, b) =>
          (favCats.contains(a.id) ? 0 : 1).compareTo(favCats.contains(b.id) ? 0 : 1));
    return [
      _Cat('__search__',
          _searchQuery.isEmpty ? tr('Search (speak or type)') : tr('Search: {q}', {'q': _searchQuery})),
      _Cat('__fav__', tr('Favourites')),
      _Cat('__all__', tr('All channels')),
      for (final c in cats) _Cat(c.id, c.name),
    ];
  }

  void _rebuildList() {
    final s = AppState.I;
    final cats = _cats();
    if (_cat >= cats.length) _cat = _allIdx;
    final id = cats[_cat].id;
    final fav = s.active?.favorites ?? const <String>{};
    _list = switch (id) {
      '__search__' => _searchQuery.isEmpty
          ? const <Channel>[]
          : s.channels.where((c) => matchesSearch(c.name, _searchQuery)).toList(),
      '__fav__' => s.channels.where((c) => fav.contains(c.id)).toList(),
      '__all__' => s.channels,
      _ => s.channels.where((c) => c.categoryId == id).toList(),
    };
  }

  int get _playingIndex => _list.indexWhere((x) => x.id == _core.channel?.id);

  // -------------------------------------------------------------- actions

  void _play(Channel c, {bool showInfo = true}) {
    _core.play(c);
    if (showInfo) _showInfo(tiles: false);
  }

  void _zap(int d) {
    if (_list.isEmpty) return;
    var i = _playingIndex;
    if (i < 0) i = 0;
    i = (i + d) % _list.length;
    if (i < 0) i += _list.length;
    _play(_list[i]);
  }

  /// [tiles]: true = OK pressed: show the TV guide/recent strip with
  /// focus on its first tile; false = zap: channel info only.
  void _showInfo({bool tiles = true, bool keepTile = false}) {
    _infoTimer?.cancel();
    setState(() {
      _mode = _Mode.info;
      _tilesOn = tiles;
      if (tiles && !keepTile) _tile = 0;
    });
    if (tiles && !keepTile) _scrollTiles();
    _infoTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && _mode == _Mode.info) setState(() => _mode = _Mode.play);
    });
  }

  void _scrollTiles() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_tileCtrl.hasClients) return;
      const w = 190.0 + 14.0; // tile + gap
      final view = _tileCtrl.position.viewportDimension;
      final target = (_tile * w - view / 2 + w / 2)
          .clamp(0.0, _tileCtrl.position.maxScrollExtent)
          .toDouble();
      _tileCtrl.animateTo(target,
          duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
    });
  }

  void _openGuide() {
    _infoTimer?.cancel();
    _rebuildList();
    setState(() {
      _guideStart = _playingIndex < 0 ? 0 : _playingIndex;
      _mode = _Mode.guide;
    });
  }

  void _openSidebar() {
    setState(() {
      _catSel = _cat;
      _railFocus = false;
      _mode = _Mode.sidebar;
    });
    _scrollCats();
  }

  void _scrollCats() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_catCtrl.hasClients) return;
      const h = 56.0;
      final view = _catCtrl.position.viewportDimension;
      _catCtrl.jumpTo((_catSel * h - view / 2 + h / 2)
          .clamp(0.0, _catCtrl.position.maxScrollExtent)
          .toDouble());
    });
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Settings'))),
        body: const MenuScreen(),
      ),
    ));
    if (mounted) {
      _onState();
      _focus.requestFocus();
    }
  }

  void _back() {
    final t = DateTime.now();
    if (_lastBackCall != null && t.difference(_lastBackCall!) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastBackCall = t;
    switch (_mode) {
      case _Mode.play:
        _openGuide();
      case _Mode.info:
        setState(() => _mode = _Mode.play);
      case _Mode.guide:
        _openSidebar();
      case _Mode.sidebar:
        setState(() => _mode = _Mode.play);
    }
  }

  void _onPlayRequest() {
    final c = AppState.I.playRequest.value;
    if (c == null || !mounted) return;
    AppState.I.playRequest.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    if (_list.indexWhere((x) => x.id == c.id) < 0) {
      _cat = _allIdx;
      _rebuildList();
    }
    setState(() => _mode = _Mode.play);
    _play(c);
  }

  void _showToast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toast = msg);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  void _toggleFav(Channel c) {
    AppState.I.toggleFavorite(c);
    _showToast(AppState.I.isFavorite(c)
        ? '★  ${c.name} added to favourites'
        : '${c.name} removed from favourites');
  }

  /// FHD / 25 FPS / STEREO from mpv's own status events. (Reading mpv
  /// properties directly blocks the UI thread while a stream connects, which
  /// froze the app when zapping.)
  List<String> _badgesNow() {
    final st = _core.player.state;
    final h = st.videoParams.h ?? 0;
    final fps = st.track.video.fps ?? 0;
    final ch = st.audioParams.channelCount ?? 0;
    return <String>[
      if (h >= 2000) 'UHD' else if (h >= 1000) 'FHD' else if (h >= 700) 'HD' else if (h > 0) 'SD',
      if (fps > 0) '${fps.round()} FPS',
      if (ch == 1) 'MONO' else if (ch == 2) 'STEREO' else if (ch == 6) '5.1' else if (ch == 8) '7.1' else if (ch > 2) '$ch CH',
    ];
  }

  // ------------------------------------------------------------ remote keys

  bool _isOk(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.gameButtonA;

  bool _isUp(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp;
  bool _isDown(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    final k = e.logicalKey;

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

    // The remote's search key (where it reaches apps)
    if (k == LogicalKeyboardKey.browserSearch || k == LogicalKeyboardKey.find) {
      if (e is KeyDownEvent) _search();
      return KeyEventResult.handled;
    }
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
    if (k == LogicalKeyboardKey.info || k == LogicalKeyboardKey.contextMenu) {
      _showInfo();
      return KeyEventResult.handled;
    }

    switch (_mode) {
      case _Mode.play:
        if (_isUp(k)) {
          _zap(-1);
        } else if (_isDown(k)) {
          _zap(1);
        } else if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
          _showInfo();
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;

      case _Mode.info:
        final tiles = _tiles();
        if (!_tilesOn &&
            (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight)) {
          _showInfo(); // info without strip: ◀▶ bring the strip up
        } else if (k == LogicalKeyboardKey.arrowLeft) {
          setState(() => _tile = (_tile - 1).clamp(0, tiles.length - 1).toInt());
          _showInfo(keepTile: true);
          _scrollTiles();
        } else if (k == LogicalKeyboardKey.arrowRight) {
          setState(() => _tile = (_tile + 1).clamp(0, tiles.length - 1).toInt());
          _showInfo(keepTile: true);
          _scrollTiles();
        } else if (_isUp(k)) {
          _zap(-1);
        } else if (_isDown(k)) {
          _zap(1);
        }
        return KeyEventResult.handled;

      case _Mode.guide:
        final g = _guideKey.currentState;
        if (k == LogicalKeyboardKey.arrowLeft && (g == null || g.atLeftEdge)) {
          _openSidebar();
        } else {
          g?.handleKey(k);
        }
        return KeyEventResult.handled;

      case _Mode.sidebar:
        final cats = _cats();
        if (_railFocus) {
          if (k == LogicalKeyboardKey.arrowRight) setState(() => _railFocus = false);
          return KeyEventResult.handled;
        }
        if (_isUp(k)) {
          setState(() => _catSel = (_catSel - 1 + cats.length) % cats.length);
          _scrollCats();
        } else if (_isDown(k)) {
          setState(() => _catSel = (_catSel + 1) % cats.length);
          _scrollCats();
        } else if (k == LogicalKeyboardKey.arrowLeft) {
          setState(() => _railFocus = true);
        } else if (k == LogicalKeyboardKey.arrowRight) {
          _chooseCategory();
        }
        return KeyEventResult.handled;
    }
  }

  /// Search: speak (Google voice) or, without a recognizer, type in the
  /// Android input dialog. Results show as a list in the guide.
  Future<void> _search() async {
    String? text;
    if (await Voice.available()) {
      text = await Voice.listen();
    } else {
      text = await Voice.type(tr('Search channels by name'), _searchQuery);
    }
    text = text?.trim();
    if (!mounted || text == null || text.isEmpty) return;
    setState(() {
      _searchQuery = text!;
      _cat = 0;
      _catSel = 0;
      _rebuildList();
    });
    _openGuide();
  }

  void _chooseCategory() {
    if (_catSel == 0) {
      _search();
      return;
    }
    setState(() {
      _cat = _catSel;
      _rebuildList();
    });
    _openGuide();
  }

  void _okShortPress() {
    switch (_mode) {
      case _Mode.play:
        _showInfo();
      case _Mode.info:
        final tiles = _tiles();
        if (!_tilesOn) {
          _showInfo();
        } else if (_tile == 0) {
          _openGuide();
        } else if (_tile < tiles.length) {
          final c = tiles[_tile]!;
          if (_list.indexWhere((x) => x.id == c.id) < 0) {
            _cat = _allIdx; // recent channel from another category: show All
            _rebuildList();
          }
          _play(c, showInfo: false);
          _showInfo(keepTile: true);
        }
      case _Mode.guide:
        final c = _guideKey.currentState?.selected;
        if (c == null) return;
        // OK on a programme that hasn't started: remind me (or cancel).
        final p = _guideKey.currentState?.selectedProgramme;
        if (p != null && p.start > DateTime.now().millisecondsSinceEpoch) {
          Reminders.I.toggle(c, p).then((added) {
            if (mounted) {
              _showToast(added
                  ? tr('Reminder set: {t} at {h}', {'t': p.title, 'h': fmtMs(p.start)})
                  : tr('Reminder removed'));
            }
          });
          return;
        }
        if (c.id == _core.channel?.id) {
          setState(() => _mode = _Mode.play); // 2nd OK: fullscreen
          _showInfo(tiles: false);
        } else {
          _play(c, showInfo: false); // 1st OK: play in the preview
        }
      case _Mode.sidebar:
        if (_railFocus) {
          _openSettings();
        } else {
          _chooseCategory();
        }
    }
  }

  void _okLongPress() {
    if (_mode == _Mode.guide) {
      final c = _guideKey.currentState?.selected;
      if (c != null) _toggleFav(c);
    } else if ((_mode == _Mode.play || _mode == _Mode.info) && _core.channel != null) {
      _toggleFav(_core.channel!);
    }
  }

  /// Info-panel tiles: index 0 = TV guide, then recent channels.
  List<Channel?> _tiles() {
    final cur = _core.channel?.id;
    return [
      null,
      ...AppState.I.recentChannels.where((c) => c.id != cur).take(10),
    ];
  }

  @override
  void dispose() {
    _core.removeListener(_refresh);
    AppState.I.removeListener(_onState);
    AppState.I.playRequest.removeListener(_onPlayRequest);
    Reminders.I.removeListener(_refresh);
    Updater.I.removeListener(_refresh);
    _infoTimer?.cancel();
    _toastTimer?.cancel();
    _clock?.cancel();
    for (final x in _subs) {
      x.cancel();
    }
    _tileCtrl.dispose();
    _core.dispose();
    _focus.dispose();
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
          child: LayoutBuilder(builder: (context, box) {
            final w = box.maxWidth, h = box.maxHeight;
            final guideOn = _mode == _Mode.guide || _mode == _Mode.sidebar;
            final left = _mode == _Mode.sidebar ? _sideW : 0.0;
            final pw = (w - left) * 0.34;
            final preview = Rect.fromLTWH(24, 20, pw, pw * 9 / 16);
            final videoRect =
                guideOn ? preview.shift(Offset(left, 0)) : Rect.fromLTWH(0, 0, w, h);
            final cats = _cats();
            final catName = cats[_cat.clamp(0, cats.length - 1)].name;

            return Stack(children: [
              if (guideOn)
                Positioned(
                  left: left,
                  top: 0,
                  right: 0,
                  bottom: 0,
                  child: TvGuide(
                    key: _guideKey,
                    channels: _list,
                    initialIndex: _guideStart,
                    playingId: _core.channel?.id,
                    categoryName: catName,
                    preview: preview,
                  ),
                ),
              // The video surface always stays full-screen; the guide preview
              // is the same surface scaled down. Resizing the real surface
              // makes mpv reconfigure its output and blocked the UI thread.
              Positioned.fill(
                child: TweenAnimationBuilder<Rect?>(
                  tween: RectTween(end: videoRect),
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  builder: (context, r, child) {
                    final rr = r ?? videoRect;
                    final sc = (rr.width / w).clamp(0.05, 1.0).toDouble();
                    return Transform(
                      transform: Matrix4.translationValues(rr.left, rr.top, 0)
                        ..multiply(Matrix4.diagonal3Values(sc, sc, 1)),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(sc < 0.99 ? 10 / sc : 0),
                        child: child,
                      ),
                    );
                  },
                  child: ColoredBox(
                    color: Colors.black,
                    child: Video(controller: _core.controller, controls: NoVideoControls),
                  ),
                ),
              ),
              if (_mode == _Mode.sidebar) _sidebar(cats),
              if (s.channels.isEmpty) Center(child: _emptyState(s)),
              if ((_core.failed || _core.loading) && !guideOn) Center(child: _statusCard()),
              if (_mode == _Mode.info) _infoPanel(catName),
              if (_toast != null)
                Positioned(top: 32, left: 0, right: 0, child: Center(child: _pill(_toast!))),
            ]);
          }),
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
          Text(tr('Loading channels…'), style: TextStyle(color: Colors.white70, fontSize: 18)),
        ] else ...[
          Text(s.channelsError ?? tr('No channels loaded'),
              style: const TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 8),
          Text(tr('Press BACK twice, then ◀ and OK for Settings'),
              style: TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ]);

  Widget _statusCard() => !_core.failed
      ? const SizedBox(
          width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 3))
      : Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
            color: const Color(0xE6000000), borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (!_core.failed)
            const SizedBox(
                width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (_core.failed)
            Text(tr('Could not play this channel'),
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(_core.status ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
          ),
        ]),
      );

  // -------------------------------------------------------------- sidebar

  Widget _sidebar(List<_Cat> cats) {
    final upd = Updater.I.available != null;
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: _sideW,
      child: Container(
        color: const Color(0xFF16181D),
        child: Row(children: [
          Container(
            width: 72,
            color: const Color(0xFF1C1F25),
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Column(children: [
              const Icon(Icons.live_tv_rounded, color: kAccent, size: 34),
              const Spacer(),
              if (upd)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Icon(Icons.circle, color: kAccent, size: 10),
                ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: _railFocus ? kAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.settings_rounded,
                    color: _railFocus ? kOnAccent : Colors.white70, size: 28),
              ),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 40, 12, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_railFocus)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 0, 12),
                    child: Text(upd ? tr('Settings  ·  update available') : tr('Settings'),
                        style: const TextStyle(color: kAccent, fontSize: 15)),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _catCtrl,
                    itemExtent: 56,
                    itemCount: cats.length,
                    itemBuilder: (_, i) {
                      final sel = i == _catSel && !_railFocus;
                      final active = i == _cat;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: sel ? kAccent : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(cats[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: sel
                                    ? kOnAccent
                                    : active
                                        ? kAccent
                                        : Colors.white,
                                fontSize: 18,
                                fontWeight:
                                    sel || active ? FontWeight.w700 : FontWeight.w500)),
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ----------------------------------------------------------- info panel

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

  Widget _badge(String t) => Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: kAccent.withOpacity(0.18),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: kAccent.withOpacity(0.55)),
        ),
        child: Text(t,
            style: const TextStyle(color: kAccent, fontSize: 12.5, fontWeight: FontWeight.w700)),
      );

  Widget _infoPanel(String catName) {
    final c = _core.channel;
    if (c == null) return const SizedBox.shrink();
    final now = DateTime.now().millisecondsSinceEpoch;
    final nn = _nowNext(c, now);
    final chNum = _playingIndex + 1;
    final tiles = _tiles();

    return Stack(children: [
      Positioned(
        left: 0,
        right: 0,
        top: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB0000000), Color(0x00000000)],
            ),
          ),
          child: Row(children: [
            Text(catName, style: const TextStyle(color: Colors.white, fontSize: 20)),
            const Spacer(),
            Text(TvGuideState.dateTimeLabel(DateTime.now()),
                style: const TextStyle(color: Colors.white, fontSize: 20)),
          ]),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(40, 80, 40, 24),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Color(0xF0000000), Color(0xC0000000), Color(0x00000000)],
              stops: [0, 0.6, 1],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                ChannelLogo(c, size: 110),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nn.cur?.title ?? c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      // fixed height: badges appearing must not move the text
                      SizedBox(
                        height: 30,
                        child: Row(children: [
                        if (nn.cur != null) ...[
                          Text('${fmtMs(nn.cur!.start)} – ${fmtMs(nn.cur!.stop)}',
                              style: const TextStyle(color: Colors.white70, fontSize: 17)),
                          const SizedBox(width: 14),
                          SizedBox(
                            width: 70,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: nn.cur!.progressAt(now),
                                minHeight: 3,
                                color: kAccent,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text('${((nn.cur!.stop - now) / 60000).ceil()} min',
                              style: const TextStyle(color: Colors.white70, fontSize: 17)),
                          const SizedBox(width: 28),
                        ],
                        Flexible(
                          child: Text('${chNum > 0 ? '$chNum  ' : ''}${c.name}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                        ),
                        if (AppState.I.isFavorite(c))
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.star_rounded, color: kAccent, size: 20),
                          ),
                        for (final b in _badgesNow()) _badge(b),
                      ]),
                      ),
                      if (nn.next != null) ...[
                        const SizedBox(height: 8),
                        Text(
                            '${fmtMs(nn.next!.start)} – ${fmtMs(nn.next!.stop)}   ${nn.next!.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 17)),
                      ],
                    ],
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              SizedBox(
                height: 10,
                child: LayoutBuilder(builder: (context, b) {
                  final v = nn.cur?.progressAt(now) ?? 0;
                  return Stack(alignment: Alignment.centerLeft, children: [
                    Container(height: 3, color: Colors.white24),
                    Container(height: 3, width: b.maxWidth * v, color: kAccent),
                    if (nn.cur != null)
                      Positioned(
                        left: (b.maxWidth * v - 5).clamp(0.0, b.maxWidth - 10).toDouble(),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration:
                              const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                        ),
                      ),
                  ]);
                }),
              ),
              if (_tilesOn) ...[
              const SizedBox(height: 18),
              SizedBox(
                height: 112,
                child: ListView.separated(
                  controller: _tileCtrl,
                  scrollDirection: Axis.horizontal,
                  itemCount: tiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 14),
                  itemBuilder: (_, i) => _tileWidget(tiles[i], i == _tile, now),
                ),
              ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _tileWidget(Channel? c, bool sel, int now) {
    final cur = c == null ? null : currentProgramme(c, now);
    return Container(
      width: 190,
      decoration: BoxDecoration(
        color: sel ? const Color(0xFF3A3E48) : const Color(0xCC22252C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: sel ? kAccent : Colors.transparent, width: 3),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: c == null
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.view_list_rounded, color: Colors.white, size: 40),
              SizedBox(height: 8),
              Text(tr('TV guide'), style: TextStyle(color: Colors.white, fontSize: 18)),
            ])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Center(child: ChannelLogo(c, size: 52))),
              Text(cur?.title ?? c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kAccent, fontSize: 15)),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: cur?.progressAt(now) ?? 0,
                  minHeight: 2.5,
                  color: kAccent,
                  backgroundColor: Colors.white12,
                ),
              ),
            ]),
    );
  }
}
