import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wrapper around [SharedPreferences] for the small set of keys this app uses.
/// Also owns the global [ThemeMode] notifier so the root [MaterialApp] can
/// react to theme changes from the settings screen.
class PreferencesService {
  PreferencesService._(this._prefs, this.themeMode);

  static const _kThemeMode = 'theme_mode';
  static const _kUserSettingsInitialized = 'user_settings_initialized';

  final SharedPreferences _prefs;

  /// Notifier consumed by the root [MaterialApp]. Seeded with the persisted
  /// value (defaults to [ThemeMode.system]).
  final ValueNotifier<ThemeMode> themeMode;

  static Future<PreferencesService> create() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_kThemeMode);
    final mode = _decodeThemeMode(stored);
    return PreferencesService._(prefs, ValueNotifier(mode));
  }

  // ---- Theme ----
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await _prefs.setString(_kThemeMode, _encodeThemeMode(mode));
  }

  // ---- First-launch user-settings POST (so /dashboard doesn't 404) ----
  bool get userSettingsInitialized =>
      _prefs.getBool(_kUserSettingsInitialized) ?? false;
  Future<void> setUserSettingsInitialized(bool value) =>
      _prefs.setBool(_kUserSettingsInitialized, value);

  String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _decodeThemeMode(String? stored) {
    switch (stored) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
