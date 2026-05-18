/// FileClaw API 的请求 / 响应 DTO。与 dustman-cloud app/schemas/ 对齐。
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
  final int expiresIn;
}

class MeProfile {
  MeProfile({
    required this.id,
    required this.email,
    required this.phone,
    required this.status,
    required this.emailVerifiedAt,
    required this.createdAt,
    required this.subscriptionPlan,
    required this.subscriptionEnd,
    required this.quotaAllowance,
    required this.quotaUsed,
    required this.quotaRemaining,
  });

  factory MeProfile.fromJson(Map<String, dynamic> j) => MeProfile(
        id: j['id'] as String,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        status: j['status'] as String,
        emailVerifiedAt: _parseTs(j['email_verified_at']),
        createdAt: _parseTs(j['created_at']) ?? DateTime.now(),
        subscriptionPlan: (j['subscription_plan'] as String?) ?? 'free',
        subscriptionEnd: _parseTs(j['subscription_end']),
        quotaAllowance: (j['quota_allowance'] as int?) ?? 0,
        quotaUsed: (j['quota_used'] as int?) ?? 0,
        quotaRemaining: (j['quota_remaining'] as int?) ?? 0,
      );

  final String id;
  final String? email;
  final String? phone;
  final String status;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;
  final String subscriptionPlan; // free / monthly / annual
  final DateTime? subscriptionEnd;
  final int quotaAllowance;
  final int quotaUsed;
  final int quotaRemaining;

  bool get isActive => status == 'active';
  bool get isPro => subscriptionPlan != 'free';
  String get displayName => email ?? phone ?? '(no identity)';
}

// ── Billing DTOs ────────────────────────────────


class SkuInfo {
  SkuInfo({
    required this.code,
    required this.title,
    required this.description,
    required this.amountCents,
    required this.credits,
    required this.plan,
    required this.periodDays,
  });

  factory SkuInfo.fromJson(Map<String, dynamic> j) => SkuInfo(
        code: j['code'] as String,
        title: j['title'] as String,
        description: j['description'] as String,
        amountCents: j['amount_cents'] as int,
        credits: j['credits'] as int,
        plan: j['plan'] as String?,
        periodDays: j['period_days'] as int?,
      );

  final String code;
  final String title;
  final String description;
  final int amountCents;
  final int credits;
  final String? plan;
  final int? periodDays;

  String get formattedPrice {
    final yuan = amountCents / 100.0;
    return '¥${yuan.toStringAsFixed(2)}';
  }
}

class OrderInfo {
  OrderInfo({
    required this.id,
    required this.sku,
    required this.amountCents,
    required this.currency,
    required this.status,
    required this.provider,
    required this.qrcodeUrl,
    required this.paidAt,
    required this.expiresAt,
  });

  factory OrderInfo.fromJson(Map<String, dynamic> j) => OrderInfo(
        id: j['id'] as String? ?? j['order_id'] as String,
        sku: j['sku'] as String,
        amountCents: j['amount_cents'] as int,
        currency: j['currency'] as String? ?? 'CNY',
        status: j['status'] as String,
        provider: j['provider'] as String? ?? 'stub',
        qrcodeUrl: j['qrcode_url'] as String?,
        paidAt: _parseTs(j['paid_at']),
        expiresAt: _parseTs(j['expires_at']) ??
            DateTime.now().add(const Duration(minutes: 30)),
      );

  final String id;
  final String sku;
  final int amountCents;
  final String currency;
  final String status;
  final String provider;
  final String? qrcodeUrl;
  final DateTime? paidAt;
  final DateTime expiresAt;

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isCanceled => status == 'canceled';
  bool get isTerminal => isPaid || isCanceled || status == 'refunded';
}

class QuotaInfo {
  QuotaInfo({
    required this.allowance,
    required this.used,
    required this.remaining,
    required this.resetsMonthly,
    required this.resetAt,
  });

  factory QuotaInfo.fromJson(Map<String, dynamic> j) => QuotaInfo(
        allowance: j['allowance'] as int,
        used: j['used'] as int,
        remaining: j['remaining'] as int,
        resetsMonthly: j['resets_monthly'] as bool? ?? false,
        resetAt: _parseTs(j['reset_at']),
      );

  final int allowance;
  final int used;
  final int remaining;
  final bool resetsMonthly;
  final DateTime? resetAt;
}

class SubscriptionInfo {
  SubscriptionInfo({
    required this.plan,
    required this.currentPeriodEnd,
    required this.autoRenew,
  });

  factory SubscriptionInfo.fromJson(Map<String, dynamic> j) => SubscriptionInfo(
        plan: j['plan'] as String,
        currentPeriodEnd: _parseTs(j['current_period_end']),
        autoRenew: j['auto_renew'] as bool? ?? false,
      );

  final String plan;
  final DateTime? currentPeriodEnd;
  final bool autoRenew;
}

DateTime? _parseTs(Object? v) {
  if (v is String) return DateTime.tryParse(v);
  return null;
}
