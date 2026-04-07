import 'package:flutter/foundation.dart' show kIsWeb;
import 'env.dart';

class AppConfig {
  final Environment environment;
  final String apiBaseUrl;
  final String wsUrl;
  final String mapboxToken;

  const AppConfig._({
    required this.environment,
    required this.apiBaseUrl,
    required this.wsUrl,
    required this.mapboxToken,
  });

  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  static void initialize(Environment env) {
    switch (env) {
      case Environment.dev:
        // On web (Chrome), use localhost directly.
        // On Android emulator, use 10.0.2.2 (special alias for host machine).
        final host = kIsWeb ? 'localhost' : '10.0.2.2';
        _instance = AppConfig._(
          environment: Environment.dev,
          apiBaseUrl: 'http://$host:3000/api/v1',
          wsUrl: 'ws://$host:3000',
          mapboxToken: 'YOUR_DEV_MAPBOX_TOKEN',
        );
        break;
      case Environment.staging:
        _instance = const AppConfig._(
          environment: Environment.staging,
          apiBaseUrl: 'https://staging-api.safecircle.app/api',
          wsUrl: 'wss://staging-api.safecircle.app',
          mapboxToken: 'YOUR_STAGING_MAPBOX_TOKEN',
        );
        break;
      case Environment.prod:
        _instance = const AppConfig._(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.safecircle.app/api',
          wsUrl: 'wss://api.safecircle.app',
          mapboxToken: 'YOUR_PROD_MAPBOX_TOKEN',
        );
        break;
    }
  }

  /// Convenience accessors
  String get authBaseUrl => '$apiBaseUrl/auth';
  String get incidentsBaseUrl => '$apiBaseUrl/incidents';
  String get contactsBaseUrl => '$apiBaseUrl/contacts';
  String get settingsBaseUrl => '$apiBaseUrl/settings';
  String get wsIncidentsUrl => '$wsUrl/incidents';
}
