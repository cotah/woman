import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's preference for stealth mode (calculator disguise).
///
/// SAFETY-CRITICAL: Stealth mode is a protective layer for users who may
/// have their phone inspected by an aggressor. When active, opening the
/// app launches a fake calculator. The real app is only reachable by
/// typing the Coercion PIN followed by `=`.
///
/// Activation requires BOTH conditions to be true at the same time:
///   1. User preference for stealth is enabled (this service)
///   2. User has configured a Coercion PIN (via [CoercionHandler])
///
/// If preference is on but PIN is missing, the app behaves normally —
/// the settings UI surfaces the gap and prompts the user to set a PIN.
/// This avoids a lock-out where the user enables stealth without a way
/// back into the real app.
///
/// SESSION UNLOCK: When the user enters the Coercion PIN in the
/// calculator and is taken to `/home`, the router would normally see
/// stealth still effective and bounce them back to `/calculator` —
/// causing a redirect loop. To prevent that, the calculator calls
/// [unlockForSession] before navigating, which marks the current app
/// session as unlocked. The flag lives in memory only — it resets on
/// logout (via [lockSession]) or on cold app boot (instance recreated).
class StealthModeService extends ChangeNotifier {
  static const _prefsKey = 'safecircle_stealth_mode_enabled';

  bool _prefersStealthMode = true; // Safe default until [initialize] runs.
  bool _initialized = false;
  bool _sessionUnlocked = false;

  /// Whether the user has stealth mode enabled in preferences.
  /// Synchronous — value is cached after [initialize].
  bool get prefersStealthMode => _prefersStealthMode;

  /// Whether [initialize] has completed loading from disk.
  bool get isInitialized => _initialized;

  /// Whether the current session bypasses stealth (set after a successful
  /// PIN unlock in the calculator). In-memory only — resets on logout
  /// or cold boot.
  bool get isSessionUnlocked => _sessionUnlocked;

  /// Returns true when stealth should actually engage right now.
  /// Requires preference enabled, a coercion PIN configured, and the
  /// session NOT already unlocked.
  bool isEffectivelyEnabled({required bool hasCoercionPin}) {
    if (_sessionUnlocked) return false;
    return _prefersStealthMode && hasCoercionPin;
  }

  /// Loads the stored preference. Must be called once at app startup,
  /// before [runApp], so the router can read [prefersStealthMode]
  /// synchronously.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Default to true when never set — protective default for at-risk users.
      _prefersStealthMode = prefs.getBool(_prefsKey) ?? true;
    } catch (e) {
      debugPrint('[StealthModeService] init error: $e');
      _prefersStealthMode = true; // Conservative fallback.
    }
    _initialized = true;
    notifyListeners();
  }

  /// Persists a new preference value and notifies listeners.
  Future<void> setPrefersStealthMode(bool value) async {
    if (_prefersStealthMode == value) return;
    _prefersStealthMode = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (e) {
      debugPrint('[StealthModeService] save error: $e');
    }
  }

  /// Marks the current session as unlocked. Called by the calculator
  /// after a successful Coercion PIN match, immediately before
  /// navigating to `/home`.
  void unlockForSession() {
    if (_sessionUnlocked) return;
    _sessionUnlocked = true;
    notifyListeners();
  }

  /// Re-locks the session (called on logout or auth state reset).
  void lockSession() {
    if (!_sessionUnlocked) return;
    _sessionUnlocked = false;
    notifyListeners();
  }
}
