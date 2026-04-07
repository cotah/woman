import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../storage/secure_storage.dart';

/// Local notification setup and FCM token management.
class NotificationService extends ChangeNotifier {
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final SecureStorage _secureStorage;

  bool _initialized = false;
  String? _fcmToken;

  NotificationService({required SecureStorage secureStorage})
      : _secureStorage = secureStorage;

  bool get isInitialized => _initialized;
  String? get fcmToken => _fcmToken;

  /// Initialize local notifications plugin.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels for Android.
    await _createNotificationChannels();

    _initialized = true;
    notifyListeners();
  }

  /// Store the FCM token for push notification registration.
  Future<void> setFcmToken(String token) async {
    _fcmToken = token;
    await _secureStorage.setFcmToken(token);
    notifyListeners();
  }

  /// Retrieve the stored FCM token.
  Future<String?> getFcmToken() async {
    _fcmToken ??= await _secureStorage.getFcmToken();
    return _fcmToken;
  }

  /// Show a local notification for an emergency alert.
  Future<void> showEmergencyNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'emergency_channel',
        'Emergency Alerts',
        channelDescription: 'Critical safety alerts',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.alarm,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    );

    await _localNotifications.show(
      0, // Emergency notifications use ID 0
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Show a general notification.
  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'general_channel',
        'General',
        channelDescription: 'General app notifications',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(id, title, body, details, payload: payload);
  }

  /// Show a silent/ongoing notification (for background tracking).
  Future<void> showTrackingNotification({
    required String body,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'tracking_channel',
        'Location Tracking',
        channelDescription: 'Active location tracking indicator',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      ),
    );

    await _localNotifications.show(
      1, // Tracking notifications use ID 1
      'SafeCircle',
      body,
      details,
    );
  }

  /// Cancel the tracking notification.
  Future<void> cancelTrackingNotification() async {
    await _localNotifications.cancel(1);
  }

  /// Cancel all notifications.
  Future<void> cancelAll() async {
    await _localNotifications.cancelAll();
  }

  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'emergency_channel',
          'Emergency Alerts',
          description: 'Critical safety alerts',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'general_channel',
          'General',
          description: 'General app notifications',
          importance: Importance.defaultImportance,
        ),
      );

      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'tracking_channel',
          'Location Tracking',
          description: 'Active location tracking indicator',
          importance: Importance.low,
        ),
      );
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint(
        '[NotificationService] Notification tapped: ${response.payload}');
    // Navigation handling is done at the app level via callback or stream.
  }
}
