import 'incident.dart';

enum AudioConsentLevel {
  none,
  recordOnly,
  recordAndAnalyze,
  full,
}

extension AudioConsentLevelExtension on AudioConsentLevel {
  String get apiValue {
    switch (this) {
      case AudioConsentLevel.none:
        return 'none';
      case AudioConsentLevel.recordOnly:
        return 'record_only';
      case AudioConsentLevel.recordAndAnalyze:
        return 'record_and_analyze';
      case AudioConsentLevel.full:
        return 'full';
    }
  }

  static AudioConsentLevel fromApi(String value) {
    switch (value) {
      case 'none':
        return AudioConsentLevel.none;
      case 'record_only':
        return AudioConsentLevel.recordOnly;
      case 'record_and_analyze':
        return AudioConsentLevel.recordAndAnalyze;
      case 'full':
        return AudioConsentLevel.full;
      default:
        return AudioConsentLevel.none;
    }
  }

  bool get canRecord => this != AudioConsentLevel.none;
  bool get canAnalyze =>
      this == AudioConsentLevel.recordAndAnalyze ||
      this == AudioConsentLevel.full;
}

class EmergencySettings {
  final String id;
  final String userId;
  final int countdownDurationSeconds;
  final String normalCancelMethod;
  final AudioConsentLevel audioConsent;
  final bool autoRecordAudio;
  final bool allowAiAnalysis;
  final bool shareAudioWithContacts;
  final List<String> audioContactIds;
  final RiskLevel audioShareThreshold;
  final bool enableTestMode;
  final List<Map<String, dynamic>> triggerConfigurations;
  final String emergencyMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmergencySettings({
    required this.id,
    required this.userId,
    this.countdownDurationSeconds = 5,
    this.normalCancelMethod = 'tap_pattern',
    this.audioConsent = AudioConsentLevel.none,
    this.autoRecordAudio = false,
    this.allowAiAnalysis = false,
    this.shareAudioWithContacts = false,
    this.audioContactIds = const [],
    this.audioShareThreshold = RiskLevel.critical,
    this.enableTestMode = false,
    this.triggerConfigurations = const [],
    this.emergencyMessage =
        'I need help. This is an emergency alert from SafeCircle.',
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmergencySettings.fromJson(Map<String, dynamic> json) {
    return EmergencySettings(
      id: json['id'] as String,
      userId: json['userId'] as String,
      countdownDurationSeconds:
          json['countdownDurationSeconds'] as int? ?? 5,
      normalCancelMethod:
          json['normalCancelMethod'] as String? ?? 'tap_pattern',
      audioConsent: AudioConsentLevelExtension.fromApi(
          json['audioConsent'] as String? ?? 'none'),
      autoRecordAudio: json['autoRecordAudio'] as bool? ?? false,
      allowAiAnalysis: json['allowAiAnalysis'] as bool? ?? false,
      shareAudioWithContacts:
          json['shareAudioWithContacts'] as bool? ?? false,
      audioContactIds: (json['audioContactIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      audioShareThreshold: RiskLevelExtension.fromApi(
          json['audioShareThreshold'] as String? ?? 'critical'),
      enableTestMode: json['enableTestMode'] as bool? ?? false,
      triggerConfigurations:
          (json['triggerConfigurations'] as List<dynamic>?)
                  ?.map((e) => Map<String, dynamic>.from(e as Map))
                  .toList() ??
              [],
      emergencyMessage: json['emergencyMessage'] as String? ??
          'I need help. This is an emergency alert from SafeCircle.',
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'countdownDurationSeconds': countdownDurationSeconds,
      'normalCancelMethod': normalCancelMethod,
      'audioConsent': audioConsent.apiValue,
      'autoRecordAudio': autoRecordAudio,
      'allowAiAnalysis': allowAiAnalysis,
      'shareAudioWithContacts': shareAudioWithContacts,
      'audioContactIds': audioContactIds,
      'audioShareThreshold': audioShareThreshold.apiValue,
      'enableTestMode': enableTestMode,
      'triggerConfigurations': triggerConfigurations,
      'emergencyMessage': emergencyMessage,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
