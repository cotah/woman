import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';

/// Manages background execution for active incidents and journeys.
///
/// ## Platform Capability Matrix
///
/// | Capability                    | Android            | iOS                |
/// |-------------------------------|--------------------|--------------------|
/// | Foreground service            | REQUIRES NATIVE*   | N/A                |
/// | Background location updates   | Via geolocator     | Via geolocator**   |
/// | Prevent app kill              | REQUIRES NATIVE*   | NOT POSSIBLE       |
/// | Wake from killed state        | REQUIRES NATIVE*   | Significant loc*** |
/// | Persistent notification       | REQUIRES NATIVE*   | N/A                |
/// | Audio recording in background | REQUIRES NATIVE*   | UIBackgroundMode** |
///
/// * Android foreground service requires native Kotlin/Java code registered
///   via MethodChannel. This is NOT yet implemented — the MethodChannel calls
///   will silently fail (MissingPluginException) until native code is added.
///
/// ** iOS background location requires `UIBackgroundModes: [location]` in
///    Info.plist AND `NSLocationAlwaysAndWhenInUseUsageDescription`. The
///    geolocator package handles this if permissions are granted.
///
/// *** iOS significant location changes can wake a killed app, but with
///     ~500m granularity — not suitable for fine-grained tracking.
///
/// ## Current Status: DART SCAFFOLD ONLY
///
/// The MethodChannel calls in this service are placeholders. They will
/// gracefully degrade (no crash, no error UI) but will NOT actually
/// keep the app alive in the background on either platform until the
/// corresponding native code is written.
///
/// What DOES work today without native code:
/// - Location tracking via geolocator (works while app is in foreground,
///   limited background on iOS with proper Info.plist config)
/// - Audio recording (works while app is in foreground only)
/// - Last-known-location persistence (see [persistLastKnownLocation])
///
/// ## What Must Be Built Natively
///
/// Android:
/// - Kotlin ForegroundService with persistent notification
/// - Register in AndroidManifest.xml with FOREGROUND_SERVICE permission
/// - MethodChannel bridge to start/stop from Dart
///
/// iOS:
/// - No foreground service concept; rely on background location mode
/// - Ensure Info.plist has UIBackgroundModes: [location, audio]
/// - Consider significant-change location service for killed-app recovery
class BackgroundService extends ChangeNotifier {
  static const _channel = MethodChannel('com.safecircle.app/background');
  static const _lastLocationKey = 'safecircle_last_known_location';

  bool _isRunning = false;

  /// True if startBackgroundMode was called. Does NOT guarantee the OS
  /// is actually keeping the app alive — see platform matrix above.
  bool get isRunning => _isRunning;

  /// Whether the native foreground service is actually available.
  /// False until native code is implemented.
  bool _nativeServiceAvailable = false;
  bool get isNativeServiceAvailable => _nativeServiceAvailable;

  /// Start background execution (call when an incident or journey starts).
  ///
  /// On Android: Attempts to start a foreground service via MethodChannel.
  /// On iOS: No-op (relies on geolocator background location mode).
  ///
  /// If native code is not yet implemented, this sets [_isRunning] to true
  /// but does NOT actually prevent the app from being killed by the OS.
  Future<void> startBackgroundMode({
    required String reason, // 'incident' or 'journey'
  }) async {
    if (_isRunning) return;

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
      // EXPECTED: Native code not yet implemented.
      // App will work in foreground but may be killed in background.
      debugPrint(
        '[BackgroundService] Native foreground service not available. '
        'App may be killed by OS in background. '
        'Location tracking relies on geolocator background mode only.',
      );
      _isRunning = true;
      _nativeServiceAvailable = false;
      notifyListeners();
    } catch (e) {
      debugPrint('[BackgroundService] Failed to start: $e');
    }
  }

  /// Stop background execution (call when incident/journey ends).
  Future<void> stopBackgroundMode() async {
    if (!_isRunning) return;

    try {
      await _channel.invokeMethod('stopForegroundService');
    } on MissingPluginException {
      // Expected — native code not yet implemented.
    } catch (e) {
      debugPrint('[BackgroundService] Failed to stop: $e');
    }

    _isRunning = false;
    _nativeServiceAvailable = false;
    notifyListeners();
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
  Future<({double lat, double lng, double accuracy, DateTime timestamp})?> getLastPersistedLocation() async {
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
    stopBackgroundMode();
    super.dispose();
  }
}
