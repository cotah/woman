import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_service.dart';
import '../auth/auth_state.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/contacts/contacts_screen.dart';
import '../../features/contacts/add_contact_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/emergency_settings_screen.dart';
import '../../features/settings/coercion_pin_screen.dart';
import '../../features/settings/audio_settings_screen.dart';
import '../../features/settings/privacy_screen.dart';
import '../../features/emergency/emergency_screen.dart';
import '../../features/incidents/incident_history_screen.dart';
import '../../features/incidents/incident_detail_screen.dart';
import '../../features/test_mode/test_mode_screen.dart';
import '../../features/help/help_screen.dart';
import '../../features/help/disclaimer_screen.dart';
import '../../features/journey/journey_screen.dart';
import '../../features/journey/active_journey_screen.dart';
import '../../features/diagnostics/system_readiness_screen.dart';

/// Builds the application router with auth-based redirects.
///
/// Uses the existing [AuthService] and [AuthState] from core/auth.
GoRouter buildRouter(AuthService authService) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: authService,
    redirect: (context, state) {
      final authState = authService.state;
      final path = state.uri.path;

      // While loading / initial, stay on splash
      if (authState.status == AuthStatus.initial ||
          authState.status == AuthStatus.loading) {
        return path == '/splash' ? null : '/splash';
      }

      // Not authenticated -> login (unless already on auth routes)
      final authPaths = ['/auth/login', '/auth/register', '/disclaimer'];
      if (!authState.isAuthenticated) {
        return authPaths.contains(path) ? null : '/auth/login';
      }

      // Authenticated but on auth/splash -> go home
      if (path == '/splash' || path.startsWith('/auth/')) {
        return '/home';
      }

      return null;
    },
    routes: [
      // Splash
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),

      // Auth
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Onboarding
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Dashboard (home)
      GoRoute(
        path: '/home',
        builder: (context, state) => const DashboardScreen(),
      ),

      // Contacts
      GoRoute(
        path: '/contacts',
        builder: (context, state) => const ContactsScreen(),
      ),
      GoRoute(
        path: '/contacts/add',
        builder: (context, state) => const AddContactScreen(),
      ),
      GoRoute(
        path: '/contacts/edit/:id',
        builder: (context, state) => AddContactScreen(
          contactId: state.pathParameters['id'],
        ),
      ),

      // Settings
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/settings/emergency',
        builder: (context, state) => const EmergencySettingsScreen(),
      ),
      GoRoute(
        path: '/settings/coercion-pin',
        builder: (context, state) => const CoercionPinScreen(),
      ),
      GoRoute(
        path: '/settings/audio',
        builder: (context, state) => const AudioSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        builder: (context, state) => const PrivacyScreen(),
      ),

      // Emergency
      GoRoute(
        path: '/emergency',
        builder: (context, state) => const EmergencyScreen(),
      ),

      // Incidents
      GoRoute(
        path: '/incidents',
        builder: (context, state) => const IncidentHistoryScreen(),
      ),
      GoRoute(
        path: '/incidents/:id',
        builder: (context, state) => IncidentDetailScreen(
          incidentId: state.pathParameters['id']!,
        ),
      ),

      // Test mode
      GoRoute(
        path: '/test-mode',
        builder: (context, state) => const TestModeScreen(),
      ),

      // Journey
      GoRoute(
        path: '/journey',
        builder: (context, state) => const JourneyScreen(),
      ),
      GoRoute(
        path: '/journey/active',
        builder: (context, state) => const ActiveJourneyScreen(),
      ),

      // Diagnostics (pilot testing)
      GoRoute(
        path: '/diagnostics',
        builder: (context, state) => const SystemReadinessScreen(),
      ),

      // Help
      GoRoute(
        path: '/help',
        builder: (context, state) => const HelpScreen(),
      ),
      GoRoute(
        path: '/disclaimer',
        builder: (context, state) => const DisclaimerScreen(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              'Page not found',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('Return to home'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Simple splash screen shown during auth state initialization.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield, size: 80, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'SafeCircle',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 32),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
