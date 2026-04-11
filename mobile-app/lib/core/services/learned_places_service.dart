import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_tracker_service.dart';

/// AI-powered service that learns the user's frequent places.
///
/// How it works:
/// 1. Periodically analyzes location history from [LocationTrackerService]
/// 2. Clusters nearby locations into "places" (home, work, gym, etc.)
/// 3. Tracks visit frequency and time patterns for each place
/// 4. When the user visits a new/unknown place, triggers a safety check
/// 5. The user can confirm if the place is safe or flag it
/// 6. Over time, the AI builds a complete map of the user's safe zones
///
/// All processing happens locally on the device. No location data is
/// shared externally without explicit user action.
class LearnedPlacesService extends ChangeNotifier {
  final LocationTrackerService _tracker;

  Timer? _analysisTimer;
  List<LearnedPlace> _places = [];
  LearnedPlace? _currentPlace;
  bool _isAtNewPlace = false;

  /// Radius in meters to consider "same place".
  static const double _clusterRadiusMeters = 150;

  /// Minimum visits to consider a place "learned/known".
  static const int _minVisitsToLearn = 3;

  /// How often to run the analysis (in minutes).
  static const int _analysisIntervalMinutes = 10;

  /// Storage key.
  static const String _placesKey = 'safecircle_learned_places';

  /// Callback when user arrives at an unknown place.
  void Function(double lat, double lng)? onNewPlaceDetected;

  List<LearnedPlace> get places => List.unmodifiable(_places);
  LearnedPlace? get currentPlace => _currentPlace;
  bool get isAtNewPlace => _isAtNewPlace;

  LearnedPlacesService({required LocationTrackerService tracker})
      : _tracker = tracker;

  /// Initialize — load saved places and start periodic analysis.
  Future<void> initialize() async {
    await _loadPlaces();

    // Run initial analysis
    await analyzeHistory();

    // Periodic analysis
    _analysisTimer = Timer.periodic(
      const Duration(minutes: _analysisIntervalMinutes),
      (_) => _checkCurrentLocation(),
    );

    debugPrint(
        '[LearnedPlaces] Initialized with ${_places.length} known places');
  }

  /// Analyze location history and discover/update places.
  Future<void> analyzeHistory() async {
    final history = await _tracker.getLocalHistory();
    if (history.isEmpty) return;

    // Cluster locations into places
    for (final snapshot in history) {
      final existingPlace = _findNearestPlace(
        snapshot.latitude,
        snapshot.longitude,
      );

      if (existingPlace != null) {
        // Update existing place with new visit
        existingPlace.visitCount++;
        existingPlace.lastVisited = snapshot.timestamp;

        // Track time-of-day pattern
        final hour = snapshot.timestamp.hour;
        existingPlace.hourDistribution[hour] =
            (existingPlace.hourDistribution[hour] ?? 0) + 1;

        // Track day-of-week pattern
        final weekday = snapshot.timestamp.weekday;
        existingPlace.weekdayDistribution[weekday] =
            (existingPlace.weekdayDistribution[weekday] ?? 0) + 1;

        // Refine center position (weighted average)
        final w = existingPlace.visitCount;
        existingPlace.latitude =
            ((existingPlace.latitude * (w - 1)) + snapshot.latitude) / w;
        existingPlace.longitude =
            ((existingPlace.longitude * (w - 1)) + snapshot.longitude) / w;
      } else {
        // New place discovered
        final place = LearnedPlace(
          id: 'place_${DateTime.now().millisecondsSinceEpoch}_${_places.length}',
          latitude: snapshot.latitude,
          longitude: snapshot.longitude,
          visitCount: 1,
          firstVisited: snapshot.timestamp,
          lastVisited: snapshot.timestamp,
          hourDistribution: {snapshot.timestamp.hour: 1},
          weekdayDistribution: {snapshot.timestamp.weekday: 1},
        );
        _places.add(place);
      }
    }

    // Auto-label places based on patterns
    _autoLabelPlaces();

    await _savePlaces();
    notifyListeners();
  }

