import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/incident.dart';
import '../../core/services/incident_service.dart';
import '../emergency/countdown_widget.dart';
import '../emergency/emergency_active_widget.dart';

/// Simulates the emergency flow using IncidentService with isTestMode: true.
/// Reuses the same CountdownWidget and EmergencyActiveWidget as the real flow.
/// Clearly branded as TEST MODE at all times.
class TestModeScreen extends StatefulWidget {
  const TestModeScreen({super.key});

  @override
  State<TestModeScreen> createState() => _TestModeScreenState();
}

enum _TestPhase { ready, countdown, active, ended }

class _TestModeScreenState extends State<TestModeScreen> {
  _TestPhase _phase = _TestPhase.ready;
  bool _isStarting = false;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _startTest() async {
    if (_isStarting) return;
    setState(() => _isStarting = true);

    try {
      final incidentService = context.read<IncidentService>();
      await incidentService.createIncident(
        triggerType: TriggerType.manualButton,
        isTestMode: true,
        countdownSeconds: 10,
      );
      if (mounted) {
        setState(() {
          _phase = _TestPhase.countdown;
          _isStarting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isStarting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start test: $e')),
        );
      }
    }
  }

  void _onCountdownComplete() {
    final incidentService = context.read<IncidentService>();
    final incident = incidentService.activeIncident;
    if (incident != null) {
      incidentService.activateIncident(incident.id);
    }
    setState(() => _phase = _TestPhase.active);
    HapticFeedback.heavyImpact();
  }

  void _onCancel() {
    final incidentService = context.read<IncidentService>();
    final incident = incidentService.activeIncident;
    if (incident != null) {
      incidentService.cancelIncident(incident.id, reason: 'Test cancelled');
    }
    setState(() => _phase = _TestPhase.ready);
  }

  void _onEnd() {
    final incidentService = context.read<IncidentService>();
    final incident = incidentService.activeIncident;
    if (incident != null) {
      incidentService.resolveIncident(
        incident.id,
        reason: 'Test completed',
        isFalseAlarm: true,
      );
    }
    setState(() => _phase = _TestPhase.ended);
    _showTestCompleteDialog();
  }

  void _showTestCompleteDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.science_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        title: const Text('This was a test'),
        content: const Text(
          'In a real emergency, your emergency contacts would have been '
          'notified with your real-time location. Audio recording and '
          'location sharing would have been active.\n\n'
          'No contacts were notified during this test.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _phase = _TestPhase.ready);
            },
            child: const Text('Run again'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test mode'),
        leading: IconButton(
          onPressed: () {
            // Clean up any active test incident before leaving.
            final incidentService = context.read<IncidentService>();
            final incident = incidentService.activeIncident;
            if (incident != null) {
              incidentService.cancelIncident(
                incident.id,
                reason: 'Test exited',
              );
            }
            context.pop();
          },
          icon: const Icon(Icons.close),
        ),
      ),
      body: Column(
        children: [
          // Persistent TEST MODE banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            color: theme.colorScheme.tertiaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.science_outlined,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'TEST MODE - No real alerts will be sent',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildPhaseContent(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseContent(ThemeData theme) {
    switch (_phase) {
      case _TestPhase.ready:
        return _ReadyContent(
          theme: theme,
          onStart: _startTest,
          isLoading: _isStarting,
        );
      case _TestPhase.countdown:
        return CountdownWidget(
          durationSeconds: 10,
          onComplete: _onCountdownComplete,
          onCancel: _onCancel,
          onCoercionCancel: _onCancel, // In test mode, treat coercion as normal cancel.
          hapticEnabled: true,
        );
      case _TestPhase.active:
        return EmergencyActiveWidget(
          isCoercionMode: false,
          onEnd: _onEnd,
        );
      case _TestPhase.ended:
        return _EndedContent(
          theme: theme,
          onRestart: () => setState(() => _phase = _TestPhase.ready),
          onExit: () => context.pop(),
        );
    }
  }
}

class _ReadyContent extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onStart;
  final bool isLoading;

  const _ReadyContent({
    required this.theme,
    required this.onStart,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.science_outlined,
          size: 64,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(height: 24),
        Text(
          'Test the alert flow',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'This runs through the full emergency flow using real services '
            'in test mode:\n\n'
            '1. Countdown with haptic feedback\n'
            '2. Active alert state with live status\n'
            '3. End confirmation\n\n'
            'No contacts will be notified. No real alerts will be sent.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: isLoading ? null : onStart,
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.tertiary,
            ),
            child: isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Start test'),
          ),
        ),
      ],
    );
  }
}

class _EndedContent extends StatelessWidget {
  final ThemeData theme;
  final VoidCallback onRestart;
  final VoidCallback onExit;

  const _EndedContent({
    required this.theme,
    required this.onRestart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 64,
          color: theme.colorScheme.tertiary,
        ),
        const SizedBox(height: 24),
        Text(
          'Test complete',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The test ran successfully. No alerts were sent.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: OutlinedButton(
            onPressed: onRestart,
            child: const Text('Run again'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: onExit,
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
