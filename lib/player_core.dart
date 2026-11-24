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
      if (p) {
        _retries = 0;
        status = null;
        failed = false;
      }
      notifyListeners();
    }));
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
  }

  void retry() {
    final c = channel;
    if (c != null) play(c);
  }

  void _onError(String e) {
    if (player.state.playing) return; // harmless mpv noise while playing
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
      if (!_disposed && c != null) player.open(Media(AppState.I.streamUrlFor(c)));
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

/// mpv settings for smooth, long-running live streams.
Future<void> tuneForLive(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) return;
  final props = <String, String>{
    // reconnect dropped HTTP streams inside ffmpeg first
    'stream-lavf-o': 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5',
    // a few seconds of buffer smooths out network hiccups
    'cache': 'yes',
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