  /// Check if the user is currently at a known or unknown place.
  Future<void> _checkCurrentLocation() async {
    final pos = _tracker.lastPosition;
    if (pos == null) return;

    final nearestPlace = _findNearestPlace(pos.latitude, pos.longitude);

    if (nearestPlace != null &&
        nearestPlace.visitCount >= _minVisitsToLearn) {
      // At a known place
      _currentPlace = nearestPlace;
      _isAtNewPlace = false;
    } else if (nearestPlace == null) {
      // At a completely new place
      _currentPlace = null;
      _isAtNewPlace = true;
      onNewPlaceDetected?.call(pos.latitude, pos.longitude);
      debugPrint(
          '[LearnedPlaces] New place detected at ${pos.latitude}, ${pos.longitude}');
    } else {
      // At a place we've seen but not enough to be "known"
      _currentPlace = nearestPlace;
      _isAtNewPlace = nearestPlace.visitCount < _minVisitsToLearn &&
          !nearestPlace.isConfirmedSafe;
    }

    notifyListeners();
  }

  /// User confirms a place is safe and optionally names it.
  Future<void> confirmPlaceSafe({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    var place = _findNearestPlace(latitude, longitude);

    if (place == null) {
      place = LearnedPlace(
        id: 'place_${DateTime.now().millisecondsSinceEpoch}',
        latitude: latitude,
        longitude: longitude,
        visitCount: 1,
        firstVisited: DateTime.now(),
        lastVisited: DateTime.now(),
        label: label,
        isConfirmedSafe: true,
      );
      _places.add(place);
    } else {
      place.isConfirmedSafe = true;
      if (label != null) place.label = label;
    }

    _isAtNewPlace = false;
    _currentPlace = place;

    await _savePlaces();
    notifyListeners();
  }

  /// User flags a place as unsafe.
  Future<void> flagPlaceUnsafe({
    required double latitude,
    required double longitude,
    String? reason,
  }) async {
    var place = _findNearestPlace(latitude, longitude);

    if (place == null) {
      place = LearnedPlace(
        id: 'place_${DateTime.now().millisecondsSinceEpoch}',
        latitude: latitude,
        longitude: longitude,
        visitCount: 1,
        firstVisited: DateTime.now(),
        lastVisited: DateTime.now(),
        isConfirmedSafe: false,
        isFlagged: true,
        flagReason: reason,
      );
      _places.add(place);
    } else {
      place.isConfirmedSafe = false;
      place.isFlagged = true;
      place.flagReason = reason;
    }

    await _savePlaces();
    notifyListeners();
  }

  /// Get the user's top frequent places (sorted by visit count).
  List<LearnedPlace> getTopPlaces({int limit = 10}) {
    final sorted = List<LearnedPlace>.from(_places)
      ..sort((a, b) => b.visitCount.compareTo(a.visitCount));
    return sorted.take(limit).toList();
  }

  /// Get places the user visits during a specific time range.
  List<LearnedPlace> getPlacesForTimeRange(int startHour, int endHour) {
    return _places.where((p) {
      for (int h = startHour; h <= endHour; h++) {
        if ((p.hourDistribution[h] ?? 0) > 0) return true;
      }
      return false;
    }).toList();
  }

  // ── Private helpers ─────────────────────────────────

  /// Find the nearest known place within cluster radius.
  LearnedPlace? _findNearestPlace(double lat, double lng) {
    LearnedPlace? nearest;
    double minDist = double.infinity;

    for (final place in _places) {
      final dist = _haversineDistance(
        lat, lng, place.latitude, place.longitude,
      );
      if (dist < _clusterRadiusMeters && dist < minDist) {
        minDist = dist;
        nearest = place;
      }
    }
    return nearest;
  }

  /// Haversine distance in meters between two coordinates.
  static double _haversineDistance(
    double lat1, double lon1, double lat2, double lon2,
  ) {
    const r = 6371000.0; // Earth radius in meters
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;

  /// Auto-label places based on time patterns.
  void _autoLabelPlaces() {
    for (final place in _places) {
      if (place.label != null) continue; // Already labeled by user
      if (place.visitCount < _minVisitsToLearn) continue;

      // Check if this is likely "Home" (most visits at night/early morning)
      final nightVisits = (place.hourDistribution[22] ?? 0) +
          (place.hourDistribution[23] ?? 0) +
          (place.hourDistribution[0] ?? 0) +
          (place.hourDistribution[1] ?? 0) +
          (place.hourDistribution[6] ?? 0) +
          (place.hourDistribution[7] ?? 0);

      // Check if this is likely "Work" (most visits during work hours)
      final workVisits = (place.hourDistribution[9] ?? 0) +
          (place.hourDistribution[10] ?? 0) +
          (place.hourDistribution[11] ?? 0) +
          (place.hourDistribution[14] ?? 0) +
          (place.hourDistribution[15] ?? 0) +
          (place.hourDistribution[16] ?? 0);

      final totalVisits = place.hourDistribution.values
          .fold<int>(0, (sum, v) => sum + v);

      if (totalVisits > 0) {
        if (nightVisits / totalVisits > 0.4) {
          place.autoLabel = 'Home';
        } else if (workVisits / totalVisits > 0.4) {
          // Check if it's weekday-heavy
          final weekdayVisits = (place.weekdayDistribution[1] ?? 0) +
              (place.weekdayDistribution[2] ?? 0) +
              (place.weekdayDistribution[3] ?? 0) +
              (place.weekdayDistribution[4] ?? 0) +
              (place.weekdayDistribution[5] ?? 0);
          final totalWeekday = place.weekdayDistribution.values
              .fold<int>(0, (sum, v) => sum + v);
          if (totalWeekday > 0 && weekdayVisits / totalWeekday > 0.7) {
            place.autoLabel = 'Work';
          }
        }
      }
    }
  }

  /// Load places from local storage.
  Future<void> _loadPlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_placesKey);
      if (raw == null) return;

      final list = jsonDecode(raw) as List;
      _places = list.map((e) => LearnedPlace.fromJson(e)).toList();
    } catch (e) {
      debugPrint('[LearnedPlaces] Failed to load places: $e');
    }
  }

  /// Save places to local storage.
  Future<void> _savePlaces() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(_places.map((p) => p.toJson()).toList());
      await prefs.setString(_placesKey, json);
    } catch (e) {
      debugPrint('[LearnedPlaces] Failed to save places: $e');
    }
  }

  @override
  void dispose() {
    _analysisTimer?.cancel();
    super.dispose();
  }
}

