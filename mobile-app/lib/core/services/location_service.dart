import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/location_update.dart';

/// Geolocator-based location tracking service.
/// Handles permissions, continuous tracking, and backend submission.
class LocationService extends ChangeNotifier {
  final ApiClient _apiClient;

  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  bool _isTracking = false;
  String? _activeIncidentId;

  /// Stream controller for broadcasting location updates to listeners.
  final StreamController<LocationUpdate> _locationController =
      StreamController<LocationUpdate>.broadcast();

  LocationService({required ApiClient apiClient}) : _apiClient = apiClient;

  bool get isTracking => _isTracking;
  Position? get lastPosition => _lastPosition;
  Stream<LocationUpdate> get locationStream => _locationController.stream;

  /// Check and request location permissions. Returns true if granted.
  Future<bool> requestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // Cannot request again - user must enable in settings.
      return false;
    }

    return true;
  }

  /// Get the current position as a one-shot request.
  Future<LocationUpdate?> getCurrentLocation() async {
    final hasPermission = await requestPermissions();
    if (!hasPermission) return null;

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _lastPosition = position;

      return LocationUpdate(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        altitude: position.altitude,
        provider: 'gps',
        timestamp: position.timestamp,
      );
    } catch (e) {
      debugPrint('[LocationService] Error getting current location: $e');
      return null;
    }
  }

  /// Start continuous location tracking.
  /// If [incidentId] is provided, updates are sent to the backend.
  Future<void> startTracking({String? incidentId}) async {
    if (_isTracking) return;

    final hasPermission = await requestPermissions();
    if (!hasPermission) {
      debugPrint('[LocationService] No location permission');
      return;
    }

    _activeIncidentId = incidentId;
    _isTracking = true;
    notifyListeners();

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // minimum 5 meters between updates
    );

    _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
      _onPositionUpdate,
      onError: (error) {
        debugPrint('[LocationService] Stream error: $error');
      },
    );
  }

  /// Stop continuous location tracking.
  Future<void> stopTracking() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _activeIncidentId = null;
    _isTracking = false;
    notifyListeners();
  }

  /// Set the active incident ID for backend location submissions.
  void setActiveIncident(String? incidentId) {
    _activeIncidentId = incidentId;
  }

  void _onPositionUpdate(Position position) {
    _lastPosition = position;

    final update = LocationUpdate(
      incidentId: _activeIncidentId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      speed: position.speed,
      heading: position.heading,
      altitude: position.altitude,
      provider: 'gps',
      timestamp: position.timestamp,
    );

    _locationController.add(update);

    // Send to backend if we have an active incident.
    if (_activeIncidentId != null) {
      _sendLocationToBackend(update);
    }
  }

  Future<void> _sendLocationToBackend(LocationUpdate update) async {
    if (_activeIncidentId == null) return;

    try {
      await _apiClient.post(
        ApiEndpoints.incidentLocation(_activeIncidentId!),
        data: update.toJson(),
      );
    } catch (e) {
      debugPrint('[LocationService] Failed to send location update: $e');
      // Don't rethrow - location tracking continues even if a send fails.
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _locationController.close();
    super.dispose();
  }
}
