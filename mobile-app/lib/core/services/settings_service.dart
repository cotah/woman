import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/emergency_settings.dart';

/// Service for managing emergency settings persistence.
/// Syncs settings between the mobile app and backend.
class SettingsService extends ChangeNotifier {
  final ApiClient _apiClient;

  EmergencySettings? _settings;
  bool _isLoading = false;

  SettingsService({required ApiClient apiClient}) : _apiClient = apiClient;

  EmergencySettings? get settings => _settings;
  bool get isLoading => _isLoading;

  /// Load settings from the backend. Auto-creates if not found.
  Future<EmergencySettings> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.get(ApiEndpoints.emergencySettings);
      _settings =
          EmergencySettings.fromJson(response.data as Map<String, dynamic>);
      return _settings!;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update one or more settings fields.
  Future<EmergencySettings> updateSettings(
      Map<String, dynamic> updates) async {
    final response = await _apiClient.patch(
      ApiEndpoints.emergencySettings,
      data: updates,
    );

    _settings =
        EmergencySettings.fromJson(response.data as Map<String, dynamic>);
    notifyListeners();
    return _settings!;
  }

  /// Set the coercion PIN on the backend (hashed server-side).
  Future<void> setCoercionPin(String pin) async {
    await _apiClient.post(
      ApiEndpoints.coercionPin,
      data: {'pin': pin},
    );
  }

  /// Update countdown duration.
  Future<void> updateCountdownDuration(int seconds) async {
    await updateSettings({'countdownDurationSeconds': seconds});
  }

  /// Update audio consent level.
  Future<void> updateAudioConsent(String consentLevel) async {
    await updateSettings({'audioConsent': consentLevel});
  }

  /// Update auto-record setting.
  Future<void> updateAutoRecord(bool enabled) async {
    await updateSettings({'autoRecordAudio': enabled});
  }

  /// Update AI analysis consent.
  Future<void> updateAiAnalysis(bool enabled) async {
    await updateSettings({'allowAiAnalysis': enabled});
  }

  /// Update audio sharing with contacts.
  Future<void> updateAudioSharing(bool enabled) async {
    await updateSettings({'shareAudioWithContacts': enabled});
  }
}
