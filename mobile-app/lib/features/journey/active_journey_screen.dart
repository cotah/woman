import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/journey.dart';
import '../../core/services/journey_service.dart';

/// Displays the active Safe Journey with a countdown timer,
/// destination info, and actions to complete, extend, or cancel.
class ActiveJourneyScreen extends StatefulWidget {
  const ActiveJourneyScreen({super.key});

  @override
  State<ActiveJourneyScreen> createState() => _ActiveJourneyScreenState();
}

class _ActiveJourneyScreenState extends State<ActiveJourneyScreen> {
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();

    // Tick every second to update the countdown display.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Fetch active journey on load in case we navigated here directly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final journeyService = context.read<JourneyService>();
      if (journeyService.activeJourney == null) {
        journeyService.getActiveJourney().then((journey) {
          if (journey == null && mounted) {
            context.go('/journey');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    super.dispose();
  }

  Duration _remainingTime(Journey journey) {
    final remaining = journey.expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      final hours = d.inHours.toString();
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Future<void> _onArrived() async {
    try {
      await context.read<JourneyService>().complete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Journey completed. Stay safe!')),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to complete journey: $e')),
        );
      }
    }
  }

  Future<void> _onNeedMoreTime() async {
    try {
      await context.read<JourneyService>().checkin(10);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added 10 more minutes')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to extend time: $e')),
        );
      }
    }
  }

  Future<void> _onCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel journey?'),
        content: const Text(
          'Your contacts will no longer be able to track your location. '
          'Are you sure you want to cancel?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel journey'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await context.read<JourneyService>().cancel();
      if (mounted) {
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel journey: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Safe Journey'),
          automaticallyImplyLeading: false,
        ),
        body: Consumer<JourneyService>(
          builder: (context, journeyService, _) {
            final journey = journeyService.activeJourney;

            if (journey == null) {
              return const Center(child: CircularProgressIndicator());
            }

            // If the journey ended (e.g. server-side auto-complete on
            // arrival), show a completed state.
            if (journey.status.isTerminal) {
              return _TerminalView(status: journey.status);
            }

            final remaining = _remainingTime(journey);
            final isExpired = remaining == Duration.zero;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 2),

                    // Status icon
                    Icon(
                      isExpired
                          ? Icons.warning_amber_rounded
                          : Icons.shield_outlined,
                      size: 64,
                      color: isExpired
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),

                    // Countdown timer
                    Text(
                      _formatDuration(remaining),
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontFeatures: [const FontFeature.tabularFigures()],
                        color: isExpired
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isExpired
                          ? 'Time expired - contacts may be alerted'
                          : 'Time remaining',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isExpired
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    // Destination label
                    if (journey.destLabel != null) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            journey.destLabel!,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Sharing status
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withOpacity(0.3),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.share_location,
                            size: 18,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your contacts can see your location',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(flex: 3),

                    // "I arrived safely" button
                    FilledButton.icon(
                      onPressed: _onArrived,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('I arrived safely'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // "I need more time" button
                    TextButton(
                      onPressed: _onNeedMoreTime,
                      child: const Text('I need more time (+10 min)'),
                    ),
                    const SizedBox(height: 4),

                    // Cancel button
                    TextButton(
                      onPressed: _onCancel,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Cancel journey'),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shown when the journey has reached a terminal state
/// (completed, expired, escalated, cancelled).
class _TerminalView extends StatelessWidget {
  final JourneyStatus status;

  const _TerminalView({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final IconData icon;
    final String title;
    final String subtitle;

    switch (status) {
      case JourneyStatus.completed:
        icon = Icons.check_circle_outline;
        title = 'Journey completed';
        subtitle = 'You arrived safely.';
        break;
      case JourneyStatus.escalated:
        icon = Icons.warning_amber_rounded;
        title = 'Journey escalated';
        subtitle = 'Your contacts have been alerted.';
        break;
      case JourneyStatus.expired:
        icon = Icons.timer_off_outlined;
        title = 'Journey expired';
        subtitle = 'The timer ran out.';
        break;
      case JourneyStatus.cancelled:
        icon = Icons.cancel_outlined;
        title = 'Journey cancelled';
        subtitle = 'Location sharing has stopped.';
        break;
      default:
        icon = Icons.info_outline;
        title = 'Journey ended';
        subtitle = '';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text('Return to home'),
            ),
          ],
        ),
      ),
    );
  }
}
