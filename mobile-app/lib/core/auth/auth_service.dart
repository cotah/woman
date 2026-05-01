import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/user.dart';
import '../storage/secure_storage.dart';
import 'auth_state.dart';

/// Provider-based auth service managing login, register, logout,
/// token storage, auto-refresh, and current user state.
class AuthService extends ChangeNotifier {
  final ApiClient _apiClient;
  final SecureStorage _secureStorage;

  AuthState _state = const AuthState.initial();
  AuthState get state => _state;

  Timer? _refreshTimer;

  /// Duration before token expiry at which we auto-refresh (in minutes).
  static const int _refreshBufferMinutes = 2;

  /// Assumed access token TTL if not provided by backend (in minutes).
  static const int _defaultTokenTtlMinutes = 15;

  /// Callback invoked once on the rising edge of authentication
  /// (unauthenticated → authenticated). Used by [main.dart] to trigger
  /// FCM device registration with the backend after login,
  /// auto-login, and registration. Called from [_setState] so all
  /// success paths fire it consistently.
  ///
  /// Errors raised by the callback are swallowed — the auth flow must
  /// not be derailed by a downstream side effect failure.
  final VoidCallback? onAuthenticated;

  AuthService({
    required ApiClient apiClient,
    required SecureStorage secureStorage,
    this.onAuthenticated,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage;

  /// Attempt to restore a session from stored tokens.
  ///
  /// Wrapped in a 20-second safety timeout so the app never stays on
  /// the splash screen forever — even if the backend is unreachable or
  /// an unexpected error occurs, the user will be sent to the login screen.
  ///
  /// IMPORTANT: The timeout and catch blocks check if the user is already
  /// authenticated before overriding the state. This prevents a race
  /// condition where the user registers/logs in while tryAutoLogin is
  /// still running in the background — the timeout would otherwise
  /// clear their tokens and kick them back to login.
  Future<void> tryAutoLogin() async {
    _setState(const AuthState.loading());

    try {
      await _tryAutoLoginInner().timeout(
        const Duration(seconds: 20),
        onTimeout: () {
          // Only reset if nobody else has authenticated in the meantime
          if (_state.isAuthenticated) return;
          debugPrint('[Auth] Auto-login timed out after 20s — going to login');
          _clearTokens();
          _setState(const AuthState.unauthenticated());
        },
      );
    } catch (e) {
      // Only reset if nobody else has authenticated in the meantime
      if (_state.isAuthenticated) return;
      debugPrint('[Auth] Auto-login unexpected error: $e');
      await _clearTokens();
      _setState(const AuthState.unauthenticated());
    }
  }

  /// Inner implementation of auto-login logic (called by [tryAutoLogin]).
  Future<void> _tryAutoLoginInner() async {
    final accessToken = await _secureStorage.getAccessToken();
    if (accessToken == null) {
      _setState(const AuthState.unauthenticated());
      return;
    }

    try {
      final response = await _apiClient.get(ApiEndpoints.profile);
      final user = User.fromJson(response.data as Map<String, dynamic>);
      _setState(AuthState.authenticated(user));
      _scheduleTokenRefresh();
    } catch (e) {
      // Token might be expired, try refreshing.
      final refreshed = await _apiClient.refreshToken();
      if (refreshed) {
        try {
          final response = await _apiClient.get(ApiEndpoints.profile);
          final user =
              User.fromJson(response.data as Map<String, dynamic>);
          _setState(AuthState.authenticated(user));
          _scheduleTokenRefresh();
          return;
        } catch (_) {}
      }
      await _clearTokens();
      _setState(const AuthState.unauthenticated());
    }
  }

  /// Register a new user.
  ///
  /// Does NOT set global state to 'loading' — the register screen handles
  /// its own loading indicator. Setting loading here would trigger the
  /// router redirect to /splash, breaking the registration flow.
  Future<void> register({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? phone,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiEndpoints.register,
        data: {
          'email': email,
          'password': password,
          'firstName': firstName,
          'lastName': lastName,
          if (phone != null) 'phone': phone,
        },
      );

      final data = response.data as Map<String, dynamic>;
      await _storeTokens(data);

      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      _setState(AuthState.authenticated(user));
      _scheduleTokenRefresh();
    } catch (e) {
      _setState(AuthState.unauthenticated(error: _extractError(e)));
      rethrow;
    }
  }

  /// Login with email and password.
  ///
  /// Does NOT set global state to 'loading' — the login screen handles
  /// its own loading indicator. Setting loading here would trigger the
  /// router redirect to /splash, breaking the login flow.
  Future<void> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _apiClient.post(
        ApiEndpoints.login,
        data: {
          'email': email,
          'password': password,
        },
      );

      final data = response.data as Map<String, dynamic>;
      await _storeTokens(data);

      final user = User.fromJson(data['user'] as Map<String, dynamic>);
      _setState(AuthState.authenticated(user));
      _scheduleTokenRefresh();
    } catch (e) {
      _setState(AuthState.unauthenticated(error: _extractError(e)));
      rethrow;
    }
  }

  /// Logout the current user.
  Future<void> logout() async {
    try {
      final refreshToken = await _secureStorage.getRefreshToken();
      await _apiClient.post(
        ApiEndpoints.logout,
        data: {
          if (refreshToken != null) 'refreshToken': refreshToken,
        },
      );
    } catch (_) {
      // Best effort - logout locally regardless.
    }

    _refreshTimer?.cancel();
    _refreshTimer = null;
    await _clearTokens();
    _setState(const AuthState.unauthenticated());
  }

  /// Force auth state to unauthenticated without calling backend.
  ///
  /// Used by the splash screen safety timer when auto-login has not
  /// completed within the timeout. This changes the auth state so the
  /// router's redirect naturally sends the user to the login screen.
  ///
  /// Does nothing if the user is already authenticated (prevents
  /// race condition with concurrent register/login).
  void forceUnauthenticated() {
    if (_state.isAuthenticated) return;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _setState(const AuthState.unauthenticated());
  }

  /// Refresh the current user profile from backend.
  Future<void> refreshProfile() async {
    if (!_state.isAuthenticated) return;

    try {
      final response = await _apiClient.get(ApiEndpoints.profile);
      final user = User.fromJson(response.data as Map<String, dynamic>);
      _setState(AuthState.authenticated(user));
    } catch (_) {
      // Silently fail - keep existing user data.
    }
  }

  // ── Private helpers ─────────────────────────────

  void _setState(AuthState newState) {
    final wasAuthenticated = _state.isAuthenticated;
    _state = newState;
    notifyListeners();

    // Rising edge of authentication: fire the post-login hook exactly
    // once per session. Auto-login, login, and register all funnel
    // through here.
    if (!wasAuthenticated && newState.isAuthenticated) {
      try {
        onAuthenticated?.call();
      } catch (e) {
        debugPrint('[Auth] onAuthenticated callback threw: $e');
      }
    }
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    // Backend returns tokens nested: { tokens: { accessToken, refreshToken } }
    // or flat: { accessToken, refreshToken }. Handle both.
    final tokens = data['tokens'] as Map<String, dynamic>? ?? data;

    if (tokens['accessToken'] != null) {
      await _secureStorage.setAccessToken(tokens['accessToken'] as String);
    }
    if (tokens['refreshToken'] != null) {
      await _secureStorage.setRefreshToken(tokens['refreshToken'] as String);
    }
    if (data['user'] != null) {
      final user = data['user'] as Map<String, dynamic>;
      if (user['id'] != null) {
        await _secureStorage.setUserId(user['id'] as String);
      }
    }
  }

  Future<void> _clearTokens() async {
    await _secureStorage.deleteAccessToken();
    await _secureStorage.deleteRefreshToken();
    await _secureStorage.deleteUserId();
  }

  void _scheduleTokenRefresh() {
    _refreshTimer?.cancel();
    final delay = Duration(
      minutes: _defaultTokenTtlMinutes - _refreshBufferMinutes,
    );
    _refreshTimer = Timer(delay, () async {
      final success = await _apiClient.refreshToken();
      if (success) {
        _scheduleTokenRefresh();
      } else {
        await logout();
      }
    });
  }

  String _extractError(dynamic error) {
    if (error is Exception) {
      return error.toString();
    }
    return 'An unexpected error occurred';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
