import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../storage/secure_storage.dart';
import 'api_endpoints.dart';

/// Dio-based HTTP client with JWT auth, auto-refresh on 401, and retry logic.
class ApiClient {
  late final Dio dio;
  final SecureStorage _secureStorage;

  /// Prevents concurrent token refreshes.
  Completer<bool>? _refreshCompleter;

  /// Maximum number of retries for failed requests (network errors).
  static const int _maxRetries = 2;

  ApiClient({required SecureStorage secureStorage})
      : _secureStorage = secureStorage {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.instance.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.addAll([
      _AuthInterceptor(this),
      if (kDebugMode) _LoggingInterceptor(),
    ]);
  }

  // ── Token management (called by interceptor) ──

  Future<String?> getAccessToken() => _secureStorage.getAccessToken();

  Future<bool> refreshToken() async {
    // If a refresh is already in progress, wait for it.
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _secureStorage.getRefreshToken();
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      // Use a separate Dio instance to avoid interceptor loops.
      // Must include timeouts — without them a request to an unreachable
      // host (e.g. the non-existent prod domain) hangs forever and the
      // app stays on the splash screen indefinitely.
      final refreshDio = Dio(BaseOptions(
        baseUrl: AppConfig.instance.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ));

      final response = await refreshDio.post(
        ApiEndpoints.refresh,
        data: {'refreshToken': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        await _secureStorage.setAccessToken(data['accessToken']);
        if (data['refreshToken'] != null) {
          await _secureStorage.setRefreshToken(data['refreshToken']);
        }
        _refreshCompleter!.complete(true);
        return true;
      }

      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  // ── Convenience methods ───────────────────────

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      dio.get<T>(path, queryParameters: queryParameters, options: options);

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) =>
      dio.post<T>(path,
          data: data, queryParameters: queryParameters, options: options);

  Future<Response<T>> patch<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      dio.patch<T>(path, data: data, options: options);

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Options? options,
  }) =>
      dio.delete<T>(path, data: data, options: options);

  Future<Response<T>> upload<T>(
    String path, {
    required FormData data,
    Map<String, dynamic>? queryParameters,
    void Function(int, int)? onSendProgress,
  }) =>
      dio.post<T>(
        path,
        data: data,
        queryParameters: queryParameters,
        onSendProgress: onSendProgress,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(seconds: 60),
        ),
      );
}

// ── Auth Interceptor ──────────────────────────────

class _AuthInterceptor extends Interceptor {
  final ApiClient _client;

  _AuthInterceptor(this._client);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Skip auth for public endpoints.
    final publicPaths = [
      ApiEndpoints.login,
      ApiEndpoints.register,
      ApiEndpoints.refresh,
    ];
    if (publicPaths.any((p) => options.path.contains(p))) {
      return handler.next(options);
    }

    final token = await _client.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }

    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401 &&
        !err.requestOptions.path.contains(ApiEndpoints.refresh)) {
      final success = await _client.refreshToken();
      if (success) {
        // Retry the original request with the new token.
        final token = await _client.getAccessToken();
        err.requestOptions.headers['Authorization'] = 'Bearer $token';

        try {
          final response = await _client.dio.fetch(err.requestOptions);
          return handler.resolve(response);
        } catch (retryError) {
          return handler.next(retryError as DioException);
        }
      }
    }

    // Retry on network errors.
    final retryCount =
        err.requestOptions.extra['retryCount'] as int? ?? 0;
    if (_isRetryable(err) && retryCount < ApiClient._maxRetries) {
      err.requestOptions.extra['retryCount'] = retryCount + 1;

      await Future.delayed(
          Duration(milliseconds: 500 * (retryCount + 1)));

      try {
        final response = await _client.dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (retryError) {
        return handler.next(retryError as DioException);
      }
    }

    handler.next(err);
  }

  bool _isRetryable(DioException err) {
    return err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError;
  }
}

// ── Debug Logging Interceptor ─────────────────────

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[API] --> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint(
        '[API] <-- ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
        '[API] <!! ${err.response?.statusCode ?? 'NO_STATUS'} ${err.requestOptions.path}: ${err.message}');
    handler.next(err);
  }
}
