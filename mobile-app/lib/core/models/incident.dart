enum IncidentStatus {
  pending,
  countdown,
  active,
  escalated,
  resolved,
  cancelled,
  falseAlarm,
  timedOut,
}

enum TriggerType {
  manualButton,
  coercionPin,
  physicalButton,
  quickShortcut,
  wearable,
  voice,
  geofence,
  routeAnomaly,
}

enum RiskLevel {
  none,
  monitoring,
  suspicious,
  alert,
  critical,
}

extension IncidentStatusExtension on IncidentStatus {
  String get apiValue {
    switch (this) {
      case IncidentStatus.pending:
        return 'pending';
      case IncidentStatus.countdown:
        return 'countdown';
      case IncidentStatus.active:
        return 'active';
      case IncidentStatus.escalated:
        return 'escalated';
      case IncidentStatus.resolved:
        return 'resolved';
      case IncidentStatus.cancelled:
        return 'cancelled';
      case IncidentStatus.falseAlarm:
        return 'false_alarm';
      case IncidentStatus.timedOut:
        return 'timed_out';
    }
  }

  static IncidentStatus fromApi(String value) {
    switch (value) {
      case 'pending':
        return IncidentStatus.pending;
      case 'countdown':
        return IncidentStatus.countdown;
      case 'active':
        return IncidentStatus.active;
      case 'escalated':
        return IncidentStatus.escalated;
      case 'resolved':
        return IncidentStatus.resolved;
      case 'cancelled':
        return IncidentStatus.cancelled;
      case 'false_alarm':
        return IncidentStatus.falseAlarm;
      case 'timed_out':
        return IncidentStatus.timedOut;
      default:
        return IncidentStatus.pending;
    }
  }

  bool get isActive =>
      this == IncidentStatus.active ||
      this == IncidentStatus.escalated ||
      this == IncidentStatus.countdown;

  bool get isTerminal =>
      this == IncidentStatus.resolved ||
      this == IncidentStatus.cancelled ||
      this == IncidentStatus.falseAlarm ||
      this == IncidentStatus.timedOut;
}

extension TriggerTypeExtension on TriggerType {
  String get apiValue {
    switch (this) {
      case TriggerType.manualButton:
        return 'manual_button';
      case TriggerType.coercionPin:
        return 'coercion_pin';
      case TriggerType.physicalButton:
        return 'physical_button';
      case TriggerType.quickShortcut:
        return 'quick_shortcut';
      case TriggerType.wearable:
        return 'wearable';
      case TriggerType.voice:
        return 'voice';
      case TriggerType.geofence:
        return 'geofence';
      case TriggerType.routeAnomaly:
        return 'route_anomaly';
    }
  }

  static TriggerType fromApi(String value) {
    switch (value) {
      case 'manual_button':
        return TriggerType.manualButton;
      case 'coercion_pin':
        return TriggerType.coercionPin;
      case 'physical_button':
        return TriggerType.physicalButton;
      case 'quick_shortcut':
        return TriggerType.quickShortcut;
      case 'wearable':
        return TriggerType.wearable;
      case 'voice':
        return TriggerType.voice;
      case 'geofence':
        return TriggerType.geofence;
      case 'route_anomaly':
        return TriggerType.routeAnomaly;
      default:
        return TriggerType.manualButton;
    }
  }
}

extension RiskLevelExtension on RiskLevel {
  String get apiValue {
    switch (this) {
      case RiskLevel.none:
        return 'none';
      case RiskLevel.monitoring:
        return 'monitoring';
      case RiskLevel.suspicious:
        return 'suspicious';
      case RiskLevel.alert:
        return 'alert';
      case RiskLevel.critical:
        return 'critical';
    }
  }

  static RiskLevel fromApi(String value) {
    switch (value) {
      case 'none':
        return RiskLevel.none;
      case 'monitoring':
        return RiskLevel.monitoring;
      case 'suspicious':
        return RiskLevel.suspicious;
      case 'alert':
        return RiskLevel.alert;
      case 'critical':
        return RiskLevel.critical;
      default:
        return RiskLevel.none;
    }
  }
}

class Incident {
  final String id;
  final String userId;
  final IncidentStatus status;
  final TriggerType triggerType;
  final bool isCoercion;
  final bool isTestMode;
  final int currentRiskScore;
  final RiskLevel currentRiskLevel;
  final int escalationWave;
  final DateTime startedAt;
  final DateTime? countdownEndsAt;
  final DateTime? activatedAt;
  final DateTime? resolvedAt;
  final String? resolutionReason;
  final DateTime? lastLocationAt;
  final double? lastLatitude;
  final double? lastLongitude;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Incident({
    required this.id,
    required this.userId,
    required this.status,
    required this.triggerType,
    this.isCoercion = false,
    this.isTestMode = false,
    this.currentRiskScore = 0,
    this.currentRiskLevel = RiskLevel.none,
    this.escalationWave = 0,
    required this.startedAt,
    this.countdownEndsAt,
    this.activatedAt,
    this.resolvedAt,
    this.resolutionReason,
    this.lastLocationAt,
    this.lastLatitude,
    this.lastLongitude,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Incident.fromJson(Map<String, dynamic> json) {
    return Incident(
      id: json['id'] as String,
      userId: json['userId'] as String,
      status: IncidentStatusExtension.fromApi(json['status'] as String),
      triggerType:
          TriggerTypeExtension.fromApi(json['triggerType'] as String),
      isCoercion: json['isCoercion'] as bool? ?? false,
      isTestMode: json['isTestMode'] as bool? ?? false,
      currentRiskScore: json['currentRiskScore'] as int? ?? 0,
      currentRiskLevel: RiskLevelExtension.fromApi(
          json['currentRiskLevel'] as String? ?? 'none'),
      escalationWave: json['escalationWave'] as int? ?? 0,
      startedAt: DateTime.parse(json['startedAt'] as String),
      countdownEndsAt: json['countdownEndsAt'] != null
          ? DateTime.parse(json['countdownEndsAt'] as String)
          : null,
      activatedAt: json['activatedAt'] != null
          ? DateTime.parse(json['activatedAt'] as String)
          : null,
      resolvedAt: json['resolvedAt'] != null
          ? DateTime.parse(json['resolvedAt'] as String)
          : null,
      resolutionReason: json['resolutionReason'] as String?,
      lastLocationAt: json['lastLocationAt'] != null
          ? DateTime.parse(json['lastLocationAt'] as String)
          : null,
      lastLatitude: (json['lastLatitude'] as num?)?.toDouble(),
      lastLongitude: (json['lastLongitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'status': status.apiValue,
      'triggerType': triggerType.apiValue,
      'isCoercion': isCoercion,
      'isTestMode': isTestMode,
      'currentRiskScore': currentRiskScore,
      'currentRiskLevel': currentRiskLevel.apiValue,
      'escalationWave': escalationWave,
      'startedAt': startedAt.toIso8601String(),
      'countdownEndsAt': countdownEndsAt?.toIso8601String(),
      'activatedAt': activatedAt?.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'resolutionReason': resolutionReason,
      'lastLocationAt': lastLocationAt?.toIso8601String(),
      'lastLatitude': lastLatitude,
      'lastLongitude': lastLongitude,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
