import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/incident.dart';
import '../models/location_update.dart';
import '../models/timeline_event.dart';
import 'location_service.dart';
import 'audio_service.dart';
import 'websocket_service.dart';

/// Incident business logic service.
/// Manages the full lifecycle of an incident from creation through resolution.
class IncidentService extends ChangeNotifier {
  final ApiClient _apiClient;
  final LocationService _locationService;
  final AudioService _audioService;
  final WebSocketService _webSocketService;

  Incident? _activeIncident;
  Timer? _countdownTimer;
  int _countdownRemaining = 0;
  bool _isLoading = false;

  /// Whether the device is in coercion mode: UI shows "cancelled" but
  /// location/audio/websocket remain active in the background.
  /// This flag is NEVER sent to the backend — it only controls local UI.
  bool _isCoercionMode = false;

  IncidentService({
    required ApiClient apiClient,
    required LocationService locationService,
    required AudioService audioService,
    required WebSocketService webSocketService,
  })  : _apiClient = apiClient,
        _locationService = locationService,
        _audioService = audioService,
        _webSocketService = webSocketService {
    // Listen for real-time incident updates.
    _webSocketService.incidentUpdates.listen(_onIncidentUpdate);
  }

  Incident? get activeIncident => _activeIncident;
  int get countdownRemaining => _countdownRemaining;
  bool get isLoading => _isLoading;
  bool get hasActiveIncident => _activeIncident != null;
  bool get isCountingDown => _countdownTimer?.isActive ?? false;
  bool get isCoercionMode => _isCoercionMode;

