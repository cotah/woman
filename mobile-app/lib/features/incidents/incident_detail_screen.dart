import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/incident.dart';
import '../../core/models/timeline_event.dart';
import '../../core/services/incident_service.dart';

/// Timeline event types that are user-visible.
/// Hides telemetry-level events (location updates, audio chunks, etc.) to
/// keep the timeline scannable. Failures and operator actions stay visible.
const _visibleTimelineTypes = {
  TimelineEventType.triggerActivated,
  TimelineEventType.countdownStarted,
  TimelineEventType.countdownCancelled,
  TimelineEventType.incidentActivated,
  TimelineEventType.coercionDetected,
  TimelineEventType.transcriptionCompleted,
  TimelineEventType.riskScoreChanged,
  TimelineEventType.alertDispatched,
  TimelineEventType.alertDelivered,
  TimelineEventType.alertFailed,
  TimelineEventType.contactResponded,
  TimelineEventType.escalationWave,
  TimelineEventType.incidentResolved,
  TimelineEventType.incidentTimedOut,
  TimelineEventType.secretCancel,
  TimelineEventType.geofenceBreach,
  TimelineEventType.operatorAction,
};

/// Single incident detail with timeline of events.
class IncidentDetailScreen extends StatefulWidget {
  final String incidentId;

  const IncidentDetailScreen({super.key, required this.incidentId});

  @override
  State<IncidentDetailScreen> createState() => _IncidentDetailScreenState();
}

