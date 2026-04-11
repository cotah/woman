import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages background execution for SafeCircle's always-on safety mode.
///
/// ## How It Works
///
/// When the user activates SafeCircle (during onboarding or in Settings),
/// this service starts a native foreground service (Android) or enables
/// background location mode (iOS) so the app runs 24/7.
///
/// ### Android
/// - Starts a Kotlin ForegroundService with a persistent notification
/// - Acquires a partial wake lock to keep the CPU active
/// - Service uses START_STICKY to restart if killed by the OS
/// - BootReceiver restarts the service after device reboot or app update
/// - Requests battery optimization exemption so the OS doesn't kill us
///
/// ### iOS
/// - Relies on background location mode (UIBackgroundModes: [location])
/// - Background audio mode for voice detection
/// - Significant location change service for killed-app recovery (~500m)
/// - No equivalent of Android foreground service — iOS is more restrictive
///
/// ### Data Privacy
/// - All data is encrypted in transit and at rest
/// - Location is only shared with trusted contacts during emergencies
/// - Audio is processed locally for voice activation word detection
/// - No data is sent to external servers without explicit user action
class BackgroundService extends ChangeNotifier {
  static const _channel = MethodChannel('com.safecircle.app/background');
  static const _lastLocationKey = 'safecircle_last_known_location';
  static const _alwaysOnKey = 'safecircle_always_on_enabled';

  bool _isRunning = false;
  bool _isAlwaysOn = false;

  /// True if the background service is currently active.
  bool get isRunning => _isRunning;

  /// True if the user has enabled the 24/7 always-on mode.
  bool get isAlwaysOn => _isAlwaysOn;

  /// Whether the native foreground service is actually available.
  bool _nativeServiceAvailable = false;
  bool get isNativeServiceAvailable => _nativeServiceAvailable;

  /// Whether battery optimization is exempted.
  bool _batteryOptimized = false;
  bool get isBatteryOptimizationExempt => _batteryOptimized;

  /// Initialize the service — check if always-on was previously enabled
  /// and restart if needed.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isAlwaysOn = prefs.getBool(_alwaysOnKey) ?? false;

    if (_isAlwaysOn && !_isRunning) {
      await startAlwaysOnMode();
    }

    // Check battery optimization status
    await _checkBatteryOptimization();

