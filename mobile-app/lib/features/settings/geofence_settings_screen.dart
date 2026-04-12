import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/geofence_service.dart';

/// Geofence management screen.
///
/// Allows the user to:
/// - Enable/disable geofence monitoring
/// - View all geofence zones
/// - Edit zone settings (radius, alerts)
/// - Delete custom zones
/// - See which zones were auto-created from learned places
class GeofenceSettingsScreen extends StatelessWidget {
  const GeofenceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = context.watch<GeofenceService>();

    final safeZones =
        service.geofences.where((g) => g.type == GeofenceType.safe).toList();
    final watchZones =
        service.geofences.where((g) => g.type == GeofenceType.watch).toList();
    final customZones =
        service.geofences.where((g) => g.type == GeofenceType.custom).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Geofence Zones'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Monitoring Toggle ──
          Card(
            child: SwitchListTile(
              title: const Text('Enable Geofence Monitoring'),
              subtitle: Text(
                service.isMonitoring
                    ? 'Monitoring ${service.geofences.where((g) => g.isActive).length} active zones'
                    : 'Tap to start monitoring your safe zones',
                style: theme.textTheme.bodySmall,
              ),
              secondary: Icon(
                service.isMonitoring ? Icons.radar : Icons.radar_outlined,
                color: service.isMonitoring
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              value: service.isMonitoring,
              onChanged: (enabled) async {
                if (enabled) {
                  await service.startMonitoring();
                } else {
                  await service.stopMonitoring();
                }
              },
            ),
          ),
          const SizedBox(height: 20),

          // ── Safe Zones ──
          if (safeZones.isNotEmpty) ...[
            _SectionHeader(
              title: 'Safe Zones',
              subtitle:
                  'Alert when you leave. Auto-created from your frequent places.',
              icon: Icons.shield,
              color: Colors.green,
            ),
            const SizedBox(height: 8),
            ...safeZones.map((g) => _GeofenceTile(
                  geofence: g,
                  onToggle: () => service.toggleGeofence(g.id),
                  onDelete: g.linkedPlaceId != null
                      ? null
                      : () => _confirmDelete(context, service, g),
                  onEdit: () => _editGeofence(context, service, g),
                )),
            const SizedBox(height: 20),
          ],

          // ── Watch Zones ──
          if (watchZones.isNotEmpty) ...[
            _SectionHeader(
              title: 'Watch Zones',
              subtitle: 'Alert when you enter. Based on flagged places.',
              icon: Icons.warning_amber,
              color: Colors.red,
            ),
            const SizedBox(height: 8),
            ...watchZones.map((g) => _GeofenceTile(
                  geofence: g,
                  onToggle: () => service.toggleGeofence(g.id),
                  onDelete: () => _confirmDelete(context, service, g),
                  onEdit: () => _editGeofence(context, service, g),
                )),
            const SizedBox(height: 20),
          ],

          // ── Custom Zones ──
          if (customZones.isNotEmpty) ...[
            _SectionHeader(
              title: 'Custom Zones',
              subtitle: 'Zones you created manually.',
              icon: Icons.tune,
              color: Colors.blue,
            ),
            const SizedBox(height: 8),
            ...customZones.map((g) => _GeofenceTile(
                  geofence: g,
                  onToggle: () => service.toggleGeofence(g.id),
                  onDelete: () => _confirmDelete(context, service, g),
                  onEdit: () => _editGeofence(context, service, g),
                )),
            const SizedBox(height: 20),
          ],

          // ── Empty State ──
          if (service.geofences.isEmpty)
            _buildEmptyState(theme),

          // ── How It Works ──
          const SizedBox(height: 8),
          _buildInfoCard(theme),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            Icon(Icons.radar, size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No geofence zones yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Zones are created automatically as the AI learns your frequent places. '
              'Keep using the app and they\'ll appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('How geofencing works',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            _InfoLine(
              icon: Icons.auto_awesome,
              text: 'Zones are created automatically from places you visit frequently',
            ),
            _InfoLine(
              icon: Icons.shield,
              text: 'Safe zones (home, work) alert when you leave unexpectedly',
            ),
            _InfoLine(
              icon: Icons.warning_amber,
              text: 'Watch zones (flagged places) alert when you enter',
            ),
            _InfoLine(
              icon: Icons.swap_horiz,
              text: 'Uses a 20m buffer to prevent false alerts from GPS drift',
            ),
            _InfoLine(
              icon: Icons.lock,
              text: 'All monitoring happens on your device — nothing shared externally',
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, GeofenceService service, Geofence geofence) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Zone'),
        content: Text('Remove "${geofence.name}" from your geofence zones?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              service.removeGeofence(geofence.id);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _editGeofence(
      BuildContext context, GeofenceService service, Geofence geofence) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EditGeofenceSheet(
        geofence: geofence,
        onSave: (updated) {
          service.updateGeofence(updated);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _GeofenceTile extends StatelessWidget {
  final Geofence geofence;
  final VoidCallback onToggle;
  final VoidCallback? onDelete;
  final VoidCallback onEdit;

  const _GeofenceTile({
    required this.geofence,
    required this.onToggle,
    this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color typeColor;
    switch (geofence.type) {
      case GeofenceType.safe:
        typeColor = Colors.green;
        break;
      case GeofenceType.watch:
        typeColor = Colors.red;
        break;
      case GeofenceType.custom:
        typeColor = Colors.blue;
        break;
    }

    return Card(
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: typeColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            geofence.isInside ? Icons.location_on : Icons.location_off_outlined,
            color: typeColor,
            size: 20,
          ),
        ),
        title: Text(
          geofence.name,
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: geofence.isActive
                ? null
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          '${geofence.radiusMeters.toStringAsFixed(0)}m radius · '
          '${geofence.isInside ? "Inside" : "Outside"}'
          '${geofence.linkedPlaceId != null ? " · Auto" : ""}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: geofence.isActive,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            PopupMenuButton<String>(
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                    value: 'edit', child: Text('Edit')),
                if (onDelete != null)
                  const PopupMenuItem(
                      value: 'delete', child: Text('Remove')),
              ],
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete?.call();
              },
              icon: const Icon(Icons.more_vert, size: 20),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.only(left: 12),
      ),
    );
  }
}

