/// Mirrors the backend's `status` enum for a store's POS plan purchase.
/// Fixed-term, one-time purchase model — no recurring subscription states
/// (past_due/canceled/incomplete/trialing don't apply here). An
/// unrecognized/missing value falls back to [none] so callers always have a
/// value to gate on rather than a null.
enum PosSubscriptionStatusValue {
  active,
  expired,
  none;

  static PosSubscriptionStatusValue fromJson(String? value) {
    switch (value) {
      case 'active':
        return PosSubscriptionStatusValue.active;
      case 'expired':
        return PosSubscriptionStatusValue.expired;
      default:
        return PosSubscriptionStatusValue.none;
    }
  }

  bool get isEntitled => this == PosSubscriptionStatusValue.active;
}

class PosSubscriptionStatusModel {
  final PosSubscriptionStatusValue status;
  final String? planName;
  final DateTime? purchasedAt;
  final DateTime? expiresAt;
  final int? daysRemaining;

  const PosSubscriptionStatusModel({
    required this.status,
    this.planName,
    this.purchasedAt,
    this.expiresAt,
    this.daysRemaining,
  });

  factory PosSubscriptionStatusModel.fromJson(Map<String, dynamic> json) => PosSubscriptionStatusModel(
        status: PosSubscriptionStatusValue.fromJson(json['status'] as String?),
        planName: json['planName'] as String?,
        purchasedAt: DateTime.tryParse(json['purchasedAt'] as String? ?? ''),
        expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? ''),
        daysRemaining: json['daysRemaining'] as int?,
      );

  /// Used when the endpoint call itself fails (network/auth error) — treated
  /// as not-entitled rather than silently letting the seller into the
  /// terminal, but distinguishable from a real `none` if callers need to.
  factory PosSubscriptionStatusModel.unknown() =>
      const PosSubscriptionStatusModel(status: PosSubscriptionStatusValue.none);
}
