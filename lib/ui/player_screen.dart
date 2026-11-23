import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

/// Full-window live player (libmpv via media_kit).
///
/// Keys: ↑/↓ or PgUp/PgDn = channel, ←/→ = volume, Space = pause,
/// F = fullscreen, M = mute, L = channel list, I = info, Esc = back.
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
  bool _showInfo = true;
  Timer? _infoTimer;
  bool _showList = false;
  ScrollController? _listCtrl;
  String? _status;
  bool _failed = false;
  int _retries = 0;
  Timer? _retryTimer;
  double _volumeBeforeMute = 100;

  static bool get _desktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Channel get _channel => widget.playlist[_index];

  @override
  void initState() {
    super.initState();
    _index = (widget.index < 0 || widget.index >= widget.playlist.length) ? 0 : widget.index;
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: AppState.I.settings.hwdec),
    );
    _subs.add(_player.stream.error.listen(_onError));
    _subs.add(_player.stream.completed.listen((done) {
      if (done) _scheduleRetry('The stream ended');
    }));
    _subs.add(_player.stream.playing.listen((playing) {
      if (playing && mounted && (_status != null || _failed)) {
        setState(() {
          _status = null;
          _failed = false;
        });
      }
      if (playing) _retries = 0;
    }));
    if (!_desktop) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _configure().then((_) {
      if (mounted) _open();
    });
  }

  Future<void> _configure() async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        // Let ffmpeg reconnect dropped HTTP streams by itself first.
        await platform.setProperty(
            'stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
        final ua = AppState.I.settings.userAgent;
        if (ua.isNotEmpty) await platform.setProperty('user-agent', ua);
      } catch (_) {}
    }
  }

  void _open() {
    final c = _channel;
    AppState.I.addRecent(c);
    _retryTimer?.cancel();
    setState(() {
      _status = null;
      _failed = false;
    });
    _flashInfo();
    _player.open(Media(AppState.I.streamUrlFor(c)));
  }

  void _onError(String e) {
    if (!mounted) return;
    // mpv reports some harmless errors while playing fine; ignore those.
    if (_player.state.playing) return;
    _scheduleRetry(e);
  }

  /// Our own reconnect loop (the original player's streams would just die).
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

  void _zap(int delta) {
    if (widget.playlist.length < 2) return;
    _playIndex((_index + delta) % widget.playlist.length);
  }

  void _playIndex(int i) {
    _retries = 0;
    _index = i;
    _open();
  }

  void _flashInfo() {
    _infoTimer?.cancel();
    if (mounted) setState(() => _showInfo = true);
    _infoTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showInfo = false);
    });
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

  void _volume(double d) {
    final v = (_player.state.volume + d).clamp(0.0, 100.0).toDouble();
    _player.setVolume(v);
  }

  void _toggleMute() {
    final v = _player.state.volume;
    if (v > 0) {
      _volumeBeforeMute = v;
      _player.setVolume(0);
    } else {
      _player.setVolume(_volumeBeforeMute);
    }
  }

  void _toggleList() {
    setState(() {
      _showList = !_showList;
      _listCtrl?.dispose();
      _listCtrl = _showList
          ? ScrollController(initialScrollOffset: ((_index - 4) * 60.0).clamp(0.0, double.infinity).toDouble())
          : null;
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _retryTimer?.cancel();
    _infoTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.space): () => _player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.escape): _exitOrBack,
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _zap(-1),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _zap(1),
      const SingleActivator(LogicalKeyboardKey.pageUp): () => _zap(-1),
      const SingleActivator(LogicalKeyboardKey.pageDown): () => _zap(1),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _volume(10),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _volume(-10),
      const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      const SingleActivator(LogicalKeyboardKey.keyL): _toggleList,
      const SingleActivator(LogicalKeyboardKey.keyI): _flashInfo,
    };

    final theme = MaterialDesktopVideoControlsThemeData(
      displaySeekBar: false,
      toggleFullscreenOnDoublePress: false,
      keyboardShortcuts: const {},
      topButtonBar: [
        MaterialDesktopCustomButton(
            icon: const Icon(Icons.arrow_back), onPressed: _exitOrBack),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_channel.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
      ],
      bottomButtonBar: [
        MaterialDesktopCustomButton(
            icon: const Icon(Icons.skip_previous_rounded), onPressed: () => _zap(-1)),
        const MaterialDesktopPlayOrPauseButton(),
        MaterialDesktopCustomButton(
            icon: const Icon(Icons.skip_next_rounded), onPressed: () => _zap(1)),
        const MaterialDesktopVolumeButton(),
        const Spacer(),
        MaterialDesktopCustomButton(
            icon: const Icon(Icons.info_outline_rounded), onPressed: _flashInfo),
        MaterialDesktopCustomButton(
            icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: _toggleList),
        MaterialDesktopCustomButton(
            icon: Icon(_fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded),
            onPressed: _toggleFullscreen),
      ],
    );

    final mobileTheme = MaterialVideoControlsThemeData(
      displaySeekBar: false,
      volumeGesture: true,
      brightnessGesture: true,
      topButtonBar: [
        MaterialCustomButton(
            icon: const Icon(Icons.arrow_back), onPressed: _exitOrBack),
        const SizedBox(width: 8),
        Expanded(
          child: Text(_channel.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        ),
        MaterialCustomButton(
            icon: const Icon(Icons.format_list_bulleted_rounded), onPressed: _toggleList),
      ],
      bottomButtonBar: [
        MaterialCustomButton(
            icon: const Icon(Icons.skip_previous_rounded), onPressed: () => _zap(-1)),
        MaterialCustomButton(
            icon: const Icon(Icons.skip_next_rounded), onPressed: () => _zap(1)),
        const Spacer(),
        MaterialCustomButton(
            icon: const Icon(Icons.info_outline_rounded), onPressed: _flashInfo),
      ],
    );

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
                child: GestureDetector(
                  onDoubleTap: _desktop ? _toggleFullscreen : null,
                  // Phone: swipe left/right to change channel.
                  onHorizontalDragEnd: _desktop
                      ? null
                      : (d) {
                          final v = d.primaryVelocity ?? 0;
                          if (v.abs() > 300) _zap(v < 0 ? 1 : -1);
                        },
                  child: Stack(
                    children: [
                      if (_desktop)
                        MaterialDesktopVideoControlsTheme(
                          normal: theme,
                          fullscreen: theme,
                          child: Video(
                            controller: _controller,
                            controls: MaterialDesktopVideoControls,
                          ),
                        )
                      else
                        MaterialVideoControlsTheme(
                          normal: mobileTheme,
                          fullscreen: mobileTheme,
                          child: Video(
                            controller: _controller,
                            controls: MaterialVideoControls,
                          ),
                        ),
                      Positioned(
                        left: 24,
                        bottom: 72,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: _showInfo ? 1 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: _infoCard(),
                          ),
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

  Widget _infoCard() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final progs = AppState.I.epg.forChannel(_channel);
    Programme? cur;
    Programme? next;
    for (var i = 0; i < progs.length; i++) {
      if (progs[i].isLiveAt(now)) {
        cur = progs[i];
        if (i + 1 < progs.length) next = progs[i + 1];
        break;
      }
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.72), borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChannelLogo(_channel, size: 52),
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${_index + 1}   ${_channel.name}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                  if (cur != null) ...[
                    const SizedBox(height: 6),
                    Text('${fmtMs(cur.start)}–${fmtMs(cur.stop)}   ${cur.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 360,
                      child: LinearProgressIndicator(
                        value: cur.progressAt(now),
                        minHeight: 3,
                        color: kAccent,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ],
                  if (next != null) ...[
                    const SizedBox(height: 6),
                    Text('Next  ${fmtMs(next.start)}   ${next.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
