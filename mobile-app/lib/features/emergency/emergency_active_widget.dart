import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/background_service.dart';
import '../../core/services/location_service.dart';
import '../../core/services/audio_service.dart';

/// Displays the active emergency state.
/// Designed to be minimal and discreet -- should not look alarming
/// if someone else glances at the screen.
///
/// Shows clear warnings for degraded capabilities (background not native,
/// audio consent not granted, etc.) so pilot testers can identify issues.
class EmergencyActiveWidget extends StatefulWidget {
  /// Whether this is a coercion (fake cancel) state.
  /// If true, shows a fake "cancelled" appearance while actually active.
  final bool isCoercionMode;

  /// Called to truly end the emergency.
  final VoidCallback onEnd;

  const EmergencyActiveWidget({
    super.key,
    this.isCoercionMode = false,
    required this.onEnd,
  });

  @override
  State<EmergencyActiveWidget> createState() => _EmergencyActiveWidgetState();
}

class _EmergencyActiveWidgetState extends State<EmergencyActiveWidget> {
  late final Stopwatch _elapsed;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _elapsed = Stopwatch()..start();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _elapsed.stop();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Coercion mode: show a fake "Alert cancelled" screen
    if (widget.isCoercionMode) {
      return _CoercionFakeScreen(theme: theme);
    }

    final locationService = context.watch<LocationService>();
    final audioService = context.watch<AudioService>();
    final bgService = context.watch<BackgroundService>();

    final locationStatus = locationService.isTracking ? 'Active' : 'Waiting';
    final audioStatus = audioService.isRecording ? 'Recording' : 'Standby';

    // Collect warnings for pilot testers
    final warnings = <String>[];
    if (!bgService.isNativeServiceAvailable && bgService.isRunning) {
      warnings.add('Background service not native — app may stop if minimized');
    }
    if (!locationService.isTracking) {
      warnings.add('Location not tracking — check permissions');
    }

    // Real active state: minimal, discreet
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Warnings for testers (only shown when relevant)
        if (warnings.isNotEmpty) ...[
          ...warnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          size: 16,
                          color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          w,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 8),
        ],

        // Small recording indicator
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PulsingDot(color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'Active',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Elapsed time
        Text(
          _formatDuration(_elapsed.elapsed),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w300,
            fontFeatures: [const FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 32),

        // Status items -- live from services
        _StatusRow(
          icon: Icons.location_on,
          label: 'Location sharing',
          status: locationStatus,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _StatusRow(
          icon: Icons.mic,
          label: 'Audio',
          status: audioStatus,
          theme: theme,
        ),
        const SizedBox(height: 12),
        _StatusRow(
          icon: Icons.people,
          label: 'Contacts',
          status: 'Notified',
          theme: theme,
        ),

        const SizedBox(height: 48),

        // End emergency -- subtle, not prominent
        TextButton(
          onPressed: _confirmEnd,
          child: Text(
            'End alert',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End alert'),
        content: const Text(
          'This will stop location sharing and notify your contacts '
          'that the alert has ended. Are you safe?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep active'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onEnd();
            },
            child: const Text('I am safe'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Coercion fake screen
// ─────────────────────────────────────────────────────────

class _CoercionFakeScreen extends StatelessWidget {
  final ThemeData theme;
  const _CoercionFakeScreen({required this.theme});

  @override
  Widget build(BuildContext context) {
    // This screen looks like the alert was successfully cancelled.
    // In reality, location/audio/websocket remain active.
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 24),
        Text(
          'Alert cancelled',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your contacts have been notified that you are safe.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),
        FilledButton(
          onPressed: () {
            context.go('/home');
          },
          child: const Text('Return to home'),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (_controller.value * 0.7),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String status;
  final ThemeData theme;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            status,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}