class _EditGeofenceSheet extends StatefulWidget {
  final Geofence geofence;
  final void Function(Geofence) onSave;

  const _EditGeofenceSheet({
    required this.geofence,
    required this.onSave,
  });

  @override
  State<_EditGeofenceSheet> createState() => _EditGeofenceSheetState();
}

class _EditGeofenceSheetState extends State<_EditGeofenceSheet> {
  late final TextEditingController _nameController;
  late double _radius;
  late bool _alertOnEntry;
  late bool _alertOnExit;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.geofence.name);
    _radius = widget.geofence.radiusMeters;
    _alertOnEntry = widget.geofence.alertOnEntry;
    _alertOnExit = widget.geofence.alertOnExit;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit Zone',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // Name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Zone name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Radius slider
          Text('Radius: ${_radius.toStringAsFixed(0)}m',
              style: theme.textTheme.bodyMedium),
          Slider(
            value: _radius,
            min: 50,
            max: 1000,
            divisions: 19,
            label: '${_radius.toStringAsFixed(0)}m',
            onChanged: (v) => setState(() => _radius = v),
          ),
          const SizedBox(height: 8),

          // Alert toggles
          SwitchListTile(
            title: const Text('Alert on entry'),
            subtitle: const Text('Notify when you arrive'),
            value: _alertOnEntry,
            onChanged: (v) => setState(() => _alertOnEntry = v),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Alert on exit'),
            subtitle: const Text('Notify when you leave'),
            value: _alertOnExit,
            onChanged: (v) => setState(() => _alertOnExit = v),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // Save button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                final updated = Geofence(
                  id: widget.geofence.id,
                  name: _nameController.text.trim().isEmpty
                      ? widget.geofence.name
                      : _nameController.text.trim(),
                  latitude: widget.geofence.latitude,
                  longitude: widget.geofence.longitude,
                  radiusMeters: _radius,
                  type: widget.geofence.type,
                  alertOnEntry: _alertOnEntry,
                  alertOnExit: _alertOnExit,
                  isInside: widget.geofence.isInside,
                  lastEntered: widget.geofence.lastEntered,
                  lastExited: widget.geofence.lastExited,
                  isActive: widget.geofence.isActive,
                  linkedPlaceId: widget.geofence.linkedPlaceId,
                );
                widget.onSave(updated);
              },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
