import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/journey_service.dart';
import '../../core/services/location_service.dart';

/// Screen to start a new Safe Journey.
///
/// Provides quick-start buttons for saved destinations (Home / Work),
/// a timer selector, and a start button.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  int _selectedMinutes = 30;
  bool _isStarting = false;

  // Saved destination coords (persisted via SharedPreferences).
  double? _homeLat;
  double? _homeLng;
  double? _workLat;
  double? _workLng;

  static const _durations = [10, 20, 30, 60];

  @override
  void initState() {
    super.initState();
    _loadSavedDestinations();
  }

  Future<void> _loadSavedDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _homeLat = prefs.getDouble('journey_home_lat');
      _homeLng = prefs.getDouble('journey_home_lng');
      _workLat = prefs.getDouble('journey_work_lat');
      _workLng = prefs.getDouble('journey_work_lng');
    });
  }

  Future<void> _saveDestination(String key, double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('journey_${key}_lat', lat);
    await prefs.setDouble('journey_${key}_lng', lng);
    await _loadSavedDestinations();
  }

  Future<void> _startJourney({
    required double destLat,
    required double destLng,
    String? destLabel,
  }) async {
    if (_isStarting) return;

    setState(() => _isStarting = true);

    try {
      final journeyService = context.read<JourneyService>();
      final locationService = context.read<LocationService>();

      // Get current location as start point.
      final currentLocation = await locationService.getCurrentLocation();

      await journeyService.startJourney(
        destLat: destLat,
        destLng: destLng,
        destLabel: destLabel,
        durationMinutes: _selectedMinutes,
        startLat: currentLocation?.latitude,
        startLng: currentLocation?.longitude,
      );

      if (mounted) {
        context.go('/journey/active');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start journey: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _onQuickStart(String label) async {
    double? lat;
    double? lng;

    if (label == 'Home') {
      lat = _homeLat;
      lng = _homeLng;
    } else {
      lat = _workLat;
      lng = _workLng;
    }

    if (lat == null || lng == null) {
      // Prompt user to set this destination.
      await _showSetDestinationDialog(label);
      return;
    }

    await _startJourney(destLat: lat, destLng: lng, destLabel: label);
  }

  Future<void> _showSetDestinationDialog(String label) async {
    final latController = TextEditingController();
    final lngController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Set $label location'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the coordinates for your $label destination. '
                'You can update this later in settings.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: latController,
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: 'e.g. 48.8566',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: lngController,
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: 'e.g. 2.3522',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      final lat = double.tryParse(latController.text);
      final lng = double.tryParse(lngController.text);

      if (lat != null && lng != null) {
        final key = label.toLowerCase();
        await _saveDestination(key, lat, lng);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$label location saved')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invalid coordinates')),
          );
        }
      }
    }

    latController.dispose();
    lngController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Safe Journey'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),

              // Header
              Text(
                'Share your trip',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your trusted contacts will see your live location until '
                'you arrive safely.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Quick-start destinations
              Text(
                'Quick start',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickDestinationCard(
                      icon: Icons.home_outlined,
                      label: 'Home',
                      isSet: _homeLat != null,
                      onTap: () => _onQuickStart('Home'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickDestinationCard(
                      icon: Icons.work_outline,
                      label: 'Work',
                      isSet: _workLat != null,
                      onTap: () => _onQuickStart('Work'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Duration selector
              Text(
                'Trip duration',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: _durations.map((minutes) {
                  final isSelected = _selectedMinutes == minutes;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text('${minutes}m'),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() => _selectedMinutes = minutes);
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),

              const Spacer(),

              // Start button
              FilledButton.icon(
                onPressed: _isStarting ? null : () => _onQuickStart('Home'),
                icon: _isStarting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.navigation_outlined),
                label: Text(_isStarting ? 'Starting...' : 'Start journey'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickDestinationCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final VoidCallback onTap;

  const _QuickDestinationCard({
    required this.icon,
    required this.label,
    required this.isSet,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSet
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isSet) ...[
                const SizedBox(height: 4),
                Text(
                  'Tap to set',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
