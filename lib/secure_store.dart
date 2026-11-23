import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Keeps a profile's login (username, password, playlist/EPG URLs) in the
/// operating system's encrypted store on THIS device only:
/// Windows: DPAPI-encrypted, Android/Google TV: Android Keystore.
/// Nothing is sent anywhere; Android cloud backup is disabled in the build.
class SecretStore {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static final Map<String, String> _lastWritten = {};

  static String _key(String id) => 'profile_$id';

  static Future<Map<String, String>?> read(String id) async {
    try {
      final v = await _s.read(key: _key(id));
      if (v == null) return null;
      _lastWritten[id] = v;
      return (jsonDecode(v) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return null;
    }
  }

  /// Returns false if the secure store is unavailable.
  static Future<bool> write(String id, Map<String, String> data) async {
    final v = jsonEncode(data);
    if (_lastWritten[id] == v) return true;
    try {
      await _s.write(key: _key(id), value: v);
      _lastWritten[id] = v;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> delete(String id) async {
    _lastWritten.remove(id);
    try {
      await _s.delete(key: _key(id));
    } catch (_) {}
  }
}
