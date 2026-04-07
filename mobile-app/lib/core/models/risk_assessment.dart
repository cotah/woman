import 'incident.dart';

class RiskAssessment {
  final String id;
  final String incidentId;
  final int previousScore;
  final int newScore;
  final RiskLevel previousLevel;
  final RiskLevel newLevel;
  final String ruleId;
  final String ruleName;
  final String reason;
  final String signalType;
  final Map<String, dynamic> signalPayload;
  final DateTime timestamp;

  const RiskAssessment({
    required this.id,
    required this.incidentId,
    required this.previousScore,
    required this.newScore,
    required this.previousLevel,
    required this.newLevel,
    required this.ruleId,
    required this.ruleName,
    required this.reason,
    required this.signalType,
    this.signalPayload = const {},
    required this.timestamp,
  });

  factory RiskAssessment.fromJson(Map<String, dynamic> json) {
    return RiskAssessment(
      id: json['id'] as String,
      incidentId: json['incidentId'] as String,
      previousScore: json['previousScore'] as int,
      newScore: json['newScore'] as int,
      previousLevel:
          RiskLevelExtension.fromApi(json['previousLevel'] as String),
      newLevel: RiskLevelExtension.fromApi(json['newLevel'] as String),
      ruleId: json['ruleId'] as String,
      ruleName: json['ruleName'] as String,
      reason: json['reason'] as String,
      signalType: json['signalType'] as String,
      signalPayload:
          Map<String, dynamic>.from(json['signalPayload'] as Map? ?? {}),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'incidentId': incidentId,
      'previousScore': previousScore,
      'newScore': newScore,
      'previousLevel': previousLevel.apiValue,
      'newLevel': newLevel.apiValue,
      'ruleId': ruleId,
      'ruleName': ruleName,
      'reason': reason,
      'signalType': signalType,
      'signalPayload': signalPayload,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
