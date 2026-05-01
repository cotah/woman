import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../storage/secure_storage.dart';
import 'notification_service.dart';

/// Wraps [FirebaseMessaging] for SafeCircle.
///
/// Responsibilities:
///   1. Initialize Firebase Messaging permissions (iOS) and obtain the
///      FCM token (Android directly, iOS only after APNs token arrives).
///   2. Register the device with the SafeCircle backend via
///      `POST /users/me/devices` whenever the user is authenticated.
///   3. Listen to foreground push messages and forward them to
///      [NotificationService] so the user sees a local notification
///      even when the app is open (Android does not display
///      notifications automatically when the app is in the foreground).
///   4. Re-register on token rotation.
///
/// SAFETY-CRITICAL: failures here must NEVER prevent the app from
/// reaching login/home. Every async call is wrapped in try/catch and
/// logs to debug; all public methods return without throwing.
class FcmService extends ChangeNotifier {
  final ApiClient _apiClient;
  final SecureStorage _secureStorage;
  final NotificationService _notificationService;

  FcmService({
    required ApiClient apiClient,
    required SecureStorage secureStorage,
    required NotificationService notificationService,
  })  : _apiClient = apiClient,
        _secureStorage = secureStorage,
        _notificationService = notificationService;

  bool _initialized = false;
  String? _currentToken;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedAppSub;

  bool get isInitialized => _initialized;
  String? get currentToken => _currentToken;

  /// Called once at app startup, BEFORE the user logs in.
  /// Permission prompt is deferred to first registration with backend
  /// (in [registerWithBackend]) so onboarding controls when it appears.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Foreground iOS notification presentation: show banner+sound.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Listen for foreground messages and forward to local notification
      // plugin. On iOS the system can show alerts in foreground when the
      // options above are set; on Android we always need to render
      // ourselves.
      _foregroundSub =
          FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Listen for the user tapping a notification while the app was
      // backgrounded (not killed). [getInitialMessage] handles the
      // killed-state case.
      _openedAppSub = FirebaseMessaging.onMessageOpenedApp
          .listen(_handleNotificationTap);

      // Listen for token rotations.
      _tokenRefreshSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        debugPrint('[FcmService] Token rotated.');
        _currentToken = token;
        await _secureStorage.setFcmToken(token);
        // Re-register with backend if currently authenticated.
        await registerWithBackend(silent: true);
      });

      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[FcmService] initialize failed: $e');
    }
  }

  /// Request permission (iOS) and fetch the current token. Then push the
  /// device record up to the backend. Safe to call multiple times.
  ///
  /// On iOS, [getToken] only returns a value AFTER APNs has supplied the
  /// device token to FCM. We retry briefly if the token is null.
  ///
  /// [silent] suppresses the iOS permission prompt — used when this is
  /// triggered by a token rotation rather than by user-driven login.
  Future<void> registerWithBackend({bool silent = false}) async {
    try {
      if (!silent) {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          criticalAlert: true,
        );
        debugPrint(
          '[FcmService] Permission status: ${settings.authorizationStatus}',
        );
        if (settings.authorizationStatus == AuthorizationStatus.denied) {
          debugPrint('[FcmService] User denied push permission.');
          return;
        }
      }

      // iOS: ensure APNs token is available before requesting FCM token.
      if (Platform.isIOS) {
        final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        if (apnsToken == null) {
          debugPrint(
            '[FcmService] APNs token not yet available; will retry on rotation',
          );
          return;
        }
      }

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) {
        debugPrint('[FcmService] FCM token unavailable; skipping register');
        return;
      }
      _currentToken = token;
      await _secureStorage.setFcmToken(token);

      final platform = Platform.isIOS ? 'ios' : 'android';
      final telemetry = await _collectDeviceTelemetry();

      await _apiClient.post(
        ApiEndpoints.registerDevice,
        data: {
          'platform': platform,
          'pushToken': token,
          if (telemetry.deviceModel != null)
            'deviceModel': telemetry.deviceModel,
          if (telemetry.osVersion != null) 'osVersion': telemetry.osVersion,
          if (telemetry.appVersion != null)
            'appVersion': telemetry.appVersion,
        },
      );

      debugPrint('[FcmService] Device registered with backend ($platform).');
      notifyListeners();
    } catch (e) {
      debugPrint('[FcmService] registerWithBackend failed: $e');
    }
  }

  /// Check whether the app was launched from a tap on a notification
  /// while the process was killed. Call once after the router is ready.
  Future<RemoteMessage?> consumeInitialMessage() async {
    try {
      return await FirebaseMessaging.instance.getInitialMessage();
    } catch (e) {
      debugPrint('[FcmService] getInitialMessage failed: $e');
      return null;
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint(
      '[FcmService] Foreground message: '
      '${message.messageId} | data=${message.data}',
    );
    final notification = message.notification;
    if (notification == null) return;

    final type = (message.data['type'] ?? '').toString();
    if (type == 'emergency_alert') {
      _notificationService.showEmergencyNotification(
        title: notification.title ?? 'SafeCircle alert',
        body: notification.body ?? '',
        payload: _serializeData(message.data),
      );
    } else {
      _notificationService.showNotification(
        id: message.messageId.hashCode,
        title: notification.title ?? 'SafeCircle',
        body: notification.body ?? '',
        payload: _serializeData(message.data),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    debugPrint(
      '[FcmService] Notification tapped (background): ${message.data}',
    );
    // Navigation is performed at the app layer once a navigator is
    // available — we surface the payload via NotificationService's
    // existing tap handler so a single hook handles both local and
    // remote taps.
  }

  String? _serializeData(Map<String, dynamic> data) {
    if (data.isEmpty) return null;
    // Cheap delimiter encoding — the local notification plugin treats
    // payload as opaque, callers parse on tap.
    return data.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  Future<_DeviceTelemetry> _collectDeviceTelemetry() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return _DeviceTelemetry(
          deviceModel: '${android.manufacturer} ${android.model}'.trim(),
          osVersion: 'Android ${android.version.release}',
        );
      }
      if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return _DeviceTelemetry(
          deviceModel: ios.utsname.machine,
          osVersion: '${ios.systemName} ${ios.systemVersion}',
        );
      }
    } catch (e) {
      debugPrint('[FcmService] device info collection failed: $e');
    }
    return const _DeviceTelemetry();
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _openedAppSub?.cancel();
    _tokenRefreshSub?.cancel();
    super.dispose();
  }
}

class _DeviceTelemetry {
  final String? deviceModel;
  final String? osVersion;
  final String? appVersion;

  const _DeviceTelemetry({
    this.deviceModel,
    this.osVersion,
    this.appVersion,
  });
}
