import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_state.dart';
import 'diag.dart';
import 'models.dart';

/// Playback engine shared by the TV screens: opens channels, reconnects
/// dropped streams, reports status. UI listens via ChangeNotifier.
class PlayerCore extends ChangeNotifier with WidgetsBindingObserver {
  PlayerCore() {
    WidgetsBinding.instance.addObserver(this);
    player = newPlayer();
    controller = VideoController(player, configuration: videoConfig());
    attachPlayerLog(player, controller, _subs, 'tv');
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
      if (_retries != 0 || status != null || failed || loading) {
        _retries = 0;
        status = null;
        failed = false;
        loading = false;
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
  /// Opening (or quietly retrying) a channel that hasn't started yet: the UI
  /// shows only a calm spinner. [status] is set only when it finally fails.
  bool loading = false;
  int _retries = 0;
  Timer? _retryTimer;
  Timer? _startTimer;
  bool _disposed = false;

  Future<void> _configure() => tuneForLive(player);

  Future<void> play(Channel c) async {
    await _ready;
    if (_disposed) return;
    channel = c;
    Diag.log('[tv] open channel #${c.number} "${c.name}"');
    AppState.I.addRecent(c);
    _retryTimer?.cancel();
    _retries = 0;
    status = null;
    failed = false;
    loading = true;
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
        Diag.log('[tv] nothing started after 10 s: reopening');
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
      loading = false;
      status = 'This channel isn\'t responding right now. Try again in a moment, or pick another channel.';
      notifyListeners();
      return;
    }
    _retries++;
    Diag.log('[tv] retry $_retries after: $reason');
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

/// A Player whose mpv messages reach [attachPlayerLog] when logging is on.
Player newPlayer() => Player(
    configuration: PlayerConfiguration(
        logLevel: Diag.enabled ? MPVLogLevel.info : MPVLogLevel.error));

/// Writes what [p] does to the local player log (see [Diag]).
void attachPlayerLog(Player p, VideoController c, List<StreamSubscription<dynamic>> subs, String tag) {
  if (!Diag.enabled) return;
  final sw = Stopwatch()..start();
  String t() => '[$tag ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(2)}s]';
  Diag.log('${t()} create player (${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
      'hwdec=${AppState.I.settings.hwdec}, format=${AppState.I.settings.streamFormat})');
  c.platform.future.then((_) => Diag.log('${t()} video output ready'),
      onError: (e) => Diag.log('${t()} video output FAILED: $e'));
  c.id.addListener(() => Diag.log('${t()} texture id ${c.id.value}'));
  c.rect.addListener(() => Diag.log('${t()} texture size ${c.rect.value?.width}x${c.rect.value?.height}'));
  c.waitUntilFirstFrameRendered.then((_) => Diag.log('${t()} FIRST FRAME rendered'), onError: (_) {});
  subs.add(p.stream.playing.listen((v) => Diag.log('${t()} playing=$v')));
  subs.add(p.stream.buffering.listen((v) => Diag.log('${t()} buffering=$v')));
  subs.add(p.stream.videoParams.listen((v) =>
      Diag.log('${t()} video ${v.w}x${v.h} ${v.pixelformat} ${v.hwPixelformat ?? ''}')));
  subs.add(p.stream.audioParams.listen((v) =>
      Diag.log('${t()} audio ${v.format} ${v.sampleRate}Hz ${v.channelCount}ch')));
  subs.add(p.stream.tracks.listen((v) =>
      Diag.log('${t()} tracks video=${v.video.length} audio=${v.audio.length}')));
  subs.add(p.stream.error.listen((e) => Diag.log('${t()} ERROR $e')));
  subs.add(p.stream.log.listen((l) {
    final pre = l.prefix;
    if (l.level == 'error' || l.level == 'warn' ||
        pre.startsWith('vo') || pre.startsWith('vd') || pre == 'cplayer') {
      Diag.log('${t()} mpv ${l.level} $pre: ${l.text.trim()}');
    }
  }));
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
