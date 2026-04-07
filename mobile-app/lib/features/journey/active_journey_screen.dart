import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/models/journey.dart';
import '../../core/models/location_update.dart';
import '../../core/services/journey_service.dart';
import '../../core/services/location_service.dart';

/// Displays the active Safe Journey with a countdown timer,
/// destination info, and actions to complete, extend, or cancel.
class ActiveJourneyScreen extends StatefulWidget {
  const ActiveJourneyScreen({super.key});

  @override
  State<ActiveJourneyScreen> createState() => _ActiveJourneyScreenState();
}

class _ActiveJourneyScreenState extends State<ActiveJourneyScreen> {
  Timer? _tickTimer;
  final MapController _mapController = MapController();
  StreamSubscription<LocationUpdate>? _locationSub;
  LatLng? _currentLatLng;

  @override
  void initState() {
    super.initState();

    // Tick every second to update the countdown display.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    // Listen to real-time location updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locationService = context.read<LocationService>();
      final lastPos = locationService.lastPosition;
      if (lastPos != null) {
        _currentLatLng = LatLng(lastPos.latitude, lastPos.longitude);
      }

      _locationSub = locationService.locationStream.listen((update) {
        if (mounted) {
          setState(() {
            _currentLatLng = LatLng(update.latitude, update.longitude);
          });
        }
      });

      // Also get current location immediately
      locationService.getCurrentLocation().then((loc) {
        if (loc != null && mounted) {
          setState(() {
            _currentLatLng = LatLng(loc.latitude, loc.longitude);
          });
        }
      });

      // Fetch active journey on load in case we navigated here directly.
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
    _locationSub?.cancel();
    _mapController.dispose();
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not complete journey. Please try again.')),
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not extend time. Please try again.')),
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
    } on DioException catch (e) {
      // If 400, the journey likely already expired or was completed
      if (e.response?.statusCode == 400 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Journey already ended. Returning to home.'),
          ),
        );
        // Refresh journey state and go home
        await context.read<JourneyService>().getActiveJourney();
        if (mounted) context.go('/home');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel journey. Please try again.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel journey. Please try again.'),
          ),
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

            // Build map markers and route
            final destLatLng = LatLng(journey.destLatitude, journey.destLongitude);
            final markers = <Marker>[];

            // Current location marker (added FIRST so destination renders on top)
            if (_currentLatLng != null) {
              markers.add(Marker(
                point: _currentLatLng!,
                width: 44,
                height: 44,
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withOpacity(0.3),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 22),
                ),
              ));
            }

            // Destination marker (added LAST so it renders on top of person)
            markers.add(Marker(
              point: destLatLng,
              width: 48,
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.flag, color: Colors.white, size: 24),
              ),
            ));

            // Route line from current position to destination
            final polylines = <Polyline>[];
            if (_currentLatLng != null) {
              polylines.add(Polyline(
                points: [_currentLatLng!, destLatLng],
                strokeWidth: 3.0,
                color: theme.colorScheme.primary.withOpacity(0.6),
                isDotted: true,
              ));
            }

            // Calculate zoom to fit both markers
            final mapCenter = _currentLatLng ?? destLatLng;
            double initialZoom = 14.0;
            if (_currentLatLng != null) {
              final distance = const Distance().as(
                LengthUnit.Meter,
                _currentLatLng!,
                destLatLng,
              );
              // Adjust zoom based on distance between points
              if (distance < 500) {
                initialZoom = 16.0;
              } else if (distance < 2000) {
                initialZoom = 14.0;
              } else if (distance < 5000) {
                initialZoom = 13.0;
              } else if (distance < 10000) {
                initialZoom = 12.0;
              } else {
                initialZoom = 11.0;
              }
            }
            final token = AppConfig.instance.mapboxToken;
            final useMapbox = token.isNotEmpty && !token.startsWith('YOUR_');

            return SafeArea(
              child: Column(
                children: [
                  // Live map (top half)
                  Expanded(
                    flex: 5,
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: mapCenter,
                            initialZoom: initialZoom,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: useMapbox
                                  ? 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/{z}/{x}/{y}@2x?access_token=$token'
                                  : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.safecircle.app',
                              maxZoom: 19,
                            ),
                            PolylineLayer(polylines: polylines),
                            MarkerLayer(markers: markers),
                          ],
                        ),

                        // Timer overlay on top of map
                        Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 10),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isExpired
                                        ? Icons.warning_amber_rounded
                                        : Icons.shield_outlined,
                                    size: 20,
                                    color: isExpired
                                        ? Colors.white
                                        : theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDuration(remaining),
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontFeatures: [
                                        const FontFeature.tabularFigures()
                                      ],
                                      color: isExpired
                                          ? Colors.white
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Destination label overlay
                        if (journey.destLabel != null)
                          Positioned(
                            top: 60,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface
                                      .withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.place_outlined,
                                        size: 16,
                                        color: theme
                                            .colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(journey.destLabel!,
                                        style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Re-center button
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            heroTag: 'recenter',
                            onPressed: () {
                              if (_currentLatLng != null) {
                                _mapController.move(_currentLatLng!, 15.0);
                              }
                            },
                            child: const Icon(Icons.my_location, size: 20),
                          ),
                        ),

                        // Sharing status overlay
                        Positioned(
                          bottom: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.share_location,
                                    size: 14,
                                    color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Sharing location',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action buttons (bottom)
                  Expanded(
                    flex: 3,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isExpired
                                ? 'Time expired - contacts may be alerted'
                                : 'Your contacts can see your trip',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isExpired
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),

                          FilledButton.icon(
                            onPressed: _onArrived,
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('I arrived safely'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                          ),
                          const SizedBox(height: 8),

                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _onNeedMoreTime,
                                  child: const Text('+10 min'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextButton(
                                  onPressed: _onCancel,
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                  ),
                                  child: const Text('Cancel'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
