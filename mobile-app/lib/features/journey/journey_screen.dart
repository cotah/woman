import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
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
  String? _selectedDestination; // 'Home' or 'Work' — which is selected to start
  final _durationController = TextEditingController(text: '30');

  // Saved destination coords (persisted via SharedPreferences).
  double? _homeLat;
  double? _homeLng;
  double? _workLat;
  double? _workLng;

  @override
  void initState() {
    super.initState();
    _loadSavedDestinations();
    _durationController.addListener(_onDurationChanged);
  }

  void _onDurationChanged() {
    final value = int.tryParse(_durationController.text);
    if (value != null && value >= 5 && value <= 480) {
      setState(() => _selectedMinutes = value);
    }
  }

  @override
  void dispose() {
    _durationController.removeListener(_onDurationChanged);
    _durationController.dispose();
    super.dispose();
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

  /// Called when user taps Home or Work card — only selects destination.
  /// If not yet configured, opens the dialog to set the address.
  Future<void> _onSelectDestination(String label) async {
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
      // Prompt user to set this destination first.
      await _showSetDestinationDialog(label);
      // After setting, auto-select it
      if (label == 'Home' && _homeLat != null) {
        setState(() => _selectedDestination = 'Home');
      } else if (label == 'Work' && _workLat != null) {
        setState(() => _selectedDestination = 'Work');
      }
      return;
    }

    // Just select, don't start
    setState(() => _selectedDestination = label);
  }

  /// Called when user taps "Start Journey" button.
  Future<void> _onStartJourneyPressed() async {
    final dest = _selectedDestination;

    if (dest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Home or Work first.')),
      );
      return;
    }

    double? lat;
    double? lng;

    if (dest == 'Home') {
      lat = _homeLat;
      lng = _homeLng;
    } else {
      lat = _workLat;
      lng = _workLng;
    }

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please set your $dest address first.')),
      );
      return;
    }

    await _startJourney(destLat: lat, destLng: lng, destLabel: dest);
  }

  /// Debounce timer for address autocomplete
  Timer? _autocompleteTimer;

  /// Search Nominatim for address suggestions
  Future<List<Map<String, dynamic>>> _searchAddresses(String query) async {
    if (query.length < 3) return [];
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=5&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SafeCircle-App'},
      );
      if (response.statusCode != 200) return [];
      final results = jsonDecode(response.body) as List;
      return results.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  Future<void> _showSetDestinationDialog(String label) async {
    final addressController = TextEditingController();
    bool isSearching = false;
    String? errorText;
    List<Map<String, dynamic>> suggestions = [];
    // Store selected coordinates from autocomplete
    double? selectedLat;
    double? selectedLng;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Set $label location'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Type your $label address and pick from the suggestions.',
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
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        _autocompleteTimer?.cancel();
                        if (value.length < 3) {
                          setDialogState(() => suggestions = []);
                          return;
                        }
                        // Debounce: wait 500ms after user stops typing
                        _autocompleteTimer =
                            Timer(const Duration(milliseconds: 500), () async {
                          setDialogState(() => isSearching = true);
                          final results = await _searchAddresses(value);
                          setDialogState(() {
                            suggestions = results;
                            isSearching = false;
                          });
                        });
                      },
                    ),

                    // Suggestions list
                    if (suggestions.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 180),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: suggestions.length,
                          itemBuilder: (context, index) {
                            final s = suggestions[index];
                            final displayName =
                                s['display_name'] as String? ?? '';
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place, size: 20),
                              title: Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              onTap: () {
                                addressController.text = displayName;
                                selectedLat =
                                    double.tryParse(s['lat'] as String? ?? '');
                                selectedLng =
                                    double.tryParse(s['lon'] as String? ?? '');
                                setDialogState(() {
                                  suggestions = [];
                                  errorText = null;
                                });
                              },
                            );
                          },
                        ),
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
                                  selectedLat = pos.latitude;
                                  selectedLng = pos.longitude;
                                  addressController.text =
                                      'Current location (${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)})';
                                  setDialogState(() => suggestions = []);
                                }
                              } catch (_) {
                                setDialogState(() => errorText =
                                    'Could not get current location');
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

    _autocompleteTimer?.cancel();

    if (result == true && addressController.text.isNotEmpty) {
      double? lat = selectedLat;
      double? lng = selectedLng;

      // If user typed manually without selecting a suggestion, geocode it
      if (lat == null || lng == null) {
        final address = addressController.text;
        final currentLocRegex =
            RegExp(r'Current location \(([-\d.]+), ([-\d.]+)\)');
        final match = currentLocRegex.firstMatch(address);

        if (match != null) {
          lat = double.tryParse(match.group(1)!);
          lng = double.tryParse(match.group(2)!);
        } else {
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
                content:
                    Text('Could not find that address. Please try again.')),
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

  Widget _buildMapPreview() {
    final token = AppConfig.instance.mapboxToken;
    final markers = <Marker>[];
    final points = <LatLng>[];

    if (_homeLat != null && _homeLng != null) {
      final p = LatLng(_homeLat!, _homeLng!);
      points.add(p);
      markers.add(Marker(
        point: p,
        width: 40,
        height: 40,
        child: const Icon(Icons.home, color: Colors.deepPurple, size: 32),
      ));
    }

    if (_workLat != null && _workLng != null) {
      final p = LatLng(_workLat!, _workLng!);
      points.add(p);
      markers.add(Marker(
        point: p,
        width: 40,
        height: 40,
        child: const Icon(Icons.work, color: Colors.teal, size: 32),
      ));
    }

    final center = points.first;
    final useMapbox = token.isNotEmpty && !token.startsWith('YOUR_');

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: points.length > 1 ? 12.0 : 14.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: useMapbox
              ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}@2x?access_token=$token'
              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.safecircle.app',
          maxZoom: 19,
        ),
        MarkerLayer(markers: markers),
      ],
    );
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
        child: Column(
          children: [
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
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

                    // Destination selector
                    Text(
                      'Where are you going?',
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
                            isSelected: _selectedDestination == 'Home',
                            onTap: () => _onSelectDestination('Home'),
                            onLongPress: () => _showSetDestinationDialog('Home'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickDestinationCard(
                            icon: Icons.work_outline,
                            label: 'Work',
                            isSet: _workLat != null,
                            isSelected: _selectedDestination == 'Work',
                            onTap: () => _onSelectDestination('Work'),
                            onLongPress: () => _showSetDestinationDialog('Work'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Map preview (shown when at least one destination is saved)
                    if (_homeLat != null || _workLat != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          height: 180,
                          child: _buildMapPreview(),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Duration selector — manual input
                    Text(
                      'Trip duration',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _durationController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'minutes',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _selectedMinutes.clamp(5, 480).toDouble(),
                      min: 5,
                      max: 480,
                      divisions: 95,
                      label: '${_selectedMinutes}min',
                      onChanged: (value) {
                        final minutes = value.round();
                        setState(() {
                          _selectedMinutes = minutes;
                          _durationController.removeListener(_onDurationChanged);
                          _durationController.text = minutes.toString();
                          _durationController.addListener(_onDurationChanged);
                        });
                      },
                    ),
                    Text(
                      _selectedMinutes < 60
                          ? '$_selectedMinutes min'
                          : '${_selectedMinutes ~/ 60}h ${_selectedMinutes % 60}min',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // Start button — always visible at the bottom
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: FilledButton.icon(
                onPressed: _isStarting ? null : _onStartJourneyPressed,
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
                label: Text(
                  _isStarting
                      ? 'Starting...'
                      : _selectedDestination != null
                          ? 'Start journey to $_selectedDestination'
                          : 'Start journey',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickDestinationCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSet;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _QuickDestinationCard({
    super.key,
    required this.icon,
    required this.label,
    required this.isSet,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor = isSelected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: theme.colorScheme.primary, width: 2)
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: textColor),
            const SizedBox(height: 8),
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (!isSet) ...[
              const SizedBox(height: 4),
              Text(
                'Long press to set',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withOpacity(0.6),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}