class _IncidentDetailScreenState extends State<IncidentDetailScreen> {
  Incident? _incident;
  List<TimelineEvent>? _timeline;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final svc = context.read<IncidentService>();
      final results = await Future.wait([
        svc.getIncident(widget.incidentId),
        svc.getTimeline(widget.incidentId),
      ]);
      if (!mounted) return;
      setState(() {
        _incident = results[0] as Incident;
        _timeline = results[1] as List<TimelineEvent>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load incident details.';
        _isLoading = false;
      });
    }
  }

  // ── Derived getters ─────────────────────────────────

  Duration get _duration {
    if (_incident == null) return Duration.zero;
    final end = _incident!.resolvedAt ?? DateTime.now();
    return end.difference(_incident!.startedAt);
  }

  bool get _hasAudio =>
      _timeline?.any((e) => e.type == TimelineEventType.audioChunkUploaded) ??
      false;

  bool get _hasLocation => _incident?.lastLatitude != null;

  /// Contacts notified, derived from alertDispatched/alertDelivered events
  /// (extracts payload['contactName'], dedupes).
  List<String> get _contactsNotified {
    if (_timeline == null) return const [];
    final names = <String>{};
    for (final event in _timeline!) {
      if (event.type == TimelineEventType.alertDispatched ||
          event.type == TimelineEventType.alertDelivered) {
        final name = event.payload['contactName'];
        if (name is String && name.trim().isNotEmpty) {
          names.add(name);
        }
      }
    }
    return names.toList();
  }

  List<TimelineEvent> get _visibleTimeline {
    if (_timeline == null) return const [];
    return _timeline!
        .where((e) => _visibleTimelineTypes.contains(e.type) && !e.isInternal)
        .toList();
  }

  // ── Helpers ─────────────────────────────────────────

  String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds} seconds';
    if (d.inHours < 1) return '${d.inMinutes} minutes';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  String _statusLabel(IncidentStatus status) {
    return switch (status) {
      IncidentStatus.pending => 'Pending',
      IncidentStatus.countdown => 'Countdown',
      IncidentStatus.active => 'Active',
      IncidentStatus.escalated => 'Escalated',
      IncidentStatus.resolved => 'Resolved',
      IncidentStatus.cancelled => 'Cancelled',
      IncidentStatus.falseAlarm => 'False alarm',
      IncidentStatus.timedOut => 'Timed out',
    };
  }

  String _riskLevelLabel(RiskLevel level) {
    return switch (level) {
      RiskLevel.none => 'None',
      RiskLevel.monitoring => 'Monitoring',
      RiskLevel.suspicious => 'Suspicious',
      RiskLevel.alert => 'Alert',
      RiskLevel.critical => 'Critical',
    };
  }

  Color _statusColor(IncidentStatus status, ThemeData theme) {
    return switch (status) {
      IncidentStatus.resolved => theme.colorScheme.primary,
      IncidentStatus.cancelled => theme.colorScheme.outline,
      IncidentStatus.active ||
      IncidentStatus.escalated =>
        theme.colorScheme.error,
      IncidentStatus.falseAlarm => theme.colorScheme.tertiary,
      _ => theme.colorScheme.outline,
    };
  }

  /// Map a timeline event to a user-friendly title and description.
  /// Description may pull data from event.payload when available.
  ({String title, String description}) _eventLabel(TimelineEvent event) {
    final p = event.payload;
    switch (event.type) {
      case TimelineEventType.triggerActivated:
        return (title: 'Alert triggered', description: 'Emergency activated.');
      case TimelineEventType.countdownStarted:
        final secs = p['durationSeconds'] ?? p['countdownSeconds'];
        return (
          title: 'Countdown started',
          description: secs != null
              ? '$secs second countdown began.'
              : 'Countdown began.',
        );
      case TimelineEventType.countdownCancelled:
        return (
          title: 'Countdown cancelled',
          description: 'User cancelled before activation.',
        );
      case TimelineEventType.incidentActivated:
        return (
          title: 'Alert sent',
          description: 'Contacts notified. Location sharing started.',
        );
      case TimelineEventType.coercionDetected:
        return (
          title: 'Coercion PIN detected',
          description: 'Silent escalation triggered.',
        );
      case TimelineEventType.transcriptionCompleted:
        final isDistress = p['isDistress'] == true;
        final chars = p['textLength'];
        final charsStr = chars != null ? ' in $chars chars' : '';
        return (
          title: 'Audio transcribed',
          description: isDistress
              ? 'Distress signals detected$charsStr.'
              : 'No distress signals detected$charsStr.',
        );
      case TimelineEventType.riskScoreChanged:
        final newScore = p['newScore'];
        final newLevel = p['newLevel'];
        return (
          title: 'Risk score updated',
          description: newScore != null
              ? 'New score: $newScore${newLevel != null ? " ($newLevel)" : ""}.'
              : 'Risk level changed.',
        );
      case TimelineEventType.alertDispatched:
        final name = p['contactName'];
        final channel = p['channel'];
        return (
          title: 'Notification sent',
          description: name != null
              ? 'Sent to $name${channel != null ? " via $channel" : ""}.'
              : 'Notification dispatched.',
        );
      case TimelineEventType.alertDelivered:
        final name = p['contactName'];
        return (
          title: 'Notification delivered',
          description:
              name != null ? 'Delivered to $name.' : 'Notification delivered.',
        );
      case TimelineEventType.alertFailed:
        final name = p['contactName'];
        final reason = p['reason'] ?? p['failureReason'];
        return (
          title: 'Notification failed',
          description: name != null
              ? 'Could not reach $name${reason != null ? ": $reason" : ""}.'
              : 'Notification could not be delivered.',
        );
      case TimelineEventType.contactResponded:
        final name = p['contactName'];
        final response = p['responseType'] ?? p['response'];
        return (
          title: 'Contact responded',
          description: name != null
              ? '$name responded${response != null ? ": $response" : ""}.'
              : 'A contact responded.',
        );
      case TimelineEventType.escalationWave:
        final wave = p['wave'];
        return (
          title: 'Escalation wave',
          description: wave != null
              ? 'Wave $wave activated — contacts re-notified.'
              : 'Escalation wave triggered.',
        );
      case TimelineEventType.incidentResolved:
        final reason = p['reason'];
        return (
          title: 'Alert ended',
          description:
              reason != null ? 'Resolved: $reason.' : 'Incident resolved.',
        );
      case TimelineEventType.incidentTimedOut:
        return (
          title: 'Alert timed out',
          description: 'No response received within the time window.',
        );
      case TimelineEventType.secretCancel:
        return (
          title: 'Secret cancellation',
          description: 'Backend escalation continues silently.',
        );
      case TimelineEventType.geofenceBreach:
        final zone = p['zoneName'] ?? p['zone'];
        return (
          title: 'Geofence breach',
          description: zone != null
              ? 'Entered or exited "$zone".'
              : 'Geofence boundary crossed.',
        );
      case TimelineEventType.operatorAction:
        final action = p['action'];
        return (
          title: 'Operator action',
          description:
              action != null ? 'Operator: $action.' : 'Operator action recorded.',
        );
      // Hidden by _visibleTimelineTypes filter above; included as safety net.
      default:
        return (title: 'Event', description: '');
    }
  }

  // ── Build ───────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load, theme: theme)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _buildContent(theme),
                ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    final incident = _incident!;
    final visible = _visibleTimeline;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row: date + status badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _formatDate(incident.startedAt),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    _StatusBadge(
                      label: _statusLabel(incident.status),
                      color: _statusColor(incident.status, theme),
                      theme: theme,
                    ),
                  ],
                ),

                // Mode badges (test / coercion)
                if (incident.isTestMode || incident.isCoercion) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (incident.isTestMode)
                        _ModeBadge(
                          label: 'TEST',
                          color: theme.colorScheme.tertiary,
                          theme: theme,
                        ),
                      if (incident.isTestMode && incident.isCoercion)
                        const SizedBox(width: 8),
                      if (incident.isCoercion)
                        _ModeBadge(
                          label: 'COERCION',
                          color: theme.colorScheme.error,
                          theme: theme,
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 16),
                _DetailRow(
                  label: 'Duration',
                  value: _formatDuration(_duration),
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Risk score',
                  value:
                      '${incident.currentRiskScore} (${_riskLevelLabel(incident.currentRiskLevel)})',
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Contacts notified',
                  value: _contactsNotified.isEmpty
                      ? '—'
                      : _contactsNotified.join(', '),
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Location data',
                  value: _hasLocation ? 'Available' : 'Not recorded',
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  label: 'Audio recording',
                  value: _hasAudio ? 'Available' : 'Not recorded',
                  theme: theme,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Timeline
        Text(
          'Timeline',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),

        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No timeline events recorded.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          ...List.generate(visible.length, (index) {
            final event = visible[index];
            final label = _eventLabel(event);
            return _TimelineItem(
              title: label.title,
              description: label.description,
              timestamp: event.timestamp,
              isLast: index == visible.length - 1,
              theme: theme,
            );
          }),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final ThemeData theme;

  const _StatusBadge({
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  final String label;
  final Color color;
  final ThemeData theme;

  const _ModeBadge({
    required this.label,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineItem extends StatelessWidget {
  final String title;
  final String description;
  final DateTime timestamp;
  final bool isLast;
  final ThemeData theme;

  const _TimelineItem({
    required this.title,
    required this.description,
    required this.timestamp,
    required this.isLast,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    '${timestamp.hour.toString().padLeft(2, '0')}:'
                    '${timestamp.minute.toString().padLeft(2, '0')}:'
                    '${timestamp.second.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final ThemeData theme;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