  /// Create a new incident.
  Future<Incident> createIncident({
    required TriggerType triggerType,
    bool isCoercion = false,
    bool isTestMode = false,
    LocationUpdate? location,
    int? countdownSeconds,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final data = <String, dynamic>{
        'triggerType': triggerType.apiValue,
        'isCoercion': isCoercion,
        'isTestMode': isTestMode,
      };

      if (location != null) {
        data['location'] = {
          'latitude': location.latitude,
          'longitude': location.longitude,
          if (location.accuracy != null) 'accuracy': location.accuracy,
          if (location.speed != null) 'speed': location.speed,
          if (location.heading != null) 'heading': location.heading,
          if (location.altitude != null) 'altitude': location.altitude,
          if (location.provider != null) 'provider': location.provider,
        };
      }

      if (countdownSeconds != null) {
        data['countdownSeconds'] = countdownSeconds;
      }

      final response = await _apiClient.post(
        ApiEndpoints.incidents,
        data: data,
      );

      final incident =
          Incident.fromJson(response.data as Map<String, dynamic>);
      _activeIncident = incident;

      // Start real-time subscription.
      _webSocketService.joinIncident(incident.id);

      // Start countdown if applicable.
      if (incident.status == IncidentStatus.countdown &&
          incident.countdownEndsAt != null) {
        _startCountdown(incident.countdownEndsAt!);
      }

      // Start location tracking for this incident.
      await _locationService.startTracking(incidentId: incident.id);

      return incident;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Activate an incident after countdown expires.
  Future<Incident> activateIncident(String incidentId) async {
    final response = await _apiClient.post(
      ApiEndpoints.activateIncident(incidentId),
    );

    final incident =
        Incident.fromJson(response.data as Map<String, dynamic>);
    _activeIncident = incident;

    // Start audio recording if consent allows.
    await _audioService.startRecording(incidentId: incidentId);

    notifyListeners();
    return incident;
  }

  /// Cancel an incident (normal cancellation).
  /// Stops all tracking, audio, and websocket.
  Future<void> cancelIncident(String incidentId, {String? reason}) async {
    _countdownTimer?.cancel();

    await _apiClient.post(
      ApiEndpoints.cancelIncident(incidentId),
      data: {
        'isSecretCancel': false,
        if (reason != null) 'reason': reason,
      },
    );

    await _cleanupActiveIncident(incidentId);
  }

  /// Secret cancel — COERCION MODE.
  ///
  /// SAFETY-CRITICAL BEHAVIOR:
  /// 1. Sends `isSecretCancel: true` to the backend.
  /// 2. The backend returns a FAKE "cancelled" response but internally
  ///    escalates the incident to ESCALATED + CRITICAL risk.
  /// 3. On this device, we MUST NOT stop location tracking, audio recording,
  ///    or websocket updates. The emergency remains fully active.
  /// 4. We only set a local flag so the UI can display a fake "cancelled" screen.
  /// 5. The active incident remains in memory so services keep running.
  ///
  /// The attacker sees: "Alert cancelled" screen, no recording indicators.
  /// The backend sees: ESCALATED incident, location/audio streaming in.
  /// The contacts see: Active emergency with live updates.
  Future<void> secretCancelIncident(String incidentId) async {
    _countdownTimer?.cancel();

    await _apiClient.post(
      ApiEndpoints.cancelIncident(incidentId),
      data: {
        'isSecretCancel': true,
        'reason': 'User cancelled',
      },
    );

    // DO NOT call _cleanupActiveIncident.
    // DO NOT stop location tracking.
    // DO NOT stop audio recording.
    // DO NOT leave the websocket room.
    // DO NOT null out _activeIncident.
    //
    // Only set the coercion flag so the UI shows a fake cancelled state.
    _isCoercionMode = true;
    notifyListeners();
  }

  /// Resolve an active incident. This is a GENUINE end — stops everything.
  Future<void> resolveIncident(
    String incidentId, {
    String? reason,
    bool isFalseAlarm = false,
  }) async {
    await _apiClient.post(
      ApiEndpoints.resolveIncident(incidentId),
      data: {
        if (reason != null) 'reason': reason,
        'isFalseAlarm': isFalseAlarm,
      },
    );

    _isCoercionMode = false;
    await _cleanupActiveIncident(incidentId);
  }

  /// Send a risk signal for processing by the risk engine.
  Future<void> sendRiskSignal(
    String incidentId, {
    required String type,
    Map<String, dynamic>? payload,
  }) async {
    await _apiClient.post(
      ApiEndpoints.incidentSignal(incidentId),
      data: {
        'type': type,
        if (payload != null) 'payload': payload,
      },
    );
  }

  /// Add an event to the incident timeline.
  Future<void> addEvent(
    String incidentId, {
    required String type,
    Map<String, dynamic>? payload,
    String? source,
  }) async {
    await _apiClient.post(
      ApiEndpoints.incidentEvents(incidentId),
      data: {
        'type': type,
        if (payload != null) 'payload': payload,
        if (source != null) 'source': source,
      },
    );
  }

  /// Get a single incident by ID.
  Future<Incident> getIncident(String incidentId) async {
    final response = await _apiClient.get(
      ApiEndpoints.incident(incidentId),
    );
    return Incident.fromJson(response.data as Map<String, dynamic>);
  }

  /// List incidents with optional filters.
  Future<List<Incident>> getIncidentHistory({
    int page = 1,
    int limit = 20,
    IncidentStatus? status,
    TriggerType? triggerType,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (status != null) queryParams['status'] = status.apiValue;
    if (triggerType != null) queryParams['triggerType'] = triggerType.apiValue;

    final response = await _apiClient.get(
      ApiEndpoints.incidents,
      queryParameters: queryParams,
    );

    final data = response.data;
    if (data is Map && data['data'] is List) {
      return (data['data'] as List)
          .map((e) => Incident.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (data is List) {
      return data
          .map((e) => Incident.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  /// Get the timeline for an incident.
  Future<List<TimelineEvent>> getTimeline(String incidentId) async {
    final response = await _apiClient.get(
      ApiEndpoints.incidentTimeline(incidentId),
    );

    final data = response.data;
    if (data is List) {
      return data
          .map((e) => TimelineEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    return [];
  }

  // ── Private helpers ─────────────────────────────

  void _startCountdown(DateTime endsAt) {
    _countdownTimer?.cancel();

    _countdownRemaining = endsAt.difference(DateTime.now()).inSeconds;
    if (_countdownRemaining <= 0) {
      // Countdown already expired.
      if (_activeIncident != null) {
        activateIncident(_activeIncident!.id);
      }
      return;
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdownRemaining--;
      notifyListeners();

      if (_countdownRemaining <= 0) {
        timer.cancel();
        // Auto-activate when countdown reaches zero.
        if (_activeIncident != null) {
          activateIncident(_activeIncident!.id);
        }
      }
    });
  }

  /// Full cleanup: stop all tracking, leave websocket, clear state.
  /// Called on normal cancel, resolve, and false alarm — NEVER on coercion.
  Future<void> _cleanupActiveIncident(String incidentId) async {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _countdownRemaining = 0;

    await _locationService.stopTracking();
    await _audioService.stopRecording();
    _webSocketService.leaveIncident(incidentId);

    _activeIncident = null;
    _isCoercionMode = false;
    notifyListeners();
  }

  void _onIncidentUpdate(Map<String, dynamic> data) {
    if (_activeIncident == null) return;

    final incidentId = data['incidentId'] as String?;
    if (incidentId != _activeIncident!.id) return;

    // Re-fetch the incident to get full updated state.
    getIncident(incidentId!).then((incident) {
      _activeIncident = incident;
      notifyListeners();
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
