import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _coercionPinKey = 'coercion_pin_hash';
  static const _fcmTokenKey = 'fcm_token';
  static const _onboardingCompleteKey = 'onboarding_complete';
  static const _activationWordKey = 'activation_word';

  final FlutterSecureStorage _storage;

  SecureStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  // -- Access Token --

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<void> setAccessToken(String token) =>
      _storage.write(key: _accessTokenKey, value: token);

  Future<void> deleteAccessToken() => _storage.delete(key: _accessTokenKey);

  // -- Refresh Token --

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> setRefreshToken(String token) =>
      _storage.write(key: _refreshTokenKey, value: token);

  Future<void> deleteRefreshToken() => _storage.delete(key: _refreshTokenKey);

  // -- User ID --

  Future<String?> getUserId() => _storage.read(key: _userIdKey);

  Future<void> setUserId(String id) =>
      _storage.write(key: _userIdKey, value: id);

  Future<void> deleteUserId() => _storage.delete(key: _userIdKey);

  // -- Coercion PIN --

  Future<String?> getCoercionPinHash() =>
      _storage.read(key: _coercionPinKey);

  Future<void> setCoercionPinHash(String hash) =>
      _storage.write(key: _coercionPinKey, value: hash);

  Future<void> deleteCoercionPinHash() =>
      _storage.delete(key: _coercionPinKey);

  // -- FCM Token --

  Future<String?> getFcmToken() => _storage.read(key: _fcmTokenKey);

  Future<void> setFcmToken(String token) =>
      _storage.write(key: _fcmTokenKey, value: token);

  // -- Onboarding (per-user) --

  /// Check if onboarding is complete for a specific user.
  /// If [userId] is null, falls back to the generic key (legacy).
  Future<bool> isOnboardingComplete({String? userId}) async {
    if (userId != null) {
      final value =
          await _storage.read(key: '${_onboardingCompleteKey}_$userId');
      return value == 'true';
    }
    // Legacy fallback (generic key)
    final value = await _storage.read(key: _onboardingCompleteKey);
    return value == 'true';
  }

  /// Mark onboarding as complete for a specific user.
  Future<void> setOnboardingComplete({String? userId}) async {
    if (userId != null) {
      await _storage.write(
          key: '${_onboardingCompleteKey}_$userId', value: 'true');
    }
    // Also set generic key for legacy compatibility
    await _storage.write(key: _onboardingCompleteKey, value: 'true');
  }

  // -- Activation Word --

  Future<String?> getActivationWord() =>
      _storage.read(key: _activationWordKey);

  Future<void> setActivationWord(String word) =>
      _storage.write(key: _activationWordKey, value: word);

  // -- Generic --

  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> delete(String key) => _storage.delete(key: key);

  /// Clear all stored credentials (used on logout).
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
