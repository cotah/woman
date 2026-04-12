import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/config/app_config.dart';
import 'core/config/env.dart';
import 'core/config/router.dart';
import 'core/api/api_client.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/auth_state.dart';
import 'core/services/audio_service.dart';
import 'core/services/contacts_service.dart';
import 'core/services/incident_service.dart';
import 'core/services/location_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/journey_service.dart';
import 'core/services/websocket_service.dart';
import 'core/services/offline_queue_service.dart';
import 'core/services/sms_fallback_service.dart';
import 'core/services/background_service.dart';
import 'core/services/location_tracker_service.dart';
import 'core/services/learned_places_service.dart';
import 'core/services/voice_detection_service.dart';
import 'core/storage/secure_storage.dart';
import 'core/models/incident.dart';
import 'core/models/location_update.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_notifier.dart';
import 'core/utils/coercion_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize environment config.
  // Environment is set via --dart-define=ENVIRONMENT=dev|staging|prod
  // Defaults to prod for release safety.
  const envName = String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev');
  final env = switch (envName) {
    'dev' => Environment.dev,
    'staging' => Environment.staging,
    _ => Environment.prod,
  };
  AppConfig.initialize(env);

  // Core singletons.
  final secureStorage = SecureStorage();
  final apiClient = ApiClient(secureStorage: secureStorage);

  runApp(SafeCircleApp(
    secureStorage: secureStorage,
    apiClient: apiClient,
  ));
}

class SafeCircleApp extends StatefulWidget {
  final SecureStorage secureStorage;
  final ApiClient apiClient;

  const SafeCircleApp({
    super.key,
    required this.secureStorage,
    required this.apiClient,
  });

  @override
  State<SafeCircleApp> createState() => _SafeCircleAppState();
}

class _SafeCircleAppState extends State<SafeCircleApp> {
  late final AuthService _authService;
  late final LocationService _locationService;
  late final AudioService _audioService;
  late final WebSocketService _webSocketService;
  late final NotificationService _notificationService;
  late final IncidentService _incidentService;
  late final CoercionHandler _coercionHandler;
  late final JourneyService _journeyService;
  late final SettingsService _settingsService;
  late final ContactsService _contactsService;
  late final OfflineQueueService _offlineQueueService;
  late final SmsFallbackService _smsFallbackService;
  late final BackgroundService _backgroundService;
  late final LocationTrackerService _locationTrackerService;
  late final LearnedPlacesService _learnedPlacesService;
  late final VoiceDetectionService _voiceDetectionService;
  late final ThemeNotifier _themeNotifier;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    // Initialize services.
    _authService = AuthService(
      apiClient: widget.apiClient,
      secureStorage: widget.secureStorage,
    );

    _locationService = LocationService(apiClient: widget.apiClient);
    _audioService = AudioService(apiClient: widget.apiClient);
    _webSocketService =
        WebSocketService(secureStorage: widget.secureStorage);
    _notificationService =
        NotificationService(secureStorage: widget.secureStorage);

    _incidentService = IncidentService(
      apiClient: widget.apiClient,
      locationService: _locationService,
      audioService: _audioService,
      webSocketService: _webSocketService,
    );

    _coercionHandler =
        CoercionHandler(secureStorage: widget.secureStorage);

    _journeyService = JourneyService(
      apiClient: widget.apiClient,
      locationService: _locationService,
    );

    _settingsService = SettingsService(apiClient: widget.apiClient);
    _contactsService = ContactsService(apiClient: widget.apiClient);

    _offlineQueueService = OfflineQueueService();
    _offlineQueueService.initialize();
    _smsFallbackService = SmsFallbackService();
    _backgroundService = BackgroundService();
    _backgroundService.initialize();

    _locationTrackerService = LocationTrackerService(
      apiClient: widget.apiClient,
    );
    _locationTrackerService.initialize();

    _learnedPlacesService = LearnedPlacesService(
      tracker: _locationTrackerService,
    );
    _learnedPlacesService.initialize();

    _voiceDetectionService = VoiceDetectionService(
      secureStorage: widget.secureStorage,
    );
    // Wire voice activation → auto-trigger emergency SOS
    _voiceDetectionService.onActivationDetected = () {
      debugPrint('[Main] Voice activation detected! Triggering SOS...');
      _triggerVoiceEmergency();
    };
    _voiceDetectionService.initialize();

    _themeNotifier = ThemeNotifier();

    // Initialize router with real feature screens.
    _router = buildRouter(_authService, secureStorage: widget.secureStorage);

    // Initialize notifications and attempt auto-login.
    _notificationService.initialize();
    _authService.tryAutoLogin();
  }

  @override
  void dispose() {
    _authService.dispose();
    _locationService.dispose();
    _audioService.dispose();
    _webSocketService.dispose();
    _incidentService.dispose();
    _journeyService.dispose();
    _backgroundService.dispose();
    _locationTrackerService.dispose();
    _learnedPlacesService.dispose();
    _voiceDetectionService.dispose();
    super.dispose();
  }

  /// Triggered when the voice detection service recognizes the activation word.
  /// Creates and immediately activates an emergency incident.
  Future<void> _triggerVoiceEmergency() async {
    try {
      // Get current location for the incident
      LocationUpdate? location;
      if (_locationTrackerService.lastPosition != null) {
        final pos = _locationTrackerService.lastPosition!;
        location = LocationUpdate(
          latitude: pos.latitude,
          longitude: pos.longitude,
          accuracy: pos.accuracy,
          timestamp: DateTime.now(),
        );
      }

      // Create incident with voice trigger — no countdown, immediate activation
      final incident = await _incidentService.createIncident(
        triggerType: TriggerType.voice,
        countdownSeconds: 0,
        location: location,
      );

      debugPrint('[Main] Voice emergency incident created: ${incident.id}');

      // Immediately activate (no countdown for voice-triggered emergencies)
      if (incident.status == IncidentStatus.countdown ||
          incident.status == IncidentStatus.pending) {
        await _incidentService.activateIncident(incident.id);
        debugPrint('[Main] Voice emergency activated!');
      }
    } catch (e) {
      debugPrint('[Main] Failed to trigger voice emergency: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authService),
        ChangeNotifierProvider.value(value: _locationService),
        ChangeNotifierProvider.value(value: _audioService),
        ChangeNotifierProvider.value(value: _webSocketService),
        ChangeNotifierProvider.value(value: _notificationService),
        ChangeNotifierProvider.value(value: _incidentService),
        ChangeNotifierProvider.value(value: _journeyService),
        ChangeNotifierProvider.value(value: _settingsService),
        ChangeNotifierProvider.value(value: _contactsService),
        ChangeNotifierProvider.value(value: _offlineQueueService),
        ChangeNotifierProvider.value(value: _backgroundService),
        ChangeNotifierProvider.value(value: _locationTrackerService),
        ChangeNotifierProvider.value(value: _learnedPlacesService),
        ChangeNotifierProvider.value(value: _voiceDetectionService),
        Provider.value(value: _smsFallbackService),
        Provider.value(value: widget.apiClient),
        Provider.value(value: widget.secureStorage),
        Provider.value(value: _coercionHandler),
        ChangeNotifierProvider.value(value: _themeNotifier),
      ],
      child: Consumer<ThemeNotifier>(
        builder: (context, themeNotifier, _) {
          return MaterialApp.router(
            title: 'SafeCircle',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeNotifier.themeMode,
            routerConfig: _router,
          );
        },
      ),
    );
  }
}