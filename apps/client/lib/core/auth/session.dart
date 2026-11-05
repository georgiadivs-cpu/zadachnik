import 'dart:convert';

class Session {
  const Session({
    required this.email,
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
  });

  final String email;
  final String userId;
  final String deviceId;
  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;

  bool get isAccessExpired =>
      accessExpiresAt.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 30)));

  Map<String, dynamic> toJson() => {
        'email': email,
        'userId': userId,
        'deviceId': deviceId,
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessExpiresAt': accessExpiresAt.toUtc().toIso8601String(),
        'refreshExpiresAt': refreshExpiresAt.toUtc().toIso8601String(),
      };

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        email: json['email'] as String,
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String).toUtc(),
        refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String).toUtc(),
      );

  static String encode(Session session) => jsonEncode(session.toJson());

  static Session? decode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      return null;
    }
  }
}
