import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_tracker_service.dart';
import 'learned_places_service.dart';

/// Geofence type — what kind of zone this is.
enum GeofenceType {
  /// Safe zone — user is expected to be here (home, work, etc.)
  safe,

  /// Watch zone — alert when user enters (flagged or unknown areas)
  watch,

  /// Custom zone — user-defined area with custom rules
  custom,
}

/// What happened with the geofence.
enum GeofenceEvent {
  /// User entered the geofenced area
  entered,

  /// User exited the geofenced area
  exited,
}

/// A single geofence definition.
class Geofence {
  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// Radius in meters
  final double radiusMeters;
  final GeofenceType type;

  /// Whether to alert on entry
  bool alertOnEntry;

  /// Whether to alert on exit
  bool alertOnExit;

  /// Is the user currently inside?
  bool isInside;

  /// When the user last entered this zone
  DateTime? lastEntered;

  /// When the user last exited this zone
  DateTime? lastExited;

  /// Whether this geofence is active
  bool isActive;

  /// Linked learned place ID (if auto-created from a learned place)
  String? linkedPlaceId;

  Geofence({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200,
    this.type = GeofenceType.safe,
    this.alertOnEntry = false,
    this.alertOnExit = true,
    this.isInside = false,
    this.lastEntered,
    this.lastExited,
    this.isActive = true,
    this.linkedPlaceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
        'type': type.name,
        'alertOnEntry': alertOnEntry,
        'alertOnExit': alertOnExit,
        'isInside': isInside,
        'lastEntered': lastEntered?.toIso8601String(),
        'lastExited': lastExited?.toIso8601String(),
        'isActive': isActive,
        'linkedPlaceId': linkedPlaceId,
      };

  factory Geofence.fromJson(Map<String, dynamic> json) {
    return Geofence(
      id: json['id'] as String,
      name: json['name'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200,
      type: GeofenceType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => GeofenceType.safe,
      ),
      alertOnEntry: json['alertOnEntry'] as bool? ?? false,
      alertOnExit: json['alertOnExit'] as bool? ?? true,
      isInside: json['isInside'] as bool? ?? false,
      lastEntered: json['lastEntered'] != null
          ? DateTime.parse(json['lastEntered'] as String)
          : null,
      lastExited: json['lastExited'] != null
          ? DateTime.parse(json['lastExited'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
      linkedPlaceId: json['linkedPlaceId'] as String?,
    );
  }
}

/// Geofence monitoring service.
///
/// Monitors the user's location against defined geofence zones and
/// fires callbacks when the user enters or exits a zone.
///
/// ## How It Works
///
/// 1. Listens to location updates from [LocationTrackerService]
/// 2. For each update, checks distance to all active geofences
/// 3. Detects entry (was outside → now inside) and exit (was inside → now outside)
/// 4. Fires callbacks for the app to show notifications or trigger alerts
/// 5. Auto-syncs with [LearnedPlacesService] to create geofences from learned places
///
/// ## Smart Behaviors
///
/// - Safe zones (home, work): alert when user EXITS unexpectedly
/// - Watch zones (flagged places): alert when user ENTERS
/// - Hysteresis: requires crossing the boundary by 20m to prevent flickering
class GeofenceService extends ChangeNotifier {
  final LocationTrackerService _tracker;
  final LearnedPlacesService _learnedPlaces;

  Timer? _checkTimer;
  List<Geofence> _geofences = [];
  bool _isMonitoring = false;

  /// Buffer zone in meters to prevent rapid enter/exit flickering.
  /// User must cross boundary + hysteresis to trigger event.
  static const double _hysteresisMeters = 20;

  /// How often to check geofences (in seconds).
  static const int _checkIntervalSeconds = 30;

  /// Storage key.
  static const String _storageKey = 'safecircle_geofences';
  static const String _monitoringKey = 'safecircle_geofence_monitoring';

  /// Callback when a geofence event occurs.
  void Function(Geofence geofence, GeofenceEvent event)? onGeofenceEvent;

  List<Geofence> get geofences => List.unmodifiable(_geofences);
  bool get isMonitoring => _isMonitoring;

  GeofenceService({
    required LocationTrackerService tracker,
    required LearnedPlacesService learnedPlaces,
  })  : _tracker = tracker,
        _learnedPlaces = learnedPlaces;

  /// Initialize — load saved geofences and start monitoring if enabled.
  Future<void> initialize() async {
    await _loadGeofences();
    await _syncWithLearnedPlaces();

    final prefs = await SharedPreferences.getInstance();
    final wasMonitoring = prefs.getBool(_monitoringKey) ?? false;

    if (wasMonitoring) {
      await startMonitoring();
    }

    // Listen for new learned places to auto-create geofences
    _learnedPlaces.addListener(_onLearnedPlacesChanged);

    debugPrint('[Geofence] Initialized with ${_geofences.length} zones');
  }

  /// Start monitoring all active geofences.
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _isMonitoring = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monitoringKey, true);

    // Initial check
    _checkGeofences();

    // Periodic checks
    _checkTimer = Timer.periodic(
      const Duration(seconds: _checkIntervalSeconds),
      (_) => _checkGeofences(),
    );

    debugPrint('[Geofence] Monitoring started');
    notifyListeners();
  }

  /// Stop monitoring.
  Future<void> stopMonitoring() async {
    _checkTimer?.cancel();
    _checkTimer = null;
    _isMonitoring = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_monitoringKey, false);

    debugPrint('[Geofence] Monitoring stopped');
    notifyListeners();
  }

  /// Add a new geofence.
  Future<void> addGeofence(Geofence geofence) async {
    _geofences.add(geofence);
    await _saveGeofences();
    notifyListeners();
  }

