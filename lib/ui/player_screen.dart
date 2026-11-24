import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../player_core.dart' show videoConfig, tuneForLive;
import '../models.dart' show Channel;
import 'common.dart';

/// Full-window live player (libmpv via media_kit) with our own large
/// control overlay. Same overlay on Windows (mouse) and Android (touch).
///
/// Keys: ↑/↓ or PgUp/PgDn = channel, ←/→ = volume, Space = pause,
/// F = fullscreen, M = mute, L = channel list, I = show controls, Esc = back.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.playlist, required this.index});
  final List<Channel> playlist;
  final int index;
  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  late int _index;
  final List<StreamSubscription<dynamic>> _subs = [];
  final _focus = FocusNode();

  bool _fullscreen = false;
  bool _controls = true;
  bool _overBars = false;
  Timer? _hideTimer;
  Timer? _clock;
  bool _showList = false;
  ScrollController? _listCtrl;

  String? _status;
  bool _failed = false;
  int _retries = 0;
  Timer? _retryTimer;

  bool _playing = false;
  double _volume = 100;
  double _volumeBeforeMute = 100;
  List<AudioTrack> _audioTracks = const [];
  AudioTrack? _audioTrack;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Channel get _channel => widget.playlist[_index];

  @override
  void initState() {
    super.initState();
    _index = (widget.index < 0 || widget.index >= widget.playlist.length) ? 0 : widget.index;
    _volume = AppState.I.settings.volume;
    _player = Player();
    _controller = VideoController(_player, configuration: videoConfig());
    _subs.add(_player.stream.error.listen(_onError));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _scheduleRetry('The stream ended');
    }));
    _subs.add(_player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() {
        _playing = playing;
        if (playing) {
          _status = null;
          _failed = false;
        }
      });
      if (playing) _retries = 0;
    }));
    _subs.add(_player.stream.volume.listen((v) {
      if (mounted) setState(() => _volume = v);
    }));
    _subs.add(_player.stream.tracks.listen((t) {
      if (!mounted) return;
      setState(() {
        _audioTracks =
            t.audio.where((a) => a.id != 'auto' && a.id != 'no').toList();
      });
    }));
    _subs.add(_player.stream.track.listen((t) {
      if (mounted) setState(() => _audioTrack = t.audio);
    }));
    if (!_desktop) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    // Keeps the programme progress bar moving.
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && _controls) setState(() {});
    });
    _configure().then((_) {
      if (mounted) _open();
    });
  }

  Future<void> _configure() async {
    await tuneForLive(_player);
    await _player.setVolume(_volume);
  }

  void _open() {
    final c = _channel;
    AppState.I.addRecent(c);
    _retryTimer?.cancel();
    setState(() {
      _status = null;
      _failed = false;
      _audioTracks = const [];
    });
    _showControls();
    _player.open(Media(AppState.I.streamUrlFor(c)));
  }

  void _onError(String e) {
    if (!mounted) return;
    // mpv reports some harmless errors while playing fine; ignore those.
    if (_player.state.playing) return;
    _scheduleRetry(e);
  }

  void _scheduleRetry(String reason) {
    if (!mounted) return;
    if (_retries >= 5) {
      setState(() {
        _failed = true;
        _status = reason;
      });
      return;
    }
    _retries++;
    setState(() => _status = 'Reconnecting… ($_retries/5)');
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 2 * _retries), () {
      if (mounted) _player.open(Media(AppState.I.streamUrlFor(_channel)));
    });
  }

  // ---------------------------------------------------------------- actions

  void _zap(int delta) {
    if (widget.playlist.length < 2) return;
    _playIndex((_index + delta) % widget.playlist.length);
  }

  void _playIndex(int i) {
    _retries = 0;
    _index = i;
    _open();
  }

  void _showControls() {
    _hideTimer?.cancel();
    if (!_controls && mounted) setState(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 4), _maybeHide);
  }

  void _maybeHide() {
    if (!mounted) return;
    if (_overBars || !_playing) {
      _hideTimer = Timer(const Duration(seconds: 2), _maybeHide);
      return;
    }
    setState(() => _controls = false);
  }

  void _tapVideo() {
    if (_controls) {
      _hideTimer?.cancel();
      setState(() => _controls = false);
    } else {
      _showControls();
    }
  }

  Future<void> _toggleFullscreen() async {
    if (!_desktop) return;
    _fullscreen = !_fullscreen;
    await windowManager.setFullScreen(_fullscreen);
    if (mounted) setState(() {});
  }

  Future<void> _exitOrBack() async {
    if (_fullscreen) {
      await _toggleFullscreen();
    } else if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  void _setVolume(double v, {bool persist = false}) {
    final nv = v.clamp(0.0, 100.0).toDouble();
    setState(() => _volume = nv);
    _player.setVolume(nv);
    if (persist && nv > 0) {
      AppState.I.settings.volume = nv;
      AppState.I.save();
    }
  }

  void _volumeStep(double d) {
    _setVolume(_volume + d, persist: true);
    _showControls();
  }

  void _toggleMute() {
    if (_volume > 0) {
      _volumeBeforeMute = _volume;
      _setVolume(0);
    } else {
      _setVolume(_volumeBeforeMute <= 0 ? 50 : _volumeBeforeMute);
    }
    _showControls();
  }

  void _toggleList() {
    setState(() {
      _showList = !_showList;
      _listCtrl?.dispose();
      _listCtrl = _showList
          ? ScrollController(
              initialScrollOffset:
                  ((_index - 4) * 60.0).clamp(0.0, double.infinity).toDouble())
          : null;
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _retryTimer?.cancel();
    _hideTimer?.cancel();
    _clock?.cancel();
    _listCtrl?.dispose();
    if (_fullscreen && _desktop) windowManager.setFullScreen(false);
    if (!_desktop) {
      SystemChrome.setPreferredOrientations(const []);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _player.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () {
        _player.playOrPause();
        _showControls();
      },
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.escape): _exitOrBack,
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _zap(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _zap(1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _zap(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _zap(1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _volumeStep(10),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _volumeStep(-10),
      const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      const SingleActivator(LogicalKeyboardKey.keyL): _toggleList,
      const SingleActivator(LogicalKeyboardKey.keyI): _showControls,
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: CallbackShortcuts(
        bindings: shortcuts,
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Row(
            children: [
              Expanded(
                child: MouseRegion(
                  cursor: _controls ? SystemMouseCursors.basic : SystemMouseCursors.none,
                  onHover: (_) => _showControls(),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _tapVideo,
                        onDoubleTap: _desktop ? _toggleFullscreen : null,
                        onHorizontalDragEnd: (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v.abs() > 300) _zap(v < 0 ? 1 : -1);
                        },
                        child: Video(controller: _controller, controls: NoVideoControls),
                      ),
                      IgnorePointer(
                        ignoring: !_controls,
                        child: AnimatedOpacity(
                          opacity: _controls ? 1 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: _overlay(context),
                        ),
                      ),
                      if (_status != null) Center(child: _statusCard()),
                    ],
                  ),
                ),
              ),
              if (_showList) SizedBox(width: 320, child: _channelList()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bars({required Widget child}) => MouseRegion(
        onEnter: (_) => _overBars = true,
        onExit: (_) => _overBars = false,
        child: child,
      );

  Widget _overlay(BuildContext context) {
    final fav = AppState.I.isFavorite(_channel);
    final now = DateTime.now().millisecondsSinceEpoch;
    final cur = currentProgramme(_channel, now);
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrims so white controls stay readable on bright video.
        const Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: SizedBox(
              height: 120,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: IgnorePointer(
            child: SizedBox(
              height: 240,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ---- top bar
        Align(
          alignment: Alignment.topCenter,
          child: _bars(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                _iconBtn(Icons.close_rounded, 'Back (Esc)', _exitOrBack, size: 28),
                const Spacer(),
                if (_desktop)
                  _iconBtn(
                      _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      'Fullscreen (F)',
                      _toggleFullscreen),
                _iconBtn(
                  fav ? Icons.star_rounded : Icons.star_outline_rounded,
                  fav ? 'Remove from favourites' : 'Add to favourites',
                  () => setState(() => AppState.I.toggleFavorite(_channel)),
                  color: fav ? kAccent : Colors.white,
                ),
                _iconBtn(Icons.format_list_bulleted_rounded, 'Channel list (L)', _toggleList),
              ]),
            ),
          ),
        ),

        // ---- centre: previous / play-pause / next
        Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _iconBtn(Icons.skip_previous_rounded, 'Previous channel (↑)', () => _zap(-1),
                size: 40),
            const SizedBox(width: 36),
            Tooltip(
              message: _playing ? 'Pause (Space)' : 'Play (Space)',
              child: InkResponse(
                onTap: () {
                  _player.playOrPause();
                  _showControls();
                },
                radius: 48,
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withOpacity(0.25),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 52, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 36),
            _iconBtn(Icons.skip_next_rounded, 'Next channel (↓)', () => _zap(1), size: 40),
          ]),
        ),

        // ---- bottom: channel + programme, progress, volume
        Align(
          alignment: Alignment.bottomCenter,
          child: _bars(
            child: Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, compact ? 12 : 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ChannelLogo(_channel, size: compact ? 44 : 60),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_channel.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: compact ? 18 : 24,
                                    fontWeight: FontWeight.w700)),
                            if (cur != null)
                              Text(cur.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white70, fontSize: 15)),
                          ],
                        ),
                      ),
                      if (cur != null)
                        Text('${fmtMs(cur.start)} / ${fmtMs(cur.stop)}',
                            style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: cur?.progressAt(now) ?? 0,
                      minHeight: 4,
                      color: kAccent,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    _pill(Row(mainAxisSize: MainAxisSize.min, children: [
                      _iconBtn(
                        _volume <= 0
                            ? Icons.volume_off_rounded
                            : _volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        'Mute (M)',
                        _toggleMute,
                        size: 24,
                      ),
                      SizedBox(
                        width: compact ? 120 : 170,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white24,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                          ),
                          child: Slider(
                            value: _volume.clamp(0.0, 100.0).toDouble(),
                            max: 100,
                            onChanged: (v) {
                              _setVolume(v);
                              _showControls();
                            },
                            onChangeEnd: (v) => _setVolume(v, persist: true),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 34,
                        child: Text('${_volume.round()}',
                            style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    ])),
                    if (_audioTracks.length > 1) ...[
                      const SizedBox(width: 12),
                      _audioButton(),
                    ],
                    const Spacer(),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: child,
      );

  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap,
      {double size = 26, Color color = Colors.white}) {
    return IconButton(
      tooltip: tip,
      onPressed: () {
        onTap();
        _showControls();
      },
      iconSize: size,
      color: color,
      icon: Icon(icon),
    );
  }

  Widget _audioButton() {
    String label(AudioTrack a, int i) {
      final parts = [a.title, a.language].whereType<String>().where((x) => x.isNotEmpty);
      return parts.isEmpty ? 'Audio ${i + 1}' : parts.join(' · ');
    }

    return PopupMenuButton<int>(
      tooltip: 'Audio track',
      onOpened: () => _overBars = true,
      onSelected: (i) {
        _player.setAudioTrack(_audioTracks[i]);
        _showControls();
      },
      itemBuilder: (_) => [
        for (var i = 0; i < _audioTracks.length; i++)
          CheckedPopupMenuItem(
            value: i,
            checked: _audioTrack?.id == _audioTracks[i].id,
            child: Text(label(_audioTracks[i], i)),
          ),
      ],
      child: _pill(const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.audiotrack_rounded, color: Colors.white, size: 22),
          SizedBox(width: 6),
          Text('Audio', style: TextStyle(color: Colors.white, fontSize: 14)),
        ]),
      )),
    );
  }

  Widget _statusCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(14)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_failed)
          const SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        if (_failed)
          const Text('Could not play this channel',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Text(_status ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        if (_failed) ...[
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () {
              _retries = 0;
              _open();
            },
            child: const Text('Try again'),
          ),
        ],
      ]),
    );
  }

  Widget _channelList() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Material(
      color: const Color(0xFF141417),
      child: ListView.builder(
        controller: _listCtrl,
        itemExtent: 60,
        itemCount: widget.playlist.length,
        itemBuilder: (_, i) {
          final c = widget.playlist[i];
          final sel = i == _index;
          return ListTile(
            selected: sel,
            selectedTileColor: kAccent.withOpacity(0.22),
            leading: ChannelLogo(c, size: 32),
            title: Text(c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
            subtitle: Text(currentProgramme(c, now)?.title ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            onTap: () {
              _playIndex(i);
              _focus.requestFocus();
            },
          );
        },
      ),
    );
  }
}

