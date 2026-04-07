import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
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
    final addressController = TextEditingController();
    bool isSearching = false;
    String? errorText;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Set $label location'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Type your $label address and we\'ll find it for you.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: addressController,
                    decoration: InputDecoration(
                      labelText: 'Address',
                      hintText: 'e.g. 123 Main St, City',
                      prefixIcon: const Icon(Icons.location_on_outlined),
                      errorText: errorText,
                      suffixIcon: isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) {
                      // Allow pressing enter to save
                      Navigator.of(context).pop(true);
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.my_location,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            setDialogState(() => isSearching = true);
                            try {
                              final locationService =
                                  context.read<LocationService>();
                              final pos =
                                  await locationService.getCurrentLocation();
                              if (pos != null) {
                                addressController.text =
                                    'Current location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
                              }
                            } catch (_) {
                              setDialogState(() =>
                                  errorText = 'Could not get current location');
                            } finally {
                              setDialogState(() => isSearching = false);
                            }
                          },
                          child: Text(
                            'Use my current location',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSearching
                      ? null
                      : () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && addressController.text.isNotEmpty) {
      final address = addressController.text;

      // Check if it's "Current location (lat, lng)" format
      final currentLocRegex =
          RegExp(r'Current location \(([-\d.]+), ([-\d.]+)\)');
      final match = currentLocRegex.firstMatch(address);

      double? lat;
      double? lng;

      if (match != null) {
        lat = double.tryParse(match.group(1)!);
        lng = double.tryParse(match.group(2)!);
      } else {
        // Use geocoding to convert address to coordinates
        try {
          final locations = await _geocodeAddress(address);
          if (locations != null) {
            lat = locations.$1;
            lng = locations.$2;
          }
        } catch (_) {
          // Geocoding failed
        }
      }

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
            const SnackBar(
                content: Text('Could not find that address. Please try again.')),
          );
        }
      }
    }

    addressController.dispose();
  }

  /// Convert an address string to lat/lng coordinates using geocoding.
  Future<(double, double)?> _geocodeAddress(String address) async {
    try {
      // Use the geocoding package if available, otherwise use a simple
      // HTTP-based geocoding with OpenStreetMap Nominatim (free, no API key).
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(address)}'
        '&format=json&limit=1',
      );

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SafeCircle-App'},
      );
      if (response.statusCode != 200) return null;
      final results = jsonDecode(response.body) as List;

      if (results.isNotEmpty) {
        final first = results[0] as Map<String, dynamic>;
        final lat = double.parse(first['lat'] as String);
        final lng = double.parse(first['lon'] as String);
        return (lat, lng);
      }
    } catch (e) {
      debugPrint('Geocoding failed: $e');
    }
    return null;
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
