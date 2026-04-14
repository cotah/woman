import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../../core/services/alarm_service.dart';
import '../../core/services/background_service.dart';
import '../../core/services/contacts_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/websocket_service.dart';
import '../../core/utils/coercion_handler.dart';

/// System Readiness screen for pilot testers.
/// Shows a single-glance view of every subsystem's status:
/// permissions, provider config, native capabilities, and connectivity.
class SystemReadinessScreen extends StatefulWidget {
  const SystemReadinessScreen({super.key});

  @override
  State<SystemReadinessScreen> createState() => _SystemReadinessScreenState();
}

class _SystemReadinessScreenState extends State<SystemReadinessScreen> {
  bool _isLoading = true;

  // Permissions
  bool _locationGranted = false;
  bool _microphoneGranted = false;
  bool _notificationGranted = false;

  // Device state
  int _contactCount = 0;
  bool _coercionPinSet = false;
  bool _wsConnected = false;
  DateTime? _lastLocationTimestamp;

  // Backend providers
  String _twilioMode = 'Unknown';
  String _pushMode = 'Unknown';
  String _deepgramMode = 'Unknown';
  String _openaiMode = 'Unknown';
  String _backendEnv = 'Unknown';
  bool _backendReachable = false;

  // Native capabilities
  bool _backgroundNativeAvailable = false;
  bool _alarmNativeAvailable = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);

    await Future.wait([
      _checkPermissions(),
      _checkDeviceState(),
      _checkBackendProviders(),
      _checkNativeCapabilities(),
    ]);

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _checkPermissions() async {
    final locPerm = await Geolocator.checkPermission();
    final micPerm = await Permission.microphone.status;
    final notifPerm = await Permission.notification.status;

    if (mounted) {
      setState(() {
        _locationGranted = locPerm == LocationPermission.always ||
            locPerm == LocationPermission.whileInUse;
        _microphoneGranted = micPerm.isGranted;
        _notificationGranted = notifPerm.isGranted;
      });
    }
  }

  Future<void> _checkDeviceState() async {
    try {
      final contactsService = context.read<ContactsService>();
      final coercionHandler = context.read<CoercionHandler>();
      final wsService = context.read<WebSocketService>();
      final locationService = context.read<LocationService>();

      final hasPin = await coercionHandler.hasCoercionPin();
      final lastPos = locationService.lastPosition;

      if (mounted) {
        setState(() {
          _contactCount = contactsService.contactCount;
          _coercionPinSet = hasPin;
          _wsConnected = wsService.isConnected;
          _lastLocationTimestamp = lastPos?.timestamp;
        });
      }
    } catch (e) {
      debugPrint('[SystemReadiness] Device state check failed: $e');
    }
  }

  Future<void> _checkBackendProviders() async {
    try {
      final apiClient = context.read<ApiClient>();
      final response = await apiClient.get('/health/pilot');
      final data = response.data as Map<String, dynamic>;

      final providers = data['providers'] as Map<String, dynamic>? ?? {};
      final twilio = providers['twilio_sms'] as Map<String, dynamic>? ?? {};
      final push = providers['firebase_push'] as Map<String, dynamic>? ?? {};
      final deepgram = providers['deepgram_stt'] as Map<String, dynamic>? ?? {};
      final openai = providers['openai_analysis'] as Map<String, dynamic>? ?? {};

      if (mounted) {
        setState(() {
          _backendReachable = true;
          _backendEnv = data['environment'] as String? ?? 'unknown';
          _twilioMode = twilio['mode'] as String? ?? 'Unknown';
          _pushMode = push['mode'] as String? ?? 'Unknown';
          _deepgramMode = deepgram['mode'] as String? ?? 'Unknown';
          _openaiMode = openai['mode'] as String? ?? 'Unknown';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _backendReachable = false;
          _twilioMode = 'Unreachable';
          _pushMode = 'Unreachable';
          _deepgramMode = 'Unreachable';
          _openaiMode = 'Unreachable';
        });
      }
    }
  }

  Future<void> _checkNativeCapabilities() async {
    try {
      final bgService = context.read<BackgroundService>();
      _backgroundNativeAvailable = bgService.isNativeServiceAvailable;
    } catch (e) {
      debugPrint('[SystemReadiness] BackgroundService check failed: $e');
    }

    try {
      final alarmService = context.read<AlarmService>();
      _alarmNativeAvailable = alarmService.nativeAudioAvailable;
    } catch (e) {
      debugPrint('[SystemReadiness] AlarmService not available: $e');
      _alarmNativeAvailable = false;
    }

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Readiness'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Environment banner
                  _EnvBanner(
                    environment: _backendEnv,
                    appEnv: AppConfig.instance.environment.name,
                    theme: theme,
                  ),
                  const SizedBox(height: 16),

                  // Permissions
                  _SectionCard(
                    title: 'Permissions',
                    theme: theme,
                    children: [
                      _StatusRow(
                        label: 'Location',
                        status: _locationGranted,
                        detail: _locationGranted ? 'Granted' : 'Denied',
                      ),
                      _StatusRow(
                        label: 'Microphone',
                        status: _microphoneGranted,
                        detail: _microphoneGranted ? 'Granted' : 'Denied',
                      ),
                      _StatusRow(
                        label: 'Notifications',
                        status: _notificationGranted,
                        detail: _notificationGranted ? 'Granted' : 'Denied',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Device state
                  _SectionCard(
                    title: 'Device State',
                    theme: theme,
                    children: [
                      _StatusRow(
                        label: 'Trusted contacts',
                        status: _contactCount > 0,
                        detail: '$_contactCount configured',
                      ),
                      _StatusRow(
                        label: 'Coercion PIN',
                        status: _coercionPinSet,
                        detail: _coercionPinSet ? 'Set' : 'Not set',
                      ),
                      _StatusRow(
                        label: 'WebSocket',
                        status: _wsConnected,
                        detail: _wsConnected ? 'Connected' : 'Disconnected',
                      ),
                      _StatusRow(
                        label: 'Last location',
                        status: _lastLocationTimestamp != null,
                        detail: _lastLocationTimestamp != null
                            ? _formatTimestamp(_lastLocationTimestamp!)
                            : 'No fix yet',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Backend providers
                  _SectionCard(
                    title: 'Alert Delivery',
                    theme: theme,
                    children: [
                      _StatusRow(
                        label: 'Backend',
                        status: _backendReachable,
                        detail: _backendReachable
                            ? 'Reachable ($_backendEnv)'
                            : 'Unreachable',
                      ),
                      _ModeRow(label: 'SMS (Twilio)', mode: _twilioMode),
                      _ModeRow(label: 'Push (FCM)', mode: _pushMode),
                      _ModeRow(label: 'Speech-to-Text', mode: _deepgramMode),
                      _ModeRow(label: 'AI Analysis', mode: _openaiMode),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Native capabilities
                  _SectionCard(
                    title: 'Native Platform',
                    theme: theme,
                    children: [
                      _StatusRow(
                        label: 'Background service',
                        status: _backgroundNativeAvailable,
                        detail: _backgroundNativeAvailable
                            ? 'Available'
                            : 'Not implemented (app may be killed in background)',
                      ),
                      _StatusRow(
                        label: 'Alarm siren',
                        status: _alarmNativeAvailable,
                        detail: _alarmNativeAvailable
                            ? 'Available'
                            : 'Not implemented (visual flash only)',
                      ),
                      _StatusRow(
                        label: 'SMS fallback',
                        status: null,
                        detail: 'Opens SMS composer (user must tap Send)',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Legend
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'DRY-RUN = alerts are logged but not sent to real recipients.\n'
                      'LIVE = alerts are delivered to real phone numbers.\n\n'
                      'Pull down to refresh all checks.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ─────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────

class _EnvBanner extends StatelessWidget {
  final String environment;
  final String appEnv;
  final ThemeData theme;

  const _EnvBanner({
    required this.environment,
    required this.appEnv,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isLive = environment.toLowerCase() == 'production';
    final color = isLive ? theme.colorScheme.error : theme.colorScheme.tertiary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isLive ? Icons.warning_amber : Icons.science_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            isLive ? 'PRODUCTION MODE' : 'TEST / DEV MODE',
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const Spacer(),
          Text(
            'App: $appEnv',
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final ThemeData theme;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.theme,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool? status; // null = info only (no green/red)
  final String detail;

  const _StatusRow({
    required this.label,
    required this.status,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final iconData = status == null
        ? Icons.info_outline
        : status!
            ? Icons.check_circle
            : Icons.cancel;

    final iconColor = status == null
        ? theme.colorScheme.onSurfaceVariant
        : status!
            ? Colors.green
            : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(iconData, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Flexible(
            child: Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  final String label;
  final String mode;

  const _ModeRow({required this.label, required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = mode == 'LIVE';
    final isDryRun = mode == 'DRY-RUN';

    final badgeColor = isLive
        ? Colors.green
        : isDryRun
            ? theme.colorScheme.tertiary
            : theme.colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 28), // indent under section
          Text(label, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              mode,
              style: theme.textTheme.labelSmall?.copyWith(
                color: badgeColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
