import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Thin JSON-aware wrapper over [SharedPreferences]. Local persistence for
/// child profiles, sessions, and settings in this offline slice. No child PII
/// leaves the device (§14.1).
class KeyValueStore {
  KeyValueStore(this._prefs);

  final SharedPreferences _prefs;

  /// Minimal inspection API: all keys currently persisted. Read-only; there
  /// is intentionally no bulk-clear (it could erase preserved credentials —
  /// see persistence_keys.dart).
  Set<String> get keys => _prefs.getKeys();

  static Future<KeyValueStore> create() async =>
      KeyValueStore(await SharedPreferences.getInstance());

  Map<String, dynamic>? readJson(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return json.decode(raw) as Map<String, dynamic>;
  }

  List<dynamic>? readJsonList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    return json.decode(raw) as List<dynamic>;
  }

  Future<void> writeJson(String key, Object value) =>
      _prefs.setString(key, json.encode(value));

  bool getBool(String key, {bool fallback = false}) =>
      _prefs.getBool(key) ?? fallback;

  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);

  String? getString(String key) => _prefs.getString(key);

  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  Future<void> remove(String key) => _prefs.remove(key);
}
