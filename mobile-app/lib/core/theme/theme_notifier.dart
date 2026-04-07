import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app's theme mode (light, dark, system) and persists
/// the user's preference to SharedPreferences.
class ThemeNotifier extends ChangeNotifier {
  static const String _prefKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  ThemeNotifier() {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_prefKey);
    if (stored != null) {
      _themeMode = _fromString(stored);
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _toString(mode));
  }

  static String _toString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static ThemeMode _fromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
