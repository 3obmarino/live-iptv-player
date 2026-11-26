import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_state.dart';
import 'models.dart';

/// Playback engine shared by the TV screens: opens channels, reconnects
/// dropped streams, reports status. UI listens via ChangeNotifier.
class PlayerCore extends ChangeNotifier with WidgetsBindingObserver {
  PlayerCore() {
    WidgetsBinding.instance.addObserver(this);
    player = Player();
    controller = VideoController(player, configuration: videoConfig());
    _subs.add(player.stream.error.listen(_onError));
    _subs.add(player.stream.completed.listen((done) {
      if (done) _scheduleRetry('The stream ended');
    }));
    _subs.add(player.stream.playing.listen((p) {
      playing = p;
      notifyListeners();
    }));
    // The stream really runs once a picture size or sound format is known.
    void started(_) {
      if (!streamStarted(player)) return;
      _startTimer?.cancel();
      if (_retries != 0 || status != null || failed) {
        _retries = 0;
        status = null;
        failed = false;
        notifyListeners();
      }
    }
    _subs.add(player.stream.width.listen(started));
    _subs.add(player.stream.audioParams.listen(started));
    _ready = _configure();
  }

  late final Player player;
  late final VideoController controller;
  final List<StreamSubscription<dynamic>> _subs = [];
  late final Future<void> _ready;

  Channel? channel;
  bool playing = false;
  String? status;
  bool failed = false;
  int _retries = 0;
  Timer? _retryTimer;
  Timer? _startTimer;
  bool _disposed = false;

  Future<void> _configure() => tuneForLive(player);

  Future<void> play(Channel c) async {
    await _ready;
    if (_disposed) return;
    channel = c;
    AppState.I.addRecent(c);
    _retryTimer?.cancel();
    _retries = 0;
    status = null;
    failed = false;
    notifyListeners();
    await player.open(Media(AppState.I.streamUrlFor(c)));
    _watchStart();
  }

  /// Some providers answer the first request for a channel that isn't
  /// running yet with a short HLS playlist mpv refuses to play, while mpv
  /// still reports "playing". Reopen if nothing has started after 10 s.
  void _watchStart() {
    _startTimer?.cancel();
    _startTimer = Timer(const Duration(seconds: 10), () {
      if (!_disposed && channel != null && !streamStarted(player)) {
        _scheduleRetry('No picture or sound');
      }
    });
  }

  void retry() {
    final c = channel;
    if (c != null) play(c);
  }

  void _onError(String e) {
    // mpv reports harmless errors while a stream plays fine; only a stream
    // that never started (no picture size, no sound format) needs a retry.
    if (streamStarted(player)) return;
    if (_retryTimer?.isActive ?? false) return; // one retry per burst
    _scheduleRetry(e);
  }

  void _scheduleRetry(String reason) {
    if (_disposed || channel == null) return;
    if (_retries >= 5) {
      failed = true;
      status = reason;
      notifyListeners();
      return;
    }
    _retries++;
    status = 'Reconnecting… ($_retries/5)';
    notifyListeners();
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: 2 * _retries), () {
      final c = channel;
      if (!_disposed && c != null) {
        player.open(Media(AppState.I.streamUrlFor(c)));
        _watchStart();
      }
    });
  }

  /// Leaving the app (HOME) destroys the video surface on Android TV. Stop
  /// the stream and restart the channel on return, so the picture never
  /// stays frozen on the old surface.
  bool _wasBackgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (!_wasBackgrounded && channel != null) {
        _wasBackgrounded = true;
        _retryTimer?.cancel();
        player.stop();
      }
    } else if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      retry();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _retryTimer?.cancel();
    _startTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}

/// Android / Google TV: let the hardware decoder draw straight onto the
/// screen (mediacodec_embed) instead of copying every frame through the GPU.
/// That copy is what makes 1080p/4K live TV stutter on TV boxes.
VideoControllerConfiguration videoConfig() {
  final hw = AppState.I.settings.hwdec;
  if (Platform.isAndroid && hw) {
    return const VideoControllerConfiguration(
      vo: 'mediacodec_embed',
      hwdec: 'mediacodec',
    );
  }
  return VideoControllerConfiguration(enableHardwareAcceleration: hw);
}

/// True once the stream really runs: a picture size or a sound format is
/// known. mpv's own "playing" flag turns on even when opening failed.
bool streamStarted(Player p) =>
    (p.state.width ?? 0) > 0 || (p.state.audioParams.sampleRate ?? 0) > 0;

/// mpv settings for smooth, long-running live streams.
Future<void> tuneForLive(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  final props = <String, String>{
    // reconnect dropped HTTP streams inside ffmpeg first
    'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
    // a few seconds of buffer smooths out network hiccups
    'cache': 'yes',
    'cache-on-disk': 'no', // memory only (logged "Failed to create file cache")
    'cache-secs': '8',
    'demuxer-readahead-secs': '8',
    'demuxer-max-bytes': '64MiB',
    'demuxer-max-back-bytes': '8MiB',
    // drop late frames instead of slowing down; keep audio steady
    'framedrop': 'vo',
    'audio-buffer': '0.5',
    // decode audio ourselves (no passthrough): passthrough to soundbars /
    // eARC is a common cause of audio going silent after a while
    'audio-spdif': '',
    // live streams: never stop at "end of file" on a short read
    'keep-open': 'no',
  };
  final ua = AppState.I.settings.userAgent;
  if (ua.isNotEmpty) props['user-agent'] = ua;
  for (final e in props.entries) {
    try {
      await platform.setProperty(e.key, e.value);
    } catch (_) {}
  }
}
