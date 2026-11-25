import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'storage.dart';

/// Android: open Live TV automatically when the device starts (for TV boxes
/// and signage screens). The native BootReceiver looks for the flag file.
class Autostart extends ChangeNotifier with WidgetsBindingObserver {
  Autostart._() {
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }
  static final Autostart I = Autostart._();

  static const _ch = MethodChannel('livetv/boot');
  static bool get supported => Platform.isAndroid;

  File get _flag => Store.file('autostart_on_boot');

  bool get enabled => supported && _flag.existsSync();

  /// Android 10+ needs "Display over other apps" to start after boot.
  bool permitted = true;

  Future<void> _refresh() async {
    if (!supported) return;
    try {
      permitted = await _ch.invokeMethod<bool>('canStartFromBackground') ?? false;
    } catch (_) {
      permitted = false;
    }
    notifyListeners();
  }

  // Coming back from Android settings: re-check the permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  /// Returns false when the permission screen could not be opened.
  Future<bool> setEnabled(bool on) async {
    if (on) {
      await _flag.writeAsString('1');
    } else if (_flag.existsSync()) {
      await _flag.delete();
    }
    await _refresh();
    if (on && !permitted) return openPermission();
    return true;
  }

  Future<bool> openPermission() async {
    try {
      return await _ch.invokeMethod<bool>('openPermissionSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}