/// Represents a place the AI has learned about.
class LearnedPlace {
  final String id;
  double latitude;
  double longitude;
  int visitCount;
  DateTime firstVisited;
  DateTime lastVisited;

  /// User-defined label (e.g. "Home", "Gym", "Mom's house").
  String? label;

  /// AI-inferred label based on patterns.
  String? autoLabel;

  /// Whether user explicitly confirmed this place is safe.
  bool isConfirmedSafe;

  /// Whether user flagged this place.
  bool isFlagged;
  String? flagReason;

  /// Hour of day distribution (0-23 -> count).
  Map<int, int> hourDistribution;

  /// Day of week distribution (1=Mon, 7=Sun -> count).
  Map<int, int> weekdayDistribution;

  LearnedPlace({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.visitCount,
    required this.firstVisited,
    required this.lastVisited,
    this.label,
    this.autoLabel,
    this.isConfirmedSafe = false,
    this.isFlagged = false,
    this.flagReason,
    Map<int, int>? hourDistribution,
    Map<int, int>? weekdayDistribution,
  })  : hourDistribution = hourDistribution ?? {},
        weekdayDistribution = weekdayDistribution ?? {};

  /// Display name — user label > auto label > "Unknown place".
  String get displayName =>
      label ?? autoLabel ?? 'Unknown place';

  /// Whether this place is "known" (enough visits or confirmed).
  bool get isKnown => visitCount >= 3 || isConfirmedSafe;

  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'visitCount': visitCount,
        'firstVisited': firstVisited.toIso8601String(),
        'lastVisited': lastVisited.toIso8601String(),
        'label': label,
        'autoLabel': autoLabel,
        'isConfirmedSafe': isConfirmedSafe,
        'isFlagged': isFlagged,
        'flagReason': flagReason,
        'hourDistribution':
            hourDistribution.map((k, v) => MapEntry(k.toString(), v)),
        'weekdayDistribution':
            weekdayDistribution.map((k, v) => MapEntry(k.toString(), v)),
      };

  factory LearnedPlace.fromJson(Map<String, dynamic> json) {
    return LearnedPlace(
      id: json['id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      visitCount: json['visitCount'] as int? ?? 0,
      firstVisited: DateTime.parse(json['firstVisited'] as String),
      lastVisited: DateTime.parse(json['lastVisited'] as String),
      label: json['label'] as String?,
      autoLabel: json['autoLabel'] as String?,
      isConfirmedSafe: json['isConfirmedSafe'] as bool? ?? false,
      isFlagged: json['isFlagged'] as bool? ?? false,
      flagReason: json['flagReason'] as String?,
      hourDistribution: (json['hourDistribution'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
          {},
      weekdayDistribution:
          (json['weekdayDistribution'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(int.parse(k), v as int)) ??
              {},
    );
  }
}
