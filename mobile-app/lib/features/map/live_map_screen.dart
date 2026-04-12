import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/services/location_tracker_service.dart';
import '../../core/services/learned_places_service.dart';
import '../../core/services/geofence_service.dart';
import '../../core/services/contacts_service.dart';

/// Live map screen — Life360-style real-time tracking view.
///
/// Shows:
/// - User's current location with animated pulse
/// - Learned places (home, work, etc.) with labeled markers
/// - Movement trail for the last 24 hours
/// - Current place info: name, time spent here
/// - Bottom sheet with place details
class LiveMapScreen extends StatefulWidget {
  const LiveMapScreen({super.key});

  @override
  State<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends State<LiveMapScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  late AnimationController _pulseController;
  Timer? _refreshTimer;
  Timer? _timeAtLocationTimer;

  bool _isFollowing = true;
  bool _showTrail = true;
  bool _showPlaces = true;
  bool _showGeofences = true;
  DateTime? _arrivedAtCurrent;
  String _timeAtLocation = '';

  // Direct position (fetched on map open, independent of tracker)
  Position? _directPosition;
  bool _isLoadingLocation = true;
  String? _locationError;

  // Trail data
  List<LocationSnapshot> _trail = [];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    // Refresh trail and position every 30s
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) {
        _refreshTrail();
        _requestLocation();
      },
    );

    // Update "time at location" counter every second
    _timeAtLocationTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTimeAtLocation(),
    );

    // Request location immediately when map opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestLocation();
      _refreshTrail();
      _detectArrivalTime();
    });
  }

  /// Request location directly from GPS — independent of tracker service.
  Future<void> _requestLocation() async {
    try {
      // Check & request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationError = 'Location permission denied. '
                'Please enable it in your device settings.';
          });
        }
        return;
      }

      // Check if location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _isLoadingLocation = false;
            _locationError = 'Location services are disabled. '
                'Please enable GPS on your device.';
          });
        }
        return;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      if (mounted) {
        setState(() {
          _directPosition = position;
          _isLoadingLocation = false;
          _locationError = null;
        });
      }

      debugPrint('[LiveMap] Got position: '
          '${position.latitude}, ${position.longitude}');
    } catch (e) {
      debugPrint('[LiveMap] Location error: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _locationError = 'Could not get your location. '
              'Check GPS and try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _refreshTimer?.cancel();
    _timeAtLocationTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTrail() async {
    final tracker = context.read<LocationTrackerService>();
    final history = await tracker.getRecentHistory(hours: 24);
    if (mounted) {
      setState(() => _trail = history);
    }
  }

  void _detectArrivalTime() {
    final places = context.read<LearnedPlacesService>();
    if (places.currentPlace != null) {
      // Use last visited as arrival approximation
      _arrivedAtCurrent = places.currentPlace!.lastVisited;
    } else {
      // If at a new place, use the timestamp of last snapshot
      final tracker = context.read<LocationTrackerService>();
      if (tracker.lastPosition != null) {
        _arrivedAtCurrent = DateTime.now();
      }
    }
    _updateTimeAtLocation();
  }

  void _updateTimeAtLocation() {
    if (_arrivedAtCurrent == null) {
      if (mounted) setState(() => _timeAtLocation = '');
      return;
    }

    final diff = DateTime.now().difference(_arrivedAtCurrent!);
    String formatted;

    if (diff.inDays > 0) {
      formatted = '${diff.inDays}d ${diff.inHours.remainder(24)}h';
    } else if (diff.inHours > 0) {
      formatted = '${diff.inHours}h ${diff.inMinutes.remainder(60)}min';
    } else if (diff.inMinutes > 0) {
      formatted = '${diff.inMinutes}min';
    } else {
      formatted = 'Just arrived';
    }

    if (mounted) setState(() => _timeAtLocation = formatted);
  }

  /// Get the best available position (tracker or direct).
  Position? _getBestPosition() {
    final tracker = context.read<LocationTrackerService>();
    return tracker.lastPosition ?? _directPosition;
  }

  void _centerOnUser() {
    final pos = _getBestPosition();
    if (pos != null) {
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        16.0,
      );
      setState(() => _isFollowing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracker = context.watch<LocationTrackerService>();
    final places = context.watch<LearnedPlacesService>();
    final geofenceService = context.watch<GeofenceService>();

    // Use tracker position first, fall back to directly-fetched position
    final hasPosition =
        tracker.lastPosition != null || _directPosition != null;

    return Scaffold(
      body: Stack(
        children: [
          // ── The Map ──
          if (hasPosition)
            _buildMap(theme, tracker, places, geofenceService)
          else
            _buildNoLocationState(theme),

          // ── Top Bar (overlay) ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  _CircleButton(
                    icon: Icons.visibility,
                    onTap: () => setState(() => _showTrail = !_showTrail),
                    isActive: _showTrail,
                  ),
                  const SizedBox(width: 8),
                  _CircleButton(
                    icon: Icons.location_on,
                    onTap: () => setState(() => _showPlaces = !_showPlaces),
                    isActive: _showPlaces,
                  ),
                  const SizedBox(width: 8),
                  _CircleButton(
                    icon: Icons.shield,
                    onTap: () =>
                        setState(() => _showGeofences = !_showGeofences),
                    isActive: _showGeofences,
                  ),
                ],
              ),
            ),
          ),

          // ── Re-center button ──
          if (hasPosition && !_isFollowing)
            Positioned(
              right: 16,
              bottom: 220,
              child: FloatingActionButton.small(
                heroTag: 'recenter',
                onPressed: _centerOnUser,
                backgroundColor: theme.colorScheme.surface,
                child: Icon(Icons.my_location,
                    color: theme.colorScheme.primary),
              ),
            ),

          // ── Bottom Info Sheet ──
          if (hasPosition)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomSheet(theme, tracker, places),
            ),
        ],
      ),
    );
  }

  Widget _buildMap(ThemeData theme, LocationTrackerService tracker,
      LearnedPlacesService places, GeofenceService geofenceService) {
    final pos = tracker.lastPosition ?? _directPosition!;
    final userLatLng = LatLng(pos.latitude, pos.longitude);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: userLatLng,
        initialZoom: 16.0,
        onPositionChanged: (pos, hasGesture) {
          if (hasGesture) {
            setState(() => _isFollowing = false);
          }
        },
      ),
      children: [
        // Map tiles — Mapbox dark style (Waze-like) with OSM fallback
        Builder(builder: (context) {
          final token = AppConfig.instance.mapboxToken;
          final useMapbox = token.isNotEmpty && !token.startsWith('YOUR_');
          final isDark = Theme.of(context).brightness == Brightness.dark;

          // Mapbox styles: dark-v11 for dark theme, navigation-night-v1 for Waze-like
          final mapboxStyle = isDark ? 'navigation-night-v1' : 'navigation-day-v1';

          return TileLayer(
            urlTemplate: useMapbox
                ? 'https://api.mapbox.com/styles/v1/mapbox/$mapboxStyle/tiles/{z}/{x}/{y}@2x?access_token=$token'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.safecircle.app',
            maxZoom: 19,
            tileSize: useMapbox ? 512 : 256,
            zoomOffset: useMapbox ? -1 : 0,
          );
        }),

        // Movement trail (polyline)
        if (_showTrail && _trail.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _trail
                    .map((s) => LatLng(s.latitude, s.longitude))
                    .toList(),
                strokeWidth: 3.0,
                color: theme.colorScheme.primary.withValues(alpha: 0.6),
              ),
            ],
          ),

        // Trail dots (each snapshot point)
        if (_showTrail && _trail.isNotEmpty)
          CircleLayer(
            circles: _trail.map((s) {
              return CircleMarker(
                point: LatLng(s.latitude, s.longitude),
                radius: 3,
                color: theme.colorScheme.primary.withValues(alpha: 0.4),
                borderColor: Colors.transparent,
                borderStrokeWidth: 0,
              );
            }).toList(),
          ),

        // Geofence zones (semi-transparent circles)
        if (_showGeofences && geofenceService.geofences.isNotEmpty)
          CircleLayer(
            circles: geofenceService.geofences
                .where((g) => g.isActive)
                .map((g) {
              Color fillColor;
              Color borderColor;

              switch (g.type) {
                case GeofenceType.safe:
                  fillColor = Colors.green.withValues(alpha: 0.1);
                  borderColor = Colors.green.withValues(alpha: 0.5);
                  break;
                case GeofenceType.watch:
                  fillColor = Colors.red.withValues(alpha: 0.1);
                  borderColor = Colors.red.withValues(alpha: 0.5);
                  break;
                case GeofenceType.custom:
                  fillColor = Colors.blue.withValues(alpha: 0.1);
                  borderColor = Colors.blue.withValues(alpha: 0.5);
                  break;
              }

              return CircleMarker(
                point: LatLng(g.latitude, g.longitude),
                radius: g.radiusMeters,
                useRadiusInMeter: true,
                color: fillColor,
                borderColor: borderColor,
                borderStrokeWidth: 2,
              );
            }).toList(),
          ),

        // Learned places markers
        if (_showPlaces && places.places.isNotEmpty)
          MarkerLayer(
            markers: places.places.map((place) {
              return Marker(
                point: LatLng(place.latitude, place.longitude),
                width: 120,
                height: 60,
                child: _PlaceMarker(place: place),
              );
            }).toList(),
          ),

        // User pulse ring (animated) — Waze-style glow
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final scale = 1.0 + (_pulseController.value * 0.6);
            final opacity = 1.0 - _pulseController.value;
            return CircleLayer(
              circles: [
                CircleMarker(
                  point: userLatLng,
                  radius: 24 * scale,
                  color: const Color(0xFF6C47FF)
                      .withValues(alpha: 0.25 * opacity),
                  borderColor: Colors.transparent,
                  borderStrokeWidth: 0,
                ),
              ],
            );
          },
        ),

        // User avatar marker — Waze-style
        MarkerLayer(
          markers: [
            Marker(
              point: userLatLng,
              width: 48,
              height: 48,
              child: const _UserAvatarMarker(),
            ),
          ],
        ),

        // Nearby contacts layer (shows trusted contacts who share location)
        // This will be populated when contacts share their location
        // For now it shows an empty layer — ready for Phase 2
        MarkerLayer(
          markers: _buildContactMarkers(),
        ),
      ],
    );
  }

  Widget _buildBottomSheet(ThemeData theme, LocationTrackerService tracker,
      LearnedPlacesService places) {
    final currentPlace = places.currentPlace;
    final isNewPlace = places.isAtNewPlace;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Location info row
          Row(
            children: [
              // Place icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isNewPlace
                      ? Colors.orange.withValues(alpha: 0.15)
                      : currentPlace != null
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getPlaceIcon(currentPlace),
                  color: isNewPlace
                      ? Colors.orange
                      : currentPlace != null
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),

              // Place name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getPlaceName(currentPlace, isNewPlace),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _getPlaceSubtitle(currentPlace, isNewPlace, tracker),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Time at location badge
              if (_timeAtLocation.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        _timeAtLocation,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            children: [
              _StatChip(
                icon: Icons.place,
                label: '${places.places.length} places',
                theme: theme,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: Icons.timeline,
                label: '${_trail.length} points (24h)',
                theme: theme,
              ),
              const SizedBox(width: 8),
              _StatChip(
                icon: tracker.isTracking
                    ? Icons.sensors
                    : Icons.sensors_off,
                label: tracker.isTracking ? 'Live' : 'Off',
                theme: theme,
                color: tracker.isTracking ? Colors.green : Colors.grey,
              ),
            ],
          ),

          // New place alert
          if (isNewPlace) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.explore, color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You\'re at a new place. Is everything OK?',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniButton(
                    label: 'I\'m safe',
                    color: Colors.green,
                    onTap: () {
                      final placesService =
                          context.read<LearnedPlacesService>();
                      final pos = tracker.lastPosition ?? _directPosition;
                      if (pos != null) {
                        placesService.confirmPlaceSafe(
                          latitude: pos.latitude,
                          longitude: pos.longitude,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNoLocationState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoadingLocation) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'Getting your location...',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please allow location access when prompted',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Icon(Icons.location_off,
                  size: 64, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'Location unavailable',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_locationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _locationError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _isLoadingLocation = true;
                    _locationError = null;
                  });
                  _requestLocation();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getPlaceIcon(LearnedPlace? place) {
    if (place == null) return Icons.location_on;
    final label = (place.label ?? place.autoLabel ?? '').toLowerCase();
    if (label.contains('home')) return Icons.home;
    if (label.contains('work')) return Icons.work;
    if (label.contains('gym')) return Icons.fitness_center;
    if (label.contains('school') || label.contains('uni')) {
      return Icons.school;
    }
    if (label.contains('shop') || label.contains('store') ||
        label.contains('mall')) return Icons.shopping_bag;
    if (label.contains('restaurant') || label.contains('food')) {
      return Icons.restaurant;
    }
    return Icons.place;
  }

  String _getPlaceName(LearnedPlace? place, bool isNew) {
    if (isNew) return 'New place';
    if (place != null) {
      return place.label ?? place.autoLabel ?? 'Known place';
    }
    return 'Current location';
  }

  String _getPlaceSubtitle(
      LearnedPlace? place, bool isNew, LocationTrackerService tracker) {
    if (isNew) return 'Not in your safe zones yet';
    if (place != null) {
      return 'Visited ${place.visitCount} times';
    }
    final pos = tracker.lastPosition ?? _directPosition;
    if (pos != null) {
      return '${pos.latitude.toStringAsFixed(4)}, '
          '${pos.longitude.toStringAsFixed(4)}';
    }
    return 'Location unavailable';
  }

  /// Build markers for trusted contacts who share their location.
  /// Returns empty list for now — ready for Phase 2 contact sharing.
  List<Marker> _buildContactMarkers() {
    // Phase 2: fetch shared locations from ContactsService and
    // return a Marker for each contact with a _ContactAvatarMarker child.
    return [];
  }
}

// ─────────────────────────────────────────────────────────
// Helper Widgets
// ─────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;

  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.isActive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isActive
              ? const Color(0xFF6C47FF)
              : const Color(0xCC000000),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _PlaceMarker extends StatelessWidget {
  final LearnedPlace place;

  const _PlaceMarker({required this.place});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = place.label ?? place.autoLabel ?? 'Place';
    final isHome = label.toLowerCase().contains('home');
    final isWork = label.toLowerCase().contains('work');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Icon(
          isHome
              ? Icons.home
              : isWork
                  ? Icons.work
                  : Icons.place,
          color: place.isConfirmedSafe
              ? Colors.green
              : theme.colorScheme.primary,
          size: 28,
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  final Color? color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.theme,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 14,
              color: color ?? theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color ?? theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Waze-style user avatar marker — circular avatar with directional pointer.
class _UserAvatarMarker extends StatelessWidget {
  const _UserAvatarMarker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const avatarColor = Color(0xFF6C47FF); // SafeCircle purple

    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Directional pointer (triangle at the bottom)
          Positioned(
            bottom: 0,
            child: CustomPaint(
              size: const Size(16, 8),
              painter: _PointerPainter(color: avatarColor),
            ),
          ),
          // White border ring
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          // Colored inner circle with person icon
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8B6DFF), avatarColor],
              ),
            ),
            child: const Icon(
              Icons.person,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints a small downward-pointing triangle (direction pointer).
class _PointerPainter extends CustomPainter {
  final Color color;
  _PointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MiniButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MiniButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
