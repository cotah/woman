import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/journey.dart';
import '../models/location_update.dart';
import 'location_service.dart';

/// Manages Safe Journey lifecycle: start, track, check-in, complete, cancel.
///
/// Listens to [LocationService.locationStream] and auto-sends location
/// updates to the backend while a journey is active.
class JourneyService extends ChangeNotifier {
  final ApiClient _apiClient;
  final LocationService _locationService;

  Journey? _activeJourney;
  bool _isLoading = false;
  StreamSubscription<LocationUpdate>? _locationSubscription;

  JourneyService({
    required ApiClient apiClient,
    required LocationService locationService,
  })  : _apiClient = apiClient,
        _locationService = locationService {
    _locationSubscription =
        _locationService.locationStream.listen(_onLocationUpdate);
  }

  Journey? get activeJourney => _activeJourney;
  bool get isLoading => _isLoading;
  bool get hasActiveJourney => _activeJourney != null;

  /// Start a new journey. Returns the created journey.
  Future<Journey> startJourney({
    required double destLat,
    required double destLng,
    String? destLabel,
    required int durationMinutes,
    double? startLat,
    double? startLng,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = <String, dynamic>{
        'destLatitude': destLat,
        'destLongitude': destLng,
        'durationMinutes': durationMinutes,
      };

      if (destLabel != null) data['destLabel'] = destLabel;
      if (startLat != null) data['startLatitude'] = startLat;
      if (startLng != null) data['startLongitude'] = startLng;

      final response = await _apiClient.post(
        ApiEndpoints.journey,
        data: data,
      );

      final journey =
          Journey.fromJson(response.data as Map<String, dynamic>);
      _activeJourney = journey;

      // Start location tracking for the journey.
      await _locationService.startTracking();

      return journey;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch the currently active journey from the backend.
  /// Returns null if no active journey exists.
  ///
  /// Backend contract: GET /journey/active always returns 200 with
  /// { journey: <data|null> }. Never returns 404 for "no active journey".
  Future<Journey?> getActiveJourney() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.get(ApiEndpoints.journeyActive);
      final data = response.data;

      // Handle explicit null contract: { journey: null }
      if (data is Map<String, dynamic> && data.containsKey('journey')) {
        final journeyData = data['journey'];
        if (journeyData == null) {
          _activeJourney = null;
          notifyListeners();
          return null;
        }
        final journey =
            Journey.fromJson(journeyData as Map<String, dynamic>);
        _activeJourney = journey;
        notifyListeners();
        return journey;
      }

      // Fallback: if backend returns journey object directly (legacy).
      if (data is Map<String, dynamic> && data.containsKey('id')) {
        final journey = Journey.fromJson(data);
        _activeJourney = journey;
        notifyListeners();
        return journey;
      }

      _activeJourney = null;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      // Defensive: handle 404 even though backend shouldn't return it.
      if (e.response?.statusCode == 404) {
        _activeJourney = null;
        notifyListeners();
        return null;
      }
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check in to extend the journey timer.
  Future<Journey> checkin(int additionalMinutes) async {
    if (_activeJourney == null) {
      throw StateError('No active journey to check in to');
    }

    final response = await _apiClient.post(
      ApiEndpoints.journeyCheckin(_activeJourney!.id),
      data: {'additionalMinutes': additionalMinutes},
    );

    final journey =
        Journey.fromJson(response.data as Map<String, dynamic>);
    _activeJourney = journey;
    notifyListeners();
    return journey;
  }

  /// Mark the journey as completed (arrived safely).
  Future<void> complete() async {
    if (_activeJourney == null) {
      throw StateError('No active journey to complete');
    }

    await _apiClient.post(
      ApiEndpoints.journeyComplete(_activeJourney!.id),
    );

    await _locationService.stopTracking();
    _activeJourney = null;
    notifyListeners();
  }

  /// Cancel the journey.
  Future<void> cancel() async {
    if (_activeJourney == null) {
      throw StateError('No active journey to cancel');
    }

    await _apiClient.delete(
      ApiEndpoints.journeyCancel(_activeJourney!.id),
    );

    await _locationService.stopTracking();
    _activeJourney = null;
    notifyListeners();
  }

  /// Send a location update for the active journey.
  /// The backend checks arrival server-side.
  Future<void> sendLocation(double lat, double lng) async {
    if (_activeJourney == null) return;

    try {
      final response = await _apiClient.post(
        ApiEndpoints.journeyLocation(_activeJourney!.id),
        data: {
          'latitude': lat,
          'longitude': lng,
        },
      );

      // If the backend returns an updated journey (e.g. auto-completed on
      // arrival), update local state.
      if (response.data is Map<String, dynamic>) {
        final updated =
            Journey.fromJson(response.data as Map<String, dynamic>);
        if (updated.status.isTerminal) {
          await _locationService.stopTracking();
        }
        _activeJourney = updated;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[JourneyService] Failed to send location: $e');
      // Don't rethrow - location tracking continues even if a send fails.
    }
  }

  // ── Private helpers ─────────────────────────────

  void _onLocationUpdate(LocationUpdate update) {
    if (_activeJourney == null) return;
    if (_activeJourney!.status.isTerminal) return;

    sendLocation(update.latitude, update.longitude);
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    super.dispose();
  }
}
