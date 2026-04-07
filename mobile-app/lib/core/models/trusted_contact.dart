class TrustedContact {
  final String id;
  final String userId;
  final String name;
  final String? relationship;
  final String phone;
  final String? email;
  final int priority;
  final bool canReceiveSms;
  final bool canReceivePush;
  final bool canReceiveVoiceCall;
  final bool canAccessAudio;
  final bool canAccessLocation;
  final String locale;
  final bool isVerified;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TrustedContact({
    required this.id,
    required this.userId,
    required this.name,
    this.relationship,
    required this.phone,
    this.email,
    this.priority = 1,
    this.canReceiveSms = true,
    this.canReceivePush = false,
    this.canReceiveVoiceCall = false,
    this.canAccessAudio = false,
    this.canAccessLocation = true,
    this.locale = 'en',
    this.isVerified = false,
    this.verifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory TrustedContact.fromJson(Map<String, dynamic> json) {
    return TrustedContact(
      id: json['id'] as String,
      userId: json['userId'] as String,
      name: json['name'] as String,
      relationship: json['relationship'] as String?,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      priority: json['priority'] as int? ?? 1,
      canReceiveSms: json['canReceiveSms'] as bool? ?? true,
      canReceivePush: json['canReceivePush'] as bool? ?? false,
      canReceiveVoiceCall: json['canReceiveVoiceCall'] as bool? ?? false,
      canAccessAudio: json['canAccessAudio'] as bool? ?? false,
      canAccessLocation: json['canAccessLocation'] as bool? ?? true,
      locale: json['locale'] as String? ?? 'en',
      isVerified: json['isVerified'] as bool? ?? false,
      verifiedAt: json['verifiedAt'] != null
          ? DateTime.parse(json['verifiedAt'] as String)
          : null,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'name': name,
      'relationship': relationship,
      'phone': phone,
      'email': email,
      'priority': priority,
      'canReceiveSms': canReceiveSms,
      'canReceivePush': canReceivePush,
      'canReceiveVoiceCall': canReceiveVoiceCall,
      'canAccessAudio': canAccessAudio,
      'canAccessLocation': canAccessLocation,
      'locale': locale,
      'isVerified': isVerified,
      'verifiedAt': verifiedAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
