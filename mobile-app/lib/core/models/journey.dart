enum JourneyStatus {
  active,
  completed,
  expired,
  escalated,
  cancelled,
}

extension JourneyStatusExtension on JourneyStatus {
  String get apiValue {
    switch (this) {
      case JourneyStatus.active:
        return 'active';
      case JourneyStatus.completed:
        return 'completed';
      case JourneyStatus.expired:
        return 'expired';
      case JourneyStatus.escalated:
        return 'escalated';
      case JourneyStatus.cancelled:
        return 'cancelled';
    }
  }

  static JourneyStatus fromApi(String value) {
    switch (value) {
      case 'active':
        return JourneyStatus.active;
      case 'completed':
        return JourneyStatus.completed;
      case 'expired':
        return JourneyStatus.expired;
      case 'escalated':
        return JourneyStatus.escalated;
      case 'cancelled':
        return JourneyStatus.cancelled;
      default:
        return JourneyStatus.active;
    }
  }

  bool get isActive => this == JourneyStatus.active;
  bool get isTerminal => this != JourneyStatus.active;
}

class Journey {
  final String id;
  final String userId;
  final JourneyStatus status;
  final double? startLatitude;
  final double? startLongitude;
  final double destLatitude;
  final double destLongitude;
  final String? destLabel;
  final int arrivalRadiusMeters;
  final int durationMinutes;
  final DateTime expiresAt;
  final DateTime startedAt;
  final DateTime? completedAt;
  final DateTime? lastCheckinAt;
  final String? incidentId;
  final bool isTestMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Journey({
    required this.id,
    required this.userId,
    required this.status,
    this.startLatitude,
    this.startLongitude,
    required this.destLatitude,
    required this.destLongitude,
    this.destLabel,
    this.arrivalRadiusMeters = 200,
    required this.durationMinutes,
    required this.expiresAt,
    required this.startedAt,
    this.completedAt,
    this.lastCheckinAt,
    this.incidentId,
    this.isTestMode = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Journey.fromJson(Map<String, dynamic> json) {
    return Journey(
      id: json['id'] as String,
      userId: json['userId'] as String,
      status: JourneyStatusExtension.fromApi(json['status'] as String),
      startLatitude: (json['startLatitude'] as num?)?.toDouble(),
      startLongitude: (json['startLongitude'] as num?)?.toDouble(),
      destLatitude: (json['destLatitude'] as num).toDouble(),
      destLongitude: (json['destLongitude'] as num).toDouble(),
      destLabel: json['destLabel'] as String?,
      arrivalRadiusMeters: json['arrivalRadiusMeters'] as int? ?? 200,
      durationMinutes: json['durationMinutes'] as int,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      startedAt: DateTime.parse(json['startedAt'] as String),
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      lastCheckinAt: json['lastCheckinAt'] != null
          ? DateTime.parse(json['lastCheckinAt'] as String)
          : null,
      incidentId: json['incidentId'] as String?,
      isTestMode: json['isTestMode'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'status': status.apiValue,
      if (startLatitude != null) 'startLatitude': startLatitude,
      if (startLongitude != null) 'startLongitude': startLongitude,
      'destLatitude': destLatitude,
      'destLongitude': destLongitude,
      if (destLabel != null) 'destLabel': destLabel,
      'arrivalRadiusMeters': arrivalRadiusMeters,
      'durationMinutes': durationMinutes,
      'expiresAt': expiresAt.toIso8601String(),
      'startedAt': startedAt.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (lastCheckinAt != null)
        'lastCheckinAt': lastCheckinAt!.toIso8601String(),
      if (incidentId != null) 'incidentId': incidentId,
      'isTestMode': isTestMode,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
