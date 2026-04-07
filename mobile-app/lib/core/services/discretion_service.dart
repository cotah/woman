import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages discretion modes for the app.
/// - Silent mode: No sounds, minimal visual feedback
/// - Disguised mode: App appears as a calculator
class DiscretionService extends ChangeNotifier {
  static const _silentKey = 'safecircle_silent_mode';
  static const _disguisedKey = 'safecircle_disguised_mode';

  bool _isSilentMode = false;
  bool _isDisguisedMode = false;

  bool get isSilentMode => _isSilentMode;
  bool get isDisguisedMode => _isDisguisedMode;

  /// Load saved preferences.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isSilentMode = prefs.getBool(_silentKey) ?? false;
    _isDisguisedMode = prefs.getBool(_disguisedKey) ?? false;
    notifyListeners();
  }

  Future<void> setSilentMode(bool enabled) async {
    _isSilentMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_silentKey, enabled);
    notifyListeners();
  }

  Future<void> setDisguisedMode(bool enabled) async {
    _isDisguisedMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_disguisedKey, enabled);
    notifyListeners();
  }
}