  /// Remove a geofence by ID.
  Future<void> removeGeofence(String id) async {
    _geofences.removeWhere((g) => g.id == id);
    await _saveGeofences();
    notifyListeners();
  }

  /// Update a geofence.
  Future<void> updateGeofence(Geofence updated) async {
    final index = _geofences.indexWhere((g) => g.id == updated.id);
    if (index >= 0) {
      _geofences[index] = updated;
      await _saveGeofences();
      notifyListeners();
    }
  }

  /// Toggle a geofence active/inactive.
  Future<void> toggleGeofence(String id) async {
    final index = _geofences.indexWhere((g) => g.id == id);
    if (index >= 0) {
      _geofences[index].isActive = !_geofences[index].isActive;
      await _saveGeofences();
      notifyListeners();
    }
  }

  /// Create a geofence from a specific location.
  Future<Geofence> createGeofenceAt({
    required String name,
    required double latitude,
    required double longitude,
    double radiusMeters = 200,
    GeofenceType type = GeofenceType.safe,
    bool alertOnEntry = false,
    bool alertOnExit = true,
  }) async {
    final geofence = Geofence(
      id: 'gf_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      type: type,
      alertOnEntry: alertOnEntry,
      alertOnExit: alertOnExit,
    );

    await addGeofence(geofence);
    return geofence;
  }

  // ── Core Logic ──────────────────────────────────

  /// Check all active geofences against current location.
  void _checkGeofences() {
    final pos = _tracker.lastPosition;
    if (pos == null) return;

    for (final geofence in _geofences) {
      if (!geofence.isActive) continue;

      final distance = _haversineDistance(
        pos.latitude,
        pos.longitude,
        geofence.latitude,
        geofence.longitude,
      );

      final wasInside = geofence.isInside;

      if (wasInside) {
        // Currently inside — check for EXIT
        // Must go beyond radius + hysteresis to count as exit
        if (distance > geofence.radiusMeters + _hysteresisMeters) {
          geofence.isInside = false;
          geofence.lastExited = DateTime.now();

          debugPrint('[Geofence] EXIT: "${geofence.name}" '
              '(distance: ${distance.toStringAsFixed(0)}m)');

          if (geofence.alertOnExit) {
            onGeofenceEvent?.call(geofence, GeofenceEvent.exited);
          }
        }
      } else {
        // Currently outside — check for ENTRY
        // Must be within radius - hysteresis to count as entry
        final entryThreshold = geofence.radiusMeters - _hysteresisMeters;
        if (distance < (entryThreshold > 0 ? entryThreshold : geofence.radiusMeters)) {
          geofence.isInside = true;
          geofence.lastEntered = DateTime.now();

          debugPrint('[Geofence] ENTRY: "${geofence.name}" '
              '(distance: ${distance.toStringAsFixed(0)}m)');

          if (geofence.alertOnEntry) {
            onGeofenceEvent?.call(geofence, GeofenceEvent.entered);
          }
        }
      }
    }

    _saveGeofences();
    notifyListeners();
  }

  // ── Learned Places Sync ─────────────────────────

  void _onLearnedPlacesChanged() {
    _syncWithLearnedPlaces();
  }

  /// Auto-create geofences from learned places that have enough visits.
  Future<void> _syncWithLearnedPlaces() async {
    final places = _learnedPlaces.places;
    bool changed = false;

    for (final place in places) {
      // Only create geofences for places with 3+ visits or confirmed safe
      if (place.visitCount < 3 && !place.isConfirmedSafe) continue;

      // Check if we already have a geofence for this place
      final existing = _geofences.any((g) => g.linkedPlaceId == place.id);
      if (existing) continue;

      // Determine type and alert rules based on place characteristics
      GeofenceType type;
      bool alertOnEntry;
      bool alertOnExit;

      if (place.isFlagged) {
        // Flagged place → watch zone, alert on entry
        type = GeofenceType.watch;
        alertOnEntry = true;
        alertOnExit = false;
      } else {
        // Safe/normal place → safe zone, alert on exit
        type = GeofenceType.safe;
        alertOnEntry = false;
        alertOnExit = true;
      }

      final label = place.label ?? place.autoLabel ?? 'Place';
      final geofence = Geofence(
        id: 'gf_auto_${place.id}',
        name: label,
        latitude: place.latitude,
        longitude: place.longitude,
        radiusMeters: 200,
        type: type,
        alertOnEntry: alertOnEntry,
        alertOnExit: alertOnExit,
        linkedPlaceId: place.id,
      );

      _geofences.add(geofence);
      changed = true;

      debugPrint('[Geofence] Auto-created zone "$label" from learned place '
          '(type: ${type.name})');
    }

    if (changed) {
      await _saveGeofences();
      notifyListeners();
    }
  }

  // ── Distance Calculation ────────────────────────

  /// Haversine formula — distance between two coordinates in meters.
  static double _haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;

  // ── Persistence ─────────────────────────────────

  Future<void> _loadGeofences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? [];

      _geofences = raw.map((s) {
        final json = jsonDecode(s) as Map<String, dynamic>;
        return Geofence.fromJson(json);
      }).toList();
    } catch (e) {
      debugPrint('[Geofence] Failed to load: $e');
      _geofences = [];
    }
  }

  Future<void> _saveGeofences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = _geofences.map((g) => jsonEncode(g.toJson())).toList();
      await prefs.setStringList(_storageKey, raw);
    } catch (e) {
      debugPrint('[Geofence] Failed to save: $e');
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _learnedPlaces.removeListener(_onLearnedPlacesChanged);
    super.dispose();
  }
}
