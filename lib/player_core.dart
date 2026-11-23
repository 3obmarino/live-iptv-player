import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_state.dart';
import 'models.dart';

/// Playback engine shared by the TV screens: opens channels, reconnects
/// dropped streams, reports status. UI listens via ChangeNotifier.
class PlayerCore extends ChangeNotifier {
  PlayerCore() {
    player = Player();
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: AppState.I.settings.hwdec),
    );
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

  Future<void> _configure() async {
    final platform = player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(
            'stream-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
        final ua = AppState.I.settings.userAgent;
        if (ua.isNotEmpty) await platform.setProperty('user-agent', ua);
      } catch (_) {}
    }
  }

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

  @override
  void dispose() {
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _retryTimer?.cancel();
    player.dispose();
    super.dispose();
  }
}
