import '../../../core/auth/session.dart';

class DeviceInfo {
  const DeviceInfo({required this.id, required this.name, required this.platform});

  final String id;
  final String name;
  final String platform;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'platform': platform,
      };
}

class AuthResponse {
  const AuthResponse({
    required this.userId,
    required this.deviceId,
    required this.accessToken,
    required this.accessExpiresAt,
    required this.refreshToken,
    required this.refreshExpiresAt,
  });

  final String userId;
  final String deviceId;
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;
  final DateTime refreshExpiresAt;

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        accessToken: json['accessToken'] as String,
        accessExpiresAt: DateTime.parse(json['accessExpiresAt'] as String).toUtc(),
        refreshToken: json['refreshToken'] as String,
        refreshExpiresAt: DateTime.parse(json['refreshExpiresAt'] as String).toUtc(),
      );

  Session toSession(String email) => Session(
        email: email.trim().toLowerCase(),
        userId: userId,
        deviceId: deviceId,
        accessToken: accessToken,
        refreshToken: refreshToken,
        accessExpiresAt: accessExpiresAt,
        refreshExpiresAt: refreshExpiresAt,
      );
}
