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
    this.mapboxToken = '',
  });

  /// Mapbox token injected at build time via --dart-define=MAPBOX_TOKEN=...
  static const String _buildMapboxToken = String.fromEnvironment('MAPBOX_TOKEN');

  static late final AppConfig _instance;
  static AppConfig get instance => _instance;

  static void initialize(Environment env) {
    // On web, auto-detect environment from the browser URL.
    // This overrides the dart-define value so deploys always work correctly.
    if (kIsWeb) {
      final host = Uri.base.host;
      if (host == 'localhost' || host == '127.0.0.1') {
        env = Environment.dev;
      } else if (host.contains('railway.app')) {
        env = Environment.staging;
      } else {
        env = Environment.prod;
      }
    }

    switch (env) {
      case Environment.dev:
        // On web (Chrome), use localhost directly.
        // On Android emulator, use 10.0.2.2 (special alias for host machine).
        final host = kIsWeb ? 'localhost' : '10.0.2.2';
        _instance = AppConfig._(
          environment: Environment.dev,
          apiBaseUrl: 'http://$host:3000/api/v1',
          wsUrl: 'ws://$host:3000',
          mapboxToken: _buildMapboxToken,
        );
        break;
      case Environment.staging:
        _instance = AppConfig._(
          environment: Environment.staging,
          apiBaseUrl: 'https://perfect-expression-production-0290.up.railway.app/api/v1',
          wsUrl: 'wss://perfect-expression-production-0290.up.railway.app',
          mapboxToken: _buildMapboxToken,
        );
        break;
      case Environment.prod:
        _instance = AppConfig._(
          environment: Environment.prod,
          apiBaseUrl: 'https://api.safecircle.app/api/v1',
          wsUrl: 'wss://api.safecircle.app',
          mapboxToken: _buildMapboxToken,
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