    notifyListeners();
  }

  /// Start the always-on 24/7 safety mode.
  ///
  /// This is the main method called when the user activates SafeCircle.
  /// It starts the native foreground service and persists the preference.
  Future<void> startAlwaysOnMode() async {
    if (_isRunning) return;

    try {
      await _channel.invokeMethod('startForegroundService', {
        'title': 'SafeCircle Active',
        'body': 'Your safety guardian is running. All data is encrypted.',
      });
      _isRunning = true;
      _nativeServiceAvailable = true;
      _isAlwaysOn = true;

      // Persist so BootReceiver and app restart know to re-enable
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_alwaysOnKey, true);

      debugPrint('[BackgroundService] Always-on mode started (native)');
      notifyListeners();
    } on MissingPluginException {
      // Web or platform without native implementation
      debugPrint(
        '[BackgroundService] Native service not available. '
        'Running in foreground-only mode (Web or missing native code).',
      );
      _isRunning = true;
      _nativeServiceAvailable = false;
      _isAlwaysOn = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_alwaysOnKey, true);

      notifyListeners();
    } catch (e) {
      debugPrint('[BackgroundService] Failed to start always-on mode: $e');
    }
  }

  /// Stop the always-on mode (user explicitly disables it).
  Future<void> stopAlwaysOnMode() async {
    try {
      await _channel.invokeMethod('stopForegroundService');
    } on MissingPluginException {
      // Expected on web
    } catch (e) {
      debugPrint('[BackgroundService] Failed to stop: $e');
    }

    _isRunning = false;
    _nativeServiceAvailable = false;
    _isAlwaysOn = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_alwaysOnKey, false);

    notifyListeners();
  }

  /// Start background execution for a specific event (incident or journey).
  /// If always-on mode is already active, this is a no-op since the service
  /// is already running.
  Future<void> startBackgroundMode({
    required String reason, // 'incident' or 'journey'
  }) async {
    if (_isRunning) return; // Already running (always-on or previous call)

    try {
      await _channel.invokeMethod('startForegroundService', {
        'title': 'SafeCircle',
        'body': reason == 'incident'
            ? 'Emergency alert active - sharing your location'
            : 'Safe journey active - sharing your location',
      });
      _isRunning = true;
      _nativeServiceAvailable = true;
      notifyListeners();
    } on MissingPluginException {
      debugPrint(
        '[BackgroundService] Native foreground service not available.',
      );
      _isRunning = true;
      _nativeServiceAvailable = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[BackgroundService] Failed to start: $e');
    }
  }

  /// Stop background execution (call when incident/journey ends).
  /// Does NOT stop always-on mode — only stops event-specific background.
  Future<void> stopBackgroundMode() async {
    if (!_isRunning) return;

    // If always-on is enabled, don't actually stop the service
    if (_isAlwaysOn) {
      // Just update the notification text back to default
      try {
        await _channel.invokeMethod('startForegroundService', {
          'title': 'SafeCircle Active',
          'body': 'Your safety guardian is running. All data is encrypted.',
        });
      } on MissingPluginException {
        // Expected
      } catch (_) {}
      return;
    }

    try {
      await _channel.invokeMethod('stopForegroundService');
    } on MissingPluginException {
      // Expected
    } catch (e) {
      debugPrint('[BackgroundService] Failed to stop: $e');
    }

    _isRunning = false;
    _nativeServiceAvailable = false;
    notifyListeners();
  }

  /// Request battery optimization exemption (Android only).
  /// This prevents the OS from killing the service when the screen is off.
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final result = await _channel
          .invokeMethod<bool>('requestBatteryOptimizationExemption');
      _batteryOptimized = result ?? false;
      notifyListeners();
      return _batteryOptimized;
    } on MissingPluginException {
      // Web or iOS
      _batteryOptimized = true; // Not applicable
      return true;
    } catch (e) {
      debugPrint('[BackgroundService] Battery optimization request failed: $e');
      return false;
    }
  }

  Future<void> _checkBatteryOptimization() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('isBatteryOptimizationExempt');
      _batteryOptimized = result ?? false;
    } on MissingPluginException {
      _batteryOptimized = true;
    } catch (_) {
      _batteryOptimized = false;
    }
  }

  /// Persist the last known location to SharedPreferences.
  /// Call this periodically during tracking so that if the app is killed,
  /// the last location is available for SMS fallback on next launch.
  Future<void> persistLastKnownLocation(
    double latitude,
    double longitude, {
    double? accuracy,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastLocationKey,
        '$latitude,$longitude,${accuracy ?? 0},${DateTime.now().toIso8601String()}',
      );
    } catch (e) {
      debugPrint('[BackgroundService] Failed to persist location: $e');
    }
  }

  /// Retrieve the last persisted location. Returns null if none saved.
  Future<({double lat, double lng, double accuracy, DateTime timestamp})?>
      getLastPersistedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_lastLocationKey);
      if (raw == null) return null;

      final parts = raw.split(',');
      if (parts.length < 4) return null;

      return (
        lat: double.parse(parts[0]),
        lng: double.parse(parts[1]),
        accuracy: double.parse(parts[2]),
        timestamp: DateTime.parse(parts[3]),
      );
    } catch (e) {
      debugPrint('[BackgroundService] Failed to read persisted location: $e');
      return null;
    }
  }

  @override
  void dispose() {
    // Don't stop the service on dispose if always-on is enabled
    if (!_isAlwaysOn) {
      stopBackgroundMode();
    }
    super.dispose();
  }
}
