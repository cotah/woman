import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/incident_service.dart';
import '../../core/utils/coercion_handler.dart';
import 'countdown_widget.dart';
import 'emergency_active_widget.dart';

/// The critical emergency screen.
///
/// States:
/// 1. Countdown -- silent countdown before alert is sent
/// 2. Active -- emergency is live, location sharing, recording
/// 3. Coercion -- fake "cancelled" display while alert continues
///    SAFETY-CRITICAL: Location, audio, and websocket remain active.
///    The IncidentService._isCoercionMode flag controls this behavior.
///    See IncidentService.secretCancelIncident() for the full contract.
/// 4. Ended -- alert has been resolved
///
/// Design: deliberately discreet and low-key. Should not draw attention
/// from an aggressor or look alarming to a bystander.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

enum _EmergencyState { countdown, active, coercion, ended }

class _EmergencyScreenState extends State<EmergencyScreen> {
  _EmergencyState _state = _EmergencyState.countdown;

  @override
  void initState() {
    super.initState();
    // Lock to portrait, keep screen on
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  int get _countdownDuration {
    final incidentService = context.read<IncidentService>();
    final incident = incidentService.activeIncident;
    if (incident?.countdownEndsAt != null) {
      final remaining =
          incident!.countdownEndsAt!.difference(DateTime.now()).inSeconds;
      return remaining > 0 ? remaining : 5;
    }
    return 5;
  }

  String? get _activeIncidentId {
    return context.read<IncidentService>().activeIncident?.id;
  }

  Future<void> _onCountdownComplete() async {
    HapticFeedback.heavyImpact();
    setState(() => _state = _EmergencyState.active);

    // Activate the incident on the backend (starts audio, notifies contacts).
    final incidentId = _activeIncidentId;
    if (incidentId != null) {
      try {
        final incidentService = context.read<IncidentService>();
        await incidentService.activateIncident(incidentId);
      } catch (e) {
        debugPrint('[EmergencyScreen] Failed to activate: $e');
      }
    }
  }

  Future<void> _onCancel() async {
    HapticFeedback.mediumImpact();

    final incidentId = _activeIncidentId;
    if (incidentId != null) {
      try {
        final incidentService = context.read<IncidentService>();
        await incidentService.cancelIncident(incidentId);
      } catch (e) {
        debugPrint('[EmergencyScreen] Cancel failed: $e');
      }
    }

    setState(() => _state = _EmergencyState.ended);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) context.go('/home');
    });
  }

  void _onCoercionCancel() {
    // SAFETY-CRITICAL: The CoercionHandler has already called
    // incidentService.secretCancelIncident() which:
    //   1. Sent isSecretCancel=true to backend (escalates to CRITICAL)
    //   2. Set _isCoercionMode=true on IncidentService
    //   3. Did NOT stop location tracking
    //   4. Did NOT stop audio recording
    //   5. Did NOT leave websocket room
    //   6. Did NOT null out activeIncident
    //
    // We only change the UI to show a fake "cancelled" screen.
    HapticFeedback.mediumImpact();
    setState(() => _state = _EmergencyState.coercion);
  }

  Future<void> _onEnd() async {
    final incidentService = context.read<IncidentService>();
    final incidentId = incidentService.activeIncident?.id;

    if (incidentId != null) {
      try {
        // resolveIncident handles both normal and coercion modes:
        // it resets _isCoercionMode and calls _cleanupActiveIncident.
        await incidentService.resolveIncident(incidentId);
      } catch (e) {
        debugPrint('[EmergencyScreen] Resolve failed: $e');
      }
    }

    setState(() => _state = _EmergencyState.ended);
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) context.go('/home');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Intentionally plain background -- not red, not flashy
    return PopScope(
      canPop: false, // Prevent accidental back navigation
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_state) {
      case _EmergencyState.countdown:
        return CountdownWidget(
          durationSeconds: _countdownDuration,
          onComplete: _onCountdownComplete,
          onCancel: _onCancel,
          onCoercionCancel: _onCoercionCancel,
        );
      case _EmergencyState.active:
        return EmergencyActiveWidget(
          isCoercionMode: false,
          onEnd: _onEnd,
        );
      case _EmergencyState.coercion:
        return EmergencyActiveWidget(
          isCoercionMode: true,
          onEnd: _onEnd,
        );
      case _EmergencyState.ended:
        return _EndedView();
    }
  }
}

class _EndedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Alert ended',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Returning to home...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
