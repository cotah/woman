import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/audio_service.dart';
import '../../core/services/incident_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/incident.dart';

/// Main dashboard screen with:
/// - Large emergency button (center)
/// - Status bar (safe / monitoring)
/// - Quick access to contacts, settings, history, safe journey
/// - Test mode toggle
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isTestMode = false;
  bool _isTriggering = false;

  bool get _isMonitoring {
    final incidentService = context.read<IncidentService>();
    return incidentService.hasActiveIncident;
  }

  Future<void> _triggerEmergency() async {
    if (_isTriggering) return;

    HapticFeedback.heavyImpact();

    if (_isTestMode) {
      context.push('/test-mode');
      return;
    }

    setState(() => _isTriggering = true);

    try {
      final locationService = context.read<LocationService>();
      final incidentService = context.read<IncidentService>();
      final settingsService = context.read<SettingsService>();
      final audioService = context.read<AudioService>();

      // Load settings to enforce audio consent and countdown duration.
      try {
        final settings = await settingsService.loadSettings();
        audioService.updateConsentLevel(settings.audioConsent);
      } catch (_) {
        // Non-fatal: proceed with default consent (none).
      }

      // Get current location for the incident.
      final location = await locationService.getCurrentLocation();

      // Create the incident on backend.
      await incidentService.createIncident(
        triggerType: TriggerType.manualButton,
        isTestMode: false,
        location: location,
      );

      if (mounted) {
        context.push('/emergency');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create alert: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: SafeArea(
        child: Consumer<IncidentService>(
          builder: (context, incidentService, _) {
            final isMonitoring = incidentService.hasActiveIncident;

            return Column(
              children: [
                // Top bar
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Text(
                        'SafeCircle',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => context.push('/help'),
                        icon: const Icon(Icons.help_outline),
                        tooltip: 'Help',
                      ),
                      IconButton(
                        onPressed: () => context.push('/settings'),
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: 'Settings',
                      ),
                    ],
                  ),
                ),

                // Status bar
                _StatusBar(isMonitoring: isMonitoring),

                // Test mode indicator
                if (_isTestMode)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    color: theme.colorScheme.tertiaryContainer,
                    child: Text(
                      'TEST MODE',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),

                // Emergency button - centered
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onLongPress: _isTriggering ? null : _triggerEmergency,
                          child: Container(
                            width: size.width * 0.5,
                            height: size.width * 0.5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isTestMode
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.error,
                              boxShadow: [
                                BoxShadow(
                                  color: (_isTestMode
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.error)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 32,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: _isTriggering
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: theme.colorScheme.onError,
                                      strokeWidth: 3,
                                    ),
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 48,
                                        color: _isTestMode
                                            ? theme.colorScheme.onTertiary
                                            : theme.colorScheme.onError,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'HOLD',
                                        style:
                                            theme.textTheme.titleMedium?.copyWith(
                                          color: _isTestMode
                                              ? theme.colorScheme.onTertiary
                                              : theme.colorScheme.onError,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Long press to trigger alert',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Quick actions
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.route_outlined,
                          label: 'Journey',
                          onTap: () => context.push('/journey'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.people_outline,
                          label: 'Contacts',
                          onTap: () => context.push('/contacts'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.history,
                          label: 'History',
                          onTap: () => context.push('/incidents'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _QuickAction(
                          icon: Icons.place,
                          label: 'Map',
                          onTap: () => context.push('/map'),
                        ),
                      ),
                    ],
                  ),
                ),

                // Test mode toggle
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.science_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Test mode',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _isTestMode,
                        onChanged: (value) {
                          setState(() => _isTestMode = value);
                          HapticFeedback.selectionClick();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final bool isMonitoring;
  const _StatusBar({required this.isMonitoring});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isMonitoring
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMonitoring
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isMonitoring ? 'Monitoring active' : 'Safe - no active alerts',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: isMonitoring
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          Icon(
            isMonitoring ? Icons.sensors : Icons.check_circle_outline,
            size: 20,
            color: isMonitoring
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: theme.colorScheme.onSurface),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
