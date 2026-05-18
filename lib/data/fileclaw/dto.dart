/// FileClaw API 的请求 / 响应 DTO。与 dustman-cloud app/schemas/auth.py 对齐。
///
/// 这些类无业务方法，仅 fromJson / toJson；命名和 Python 端一致。
library;

class TokenPair {
  TokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresIn: j['expires_in'] as int,
      );

  final String accessToken;
  final String refreshToken;
  final int expiresIn; // 秒
}

class MeProfile {
  MeProfile({
    required this.id,
    required this.email,
    required this.phone,
    required this.status,
    required this.emailVerifiedAt,
    required this.createdAt,
  });

  factory MeProfile.fromJson(Map<String, dynamic> j) => MeProfile(
        id: j['id'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        status: j['status'] as String,
        emailVerifiedAt: _parseTs(j['email_verified_at']),
        createdAt: _parseTs(j['created_at']) ?? DateTime.now(),
      );

  final String id;
  final String? email;
  final String? phone;
  final String status; // pending/active/locked/deleted
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;

  bool get isActive => status == 'active';
  String get displayName => email ?? phone ?? '(no identity)';
}

DateTime? _parseTs(Object? v) {
  if (v is String) return DateTime.tryParse(v);
  return null;
}
