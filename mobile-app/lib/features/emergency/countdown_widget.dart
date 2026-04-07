import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/incident_service.dart';
import '../../core/utils/coercion_handler.dart';

/// Silent countdown timer with haptic feedback.
/// Designed to be discreet -- minimal visual indication,
/// with vibration pulses as the primary feedback mechanism.
class CountdownWidget extends StatefulWidget {
  /// Total countdown duration in seconds.
  final int durationSeconds;

  /// Called when the countdown reaches zero.
  final VoidCallback onComplete;

  /// Called when the user cancels via the secret gesture or normal PIN.
  final VoidCallback onCancel;

  /// Called when the user enters the coercion PIN.
  final VoidCallback onCoercionCancel;

  /// Whether haptic feedback is enabled.
  final bool hapticEnabled;

  const CountdownWidget({
    super.key,
    required this.durationSeconds,
    required this.onComplete,
    required this.onCancel,
    required this.onCoercionCancel,
    this.hapticEnabled = true,
  });

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget>
    with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;

  // Secret cancel: 3 taps in the top-right corner
  int _secretTapCount = 0;
  Timer? _secretTapResetTimer;

  // Coercion PIN entry
  bool _showPinEntry = false;
  final _pinController = TextEditingController();
  bool _isPinProcessing = false;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.durationSeconds;

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _startCountdown();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        widget.onComplete();
        return;
      }

      setState(() => _remainingSeconds--);

      // Haptic pulse each second
      if (widget.hapticEnabled) {
        HapticFeedback.lightImpact();
      }

      // Stronger vibration in last 3 seconds
      if (_remainingSeconds <= 3 && widget.hapticEnabled) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _handleSecretTap() {
    _secretTapCount++;
    _secretTapResetTimer?.cancel();
    _secretTapResetTimer = Timer(const Duration(seconds: 2), () {
      _secretTapCount = 0;
    });

    if (_secretTapCount >= 3) {
      _secretTapCount = 0;
      widget.onCancel();
    }
  }

  Future<void> _handlePinSubmit() async {
    final pin = _pinController.text;
    if (pin.length < 4 || _isPinProcessing) return;

    setState(() => _isPinProcessing = true);

    final coercionHandler = context.read<CoercionHandler>();
    final incidentService = context.read<IncidentService>();
    final incidentId = incidentService.activeIncident?.id;

    if (incidentId == null) {
      // No active incident — just cancel normally.
      widget.onCancel();
      return;
    }

    final result = await coercionHandler.handlePinEntry(
      pin,
      incidentId,
      incidentService,
    );

    _pinController.clear();
    setState(() {
      _showPinEntry = false;
      _isPinProcessing = false;
    });

    if (result == CoercionResult.coercionEscalated) {
      widget.onCoercionCancel();
    } else if (result.shouldShowCancelledUI) {
      widget.onCancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secretTapResetTimer?.cancel();
    _pulseController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _remainingSeconds / widget.durationSeconds;

    return Stack(
      children: [
        // Main countdown area -- intentionally plain / low-key
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Subtle pulsing indicator
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.4 + (_pulseController.value * 0.6),
                  child: child,
                );
              },
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Countdown number -- small, discreet
            Text(
              '$_remainingSeconds',
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),

            // Thin progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
            const SizedBox(height: 48),

            // PIN entry toggle (looks like a normal "cancel" option)
            if (!_showPinEntry)
              TextButton(
                onPressed: () => setState(() => _showPinEntry = true),
                child: Text(
                  'Enter PIN to cancel',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),

            if (_showPinEntry) ...[
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _pinController,
                  decoration: InputDecoration(
                    hintText: 'PIN',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    suffixIcon: _isPinProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.check, size: 20),
                            onPressed: _handlePinSubmit,
                          ),
                  ),
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  onSubmitted: (_) => _handlePinSubmit(),
                ),
              ),
            ],
          ],
        ),

        // Secret cancel zone -- top right corner, invisible
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: _handleSecretTap,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 80, height: 80),
          ),
        ),
      ],
    );
  }
}
