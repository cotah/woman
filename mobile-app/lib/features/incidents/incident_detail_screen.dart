import 'package:flutter/material.dart';

/// Single incident detail with timeline of events.
class IncidentDetailScreen extends StatelessWidget {
  final String incidentId;

  const IncidentDetailScreen({super.key, required this.incidentId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // TODO: Load incident from provider/service using incidentId
    final incident = _MockIncidentDetail(
      id: incidentId,
      date: DateTime.now().subtract(const Duration(days: 2)),
      duration: const Duration(minutes: 12),
      status: 'resolved',
      contactsNotified: ['Marie Dupont', 'Lucas Martin'],
      hasAudio: true,
      hasLocation: true,
      timeline: [
        _TimelineEvent(
          time: DateTime.now().subtract(const Duration(days: 2, minutes: 12)),
          title: 'Alert triggered',
          description: 'Emergency button activated.',
        ),
        _TimelineEvent(
          time: DateTime.now().subtract(const Duration(days: 2, minutes: 11, seconds: 50)),
          title: 'Countdown started',
          description: '10 second countdown began.',
        ),
        _TimelineEvent(
          time: DateTime.now().subtract(const Duration(days: 2, minutes: 11, seconds: 40)),
          title: 'Alert sent',
          description: 'Contacts notified. Location sharing started.',
        ),
        _TimelineEvent(
          time: DateTime.now().subtract(const Duration(days: 2, minutes: 11, seconds: 38)),
          title: 'Audio recording started',
          description: 'Microphone recording began.',
        ),
        _TimelineEvent(
          time: DateTime.now().subtract(const Duration(days: 2)),
          title: 'Alert ended',
          description: 'User confirmed safety. Contacts notified.',
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incident details'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'export':
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Export requested.')),
                  );
                  break;
                case 'delete':
                  _confirmDelete(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'export',
                child: Text('Export incident data'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete incident',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
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
                  Row(
                    children: [
                      Text(
                        _formatDate(incident.date),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _StatusBadge(
                        status: incident.status,
                        theme: theme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _DetailRow(
                    label: 'Duration',
                    value: '${incident.duration.inMinutes} minutes',
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Contacts notified',
                    value: incident.contactsNotified.join(', '),
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Location data',
                    value: incident.hasLocation ? 'Available' : 'Not recorded',
                    theme: theme,
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Audio recording',
                    value: incident.hasAudio ? 'Available' : 'Not recorded',
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

          ...List.generate(incident.timeline.length, (index) {
            final event = incident.timeline[index];
            final isLast = index == incident.timeline.length - 1;

            return _TimelineItem(
              event: event,
              isLast: isLast,
              theme: theme,
            );
          }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete incident'),
        content: const Text(
          'This will permanently delete this incident record and all associated data. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO: Delete incident via service
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final ThemeData theme;

  const _StatusBadge({required this.status, required this.theme});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'resolved' => theme.colorScheme.primary,
      'cancelled' => theme.colorScheme.outline,
      _ => theme.colorScheme.tertiary,
    };
    final label = switch (status) {
      'resolved' => 'Resolved',
      'cancelled' => 'Cancelled',
      _ => status,
    };

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
  final _TimelineEvent event;
  final bool isLast;
  final ThemeData theme;

  const _TimelineItem({
    required this.event,
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
                    event.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${event.time.hour.toString().padLeft(2, '0')}:'
                    '${event.time.minute.toString().padLeft(2, '0')}:'
                    '${event.time.second.toString().padLeft(2, '0')}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

// ─────────────────────────────────────────────────────────

class _TimelineEvent {
  final DateTime time;
  final String title;
  final String description;

  const _TimelineEvent({
    required this.time,
    required this.title,
    required this.description,
  });
}

class _MockIncidentDetail {
  final String id;
  final DateTime date;
  final Duration duration;
  final String status;
  final List<String> contactsNotified;
  final bool hasAudio;
  final bool hasLocation;
  final List<_TimelineEvent> timeline;

  const _MockIncidentDetail({
    required this.id,
    required this.date,
    required this.duration,
    required this.status,
    required this.contactsNotified,
    required this.hasAudio,
    required this.hasLocation,
    required this.timeline,
  });
}
