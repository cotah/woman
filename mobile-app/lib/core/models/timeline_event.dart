enum TimelineEventType {
  triggerActivated,
  countdownStarted,
  countdownCancelled,
  incidentActivated,
  coercionDetected,
  locationUpdate,
  audioChunkUploaded,
  transcriptionCompleted,
  riskScoreChanged,
  alertDispatched,
  alertDelivered,
  alertFailed,
  contactResponded,
  escalationWave,
  incidentResolved,
  incidentTimedOut,
  secretCancel,
  aiAnalysisResult,
  noteAdded,
  geofenceBreach,
  routeDeviation,
  wearableSignal,
  operatorAction,
}

extension TimelineEventTypeExtension on TimelineEventType {
  String get apiValue {
    switch (this) {
      case TimelineEventType.triggerActivated:
        return 'trigger_activated';
      case TimelineEventType.countdownStarted:
        return 'countdown_started';
      case TimelineEventType.countdownCancelled:
        return 'countdown_cancelled';
      case TimelineEventType.incidentActivated:
        return 'incident_activated';
      case TimelineEventType.coercionDetected:
        return 'coercion_detected';
      case TimelineEventType.locationUpdate:
        return 'location_update';
      case TimelineEventType.audioChunkUploaded:
        return 'audio_chunk_uploaded';
      case TimelineEventType.transcriptionCompleted:
        return 'transcription_completed';
      case TimelineEventType.riskScoreChanged:
        return 'risk_score_changed';
      case TimelineEventType.alertDispatched:
        return 'alert_dispatched';
      case TimelineEventType.alertDelivered:
        return 'alert_delivered';
      case TimelineEventType.alertFailed:
        return 'alert_failed';
      case TimelineEventType.contactResponded:
        return 'contact_responded';
      case TimelineEventType.escalationWave:
        return 'escalation_wave';
      case TimelineEventType.incidentResolved:
        return 'incident_resolved';
      case TimelineEventType.incidentTimedOut:
        return 'incident_timed_out';
      case TimelineEventType.secretCancel:
        return 'secret_cancel';
      case TimelineEventType.aiAnalysisResult:
        return 'ai_analysis_result';
      case TimelineEventType.noteAdded:
        return 'note_added';
      case TimelineEventType.geofenceBreach:
        return 'geofence_breach';
      case TimelineEventType.routeDeviation:
        return 'route_deviation';
      case TimelineEventType.wearableSignal:
        return 'wearable_signal';
      case TimelineEventType.operatorAction:
        return 'operator_action';
    }
  }

  static TimelineEventType fromApi(String value) {
    for (final type in TimelineEventType.values) {
      if (type.apiValue == value) return type;
    }
    return TimelineEventType.noteAdded;
  }
}

class TimelineEvent {
  final String id;
  final String incidentId;
  final TimelineEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> payload;
  final String source;
  final bool isInternal;
  final DateTime createdAt;

  const TimelineEvent({
    required this.id,
    required this.incidentId,
    required this.type,
    required this.timestamp,
    this.payload = const {},
    this.source = 'system',
    this.isInternal = false,
    required this.createdAt,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> json) {
    return TimelineEvent(
      id: json['id'] as String,
      incidentId: json['incidentId'] as String,
      type: TimelineEventTypeExtension.fromApi(json['type'] as String),
      timestamp: DateTime.parse(json['timestamp'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      source: json['source'] as String? ?? 'system',
      isInternal: json['isInternal'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'incidentId': incidentId,
      'type': type.apiValue,
      'timestamp': timestamp.toIso8601String(),
      'payload': payload,
      'source': source,
      'isInternal': isInternal,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
