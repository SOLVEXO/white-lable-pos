/// One Raast QR payment attempt, as the server reports it (`/api/pos/payments/intents/:id`).
///
/// Money is minor units only (an integer). The status is DERIVED by the server from an append-only event log
/// (the latest status event, with `confirmed` final); the app never decides it. The countdown is computed from the
/// server's clock: [serverTime] and [expiresAt] come from the same response, so a wrong device clock cannot show a QR as
/// valid after the server expired it (or the reverse).
enum PosQrStatus {
  created,
  presented,
  pending,
  confirmed,
  failed,
  expired,
  cancelled;

  static PosQrStatus parse(String? v) => PosQrStatus.values.firstWhere((s) => s.name == v, orElse: () => PosQrStatus.created);

  /// Still waiting for the customer.
  bool get isOpen => this == created || this == presented || this == pending;
  bool get isTerminalUnpaid => this == failed || this == expired || this == cancelled;
}

class PosPaymentIntent {
  const PosPaymentIntent({
    required this.id,
    required this.status,
    required this.amountMinor,
    required this.currency,
    required this.currencyExponent,
    required this.qrPayload,
    required this.expiresAt,
    required this.serverTime,
    this.confirmedAt,
    this.paidAfterExpiry = false,
    this.consumed = false,
    this.saleId,
    this.refundedMinor = 0,
    this.refundStatus = 'none',
    this.saleAttemptKey,
    this.attention = const [],
    this.providerRef,
  });

  final String id;
  final PosQrStatus status;
  final int amountMinor;
  final String currency;
  final int currencyExponent;
  final String qrPayload;
  final DateTime expiresAt;
  final DateTime serverTime;
  final DateTime? confirmedAt;
  final bool paidAfterExpiry;
  final bool consumed;
  final String? saleId;
  final int refundedMinor;
  final String refundStatus;
  final String? saleAttemptKey;
  final List<String> attention;
  final String? providerRef;

  /// Seconds left on the server's clock at the moment of the response (never negative).
  int get secondsRemainingAtResponse => expiresAt.difference(serverTime).inSeconds.clamp(0, 1 << 30);

  double get amount => amountMinor / _pow10(currencyExponent);

  static num _pow10(int e) {
    var r = 1;
    for (var i = 0; i < e; i++) {
      r *= 10;
    }
    return r;
  }

  factory PosPaymentIntent.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return PosPaymentIntent(
      id: (j['id'] ?? j['intentId'] ?? '') as String,
      status: PosQrStatus.parse(j['status'] as String?),
      amountMinor: asInt(j['amountMinor']),
      currency: (j['currency'] as String?) ?? '',
      currencyExponent: asInt(j['currencyExponent']),
      qrPayload: (j['qrPayload'] as String?) ?? '',
      expiresAt: DateTime.tryParse('${j['expiresAt']}') ?? DateTime.now(),
      serverTime: DateTime.tryParse('${j['serverTime']}') ?? DateTime.now(),
      confirmedAt: DateTime.tryParse('${j['confirmedAt'] ?? ''}'),
      paidAfterExpiry: j['paidAfterExpiry'] == true,
      consumed: j['consumed'] == true,
      saleId: j['saleId'] as String?,
      refundedMinor: asInt(j['refundedMinor']),
      refundStatus: (j['refundStatus'] as String?) ?? 'none',
      saleAttemptKey: j['saleAttemptKey'] as String?,
      attention: [for (final a in (j['attention'] as List<dynamic>? ?? const [])) '$a'],
      providerRef: j['providerRef'] as String?,
    );
  }
}

/// A payment a manager has to look at ("Needs attention" → Digital payments).
enum PosAttentionReason {
  paidAfterExpiry('paid_after_expiry', 'Paid after the QR expired'),
  confirmedUnattached('confirmed_unattached', 'Paid, but no sale was completed'),
  anomaly('anomaly', 'Amount did not match'),
  refundFailed('refund_failed', 'Refund failed');

  const PosAttentionReason(this.wire, this.title);
  final String wire;
  final String title;
  static PosAttentionReason? parse(String? v) {
    for (final r in values) {
      if (r.wire == v) return r;
    }
    return null;
  }
}

class PosAttentionItem {
  const PosAttentionItem({
    required this.intentId,
    required this.reason,
    required this.amountMinor,
    required this.currency,
    required this.currencyExponent,
    this.saleAttemptKey,
    this.confirmedAt,
    this.createdAt,
    this.refundedMinor = 0,
  });

  final String intentId;
  final PosAttentionReason reason;
  final int amountMinor;
  final String currency;
  final int currencyExponent;
  final String? saleAttemptKey;
  final DateTime? confirmedAt;
  final DateTime? createdAt;
  final int refundedMinor;

  factory PosAttentionItem.fromJson(Map<String, dynamic> j) {
    int asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);
    return PosAttentionItem(
      intentId: j['intentId'] as String,
      reason: PosAttentionReason.parse(j['reason'] as String?) ?? PosAttentionReason.anomaly,
      amountMinor: asInt(j['amountMinor']),
      currency: (j['currency'] as String?) ?? '',
      currencyExponent: asInt(j['currencyExponent']),
      saleAttemptKey: j['saleAttemptKey'] as String?,
      confirmedAt: DateTime.tryParse('${j['confirmedAt'] ?? ''}'),
      createdAt: DateTime.tryParse('${j['createdAt'] ?? ''}'),
      refundedMinor: asInt(j['refundedMinor']),
    );
  }
}

/// Where the store's business verification (KYB) stands — read-only here; the owner fills it in later (G2.4) and Solvexo reviews it.
enum PosKybState {
  notStarted('not_started', 'Not started'),
  draft('draft', 'Draft'),
  submitted('submitted', 'Under review'),
  verified('verified', 'Verified'),
  rejected('rejected', 'Needs changes');

  const PosKybState(this.wire, this.label);
  final String wire;
  final String label;
  static PosKybState parse(String? v) => values.firstWhere((s) => s.wire == v, orElse: () => PosKybState.notStarted);
}

class PosKybStatus {
  const PosKybStatus({required this.state, required this.digitalPaymentsEnabled, this.rejectionReason, this.submittedAt});
  final PosKybState state;
  final bool digitalPaymentsEnabled;
  final String? rejectionReason;
  final DateTime? submittedAt;

  factory PosKybStatus.fromJson(Map<String, dynamic> j) => PosKybStatus(
        state: PosKybState.parse(j['status'] as String?),
        digitalPaymentsEnabled: j['digitalPaymentsEnabled'] == true,
        rejectionReason: j['rejectionReason'] as String?,
        submittedAt: DateTime.tryParse('${j['submittedAt'] ?? ''}'),
      );
}
