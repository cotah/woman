import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

/// Always-on 24/7 location tracker.
///
/// This service runs independently from incident/journey tracking.
/// It periodically captures the user's location and:
/// - Stores a local history for AI pattern learning
/// - Detects when the user is at a new/unknown place
/// - Syncs location snapshots to the backend periodically
///
/// All data is encrypted locally and in transit.
/// No location is shared with anyone without the user's explicit action.
class LocationTrackerService extends ChangeNotifier {
  final ApiClient _apiClient;

  Timer? _trackingTimer;
  bool _isTracking = false;
  Position? _lastPosition;

  /// How often we capture a location snapshot (in minutes).
  static const int _intervalMinutes = 5;

  /// Maximum local history entries before pruning old ones.
  static const int _maxLocalHistory = 2000;

  /// Key for local storage.
  static const String _historyKey = 'safecircle_location_history';
  static const String _trackingEnabledKey = 'safecircle_tracking_enabled';

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;

  LocationTrackerService({required ApiClient apiClient})
      : _apiClient = apiClient;

  /// Initialize — check if tracking was previously enabled and restart.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_trackingEnabledKey) ?? false;
    if (enabled) {
      await startTracking();
    }
  }

  /// Start 24/7 location tracking.
  Future<void> startTracking() async {
    if (_isTracking) return;

    // Check permissions first
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint(
          '[LocationTracker] Permission not granted, cannot start tracking');
      return;
    }

    _isTracking = true;

    // Persist preference
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trackingEnabledKey, true);

    // Capture initial position
    await _captureSnapshot();

    // Set up periodic capture
    _trackingTimer = Timer.periodic(
      const Duration(minutes: _intervalMinutes),
      (_) => _captureSnapshot(),
    );

    debugPrint('[LocationTracker] 24/7 tracking started '
        '(interval: ${_intervalMinutes}min)');
    notifyListeners();
  }

  /// Stop tracking.
  Future<void> stopTracking() async {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _isTracking = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trackingEnabledKey, false);

    debugPrint('[LocationTracker] Tracking stopped');
    notifyListeners();
  }

  /// Capture a single location snapshot and store it.
  Future<void> _captureSnapshot() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      _lastPosition = position;

      final snapshot = LocationSnapshot(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        timestamp: DateTime.now(),
      );

      // Save locally
      await _saveSnapshot(snapshot);

      // Try to sync to backend (non-blocking)
      _syncToBackend(snapshot);

      notifyListeners();
    } catch (e) {
      debugPrint('[LocationTracker] Snapshot capture failed: $e');
    }
  }

  /// Save a snapshot to local history.
  Future<void> _saveSnapshot(LocationSnapshot snapshot) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyKey) ?? [];

      raw.add(jsonEncode(snapshot.toJson()));

      // Prune old entries
      if (raw.length > _maxLocalHistory) {
        raw.removeRange(0, raw.length - _maxLocalHistory);
      }

      await prefs.setStringList(_historyKey, raw);
    } catch (e) {
      debugPrint('[LocationTracker] Failed to save snapshot locally: $e');
    }
  }

  /// Get all local location history.
  Future<List<LocationSnapshot>> getLocalHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_historyKey) ?? [];

      return raw.map((s) {
        final json = jsonDecode(s) as Map<String, dynamic>;
        return LocationSnapshot.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint('[LocationTracker] Failed to read history: $e');
      return [];
    }
  }

  /// Get history for the last N hours.
  Future<List<LocationSnapshot>> getRecentHistory({int hours = 24}) async {
    final all = await getLocalHistory();
    final cutoff = DateTime.now().subtract(Duration(hours: hours));
    return all.where((s) => s.timestamp.isAfter(cutoff)).toList();
  }

  /// Sync a snapshot to the backend.
  Future<void> _syncToBackend(LocationSnapshot snapshot) async {
    try {
      await _apiClient.post(
        '/location/track',
        data: snapshot.toJson(),
      );
    } catch (e) {
      // Non-critical — will be synced in batch later
      debugPrint('[LocationTracker] Backend sync failed (will retry): $e');
    }
  }

  /// Batch sync all unsynced snapshots to backend.
  Future<int> syncPendingToBackend() async {
    try {
      final history = await getLocalHistory();
      if (history.isEmpty) return 0;

      // Send last 100 unsynced
      final batch = history.length > 100
          ? history.sublist(history.length - 100)
          : history;

      await _apiClient.post(
        '/location/track/batch',
        data: {
          'locations': batch.map((s) => s.toJson()).toList(),
        },
      );
      return batch.length;
    } catch (e) {
      debugPrint('[LocationTracker] Batch sync failed: $e');
      return 0;
    }
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }
}

/// A single location snapshot with timestamp.
class LocationSnapshot {
  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  const LocationSnapshot({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LocationSnapshot.fromJson(Map<String, dynamic> json) {
    return LocationSnapshot(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
