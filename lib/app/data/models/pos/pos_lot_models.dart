/// G3.2 lot sale rules: the first-expiry-first-out (FEFO) preview the server answers for a lot-tracked item, and the lots a sold
/// line was taken from. The server allocates for real when the sale is saved; this is only what the till shows beforehand.
int? _int(dynamic v) => v is num ? v.toInt() : null;

class LotAllocation {
  const LotAllocation({required this.lotId, required this.lotNumber, required this.take, this.expiryDate, this.daysLeft});
  final String lotId, lotNumber;
  final int take;
  final DateTime? expiryDate;

  /// Whole days until expiry as the SERVER counted them (null = the lot has no expiry date).
  final int? daysLeft;

  factory LotAllocation.fromJson(Map<String, dynamic> j) => LotAllocation(
    lotId: '${j['lotId'] ?? ''}',
    lotNumber: '${j['lotNumber'] ?? ''}',
    take: _int(j['take']) ?? 0,
    expiryDate: DateTime.tryParse('${j['expiryDate'] ?? ''}')?.toLocal(),
    daysLeft: _int(j['daysLeft']),
  );

  Map<String, dynamic> toJson() => {'lotId': lotId, 'lotNumber': lotNumber, 'take': take, 'expiryDate': expiryDate?.toUtc().toIso8601String(), 'daysLeft': daysLeft};
}

/// "expires in 3 d" / "expires today" / "expired" — plain words for a number of days left.
String lotExpiryWords(int? daysLeft) {
  if (daysLeft == null) return 'no expiry date';
  if (daysLeft < 0) return 'expired';
  if (daysLeft == 0) return 'expires today';
  return 'expires in $daysLeft d';
}

class LotPreview {
  const LotPreview({required this.variantId, required this.trackLots, required this.qty, this.shortBy = 0, this.expiredUnits = 0, this.allocations = const [], this.serverTime, this.asOf});
  final String variantId;
  final bool trackLots;
  final int qty, shortBy, expiredUnits;
  final List<LotAllocation> allocations;
  final DateTime? serverTime;

  /// When this answer was received (used to label a remembered answer "as of …" when the till is offline).
  final DateTime? asOf;

  /// The nearest lot the sale would take from.
  LotAllocation? get first => allocations.isEmpty ? null : allocations.first;

  /// Units that cannot be sold normally while expired units exist: the cashier may ask a manager to sell the expired ones.
  bool get needsExpiredOverride => shortBy > 0 && expiredUnits > 0;

  /// The nearest lot expires within [days] days (never an expired lot: those are not offered).
  bool expiresWithin(int days) => first?.daysLeft != null && first!.daysLeft! <= days;

  /// "Lot LOT-SOON · expires in 3 d", or null when there is nothing to say.
  String? get headline => first == null ? null : 'Lot ${first!.lotNumber} · ${lotExpiryWords(first!.daysLeft)}';

  /// "+ 1 from LOT-LATER" when the quantity spans several lots.
  String? get spill {
    if (allocations.length < 2) return null;
    return allocations.skip(1).map((a) => '+ ${a.take} from ${a.lotNumber}').join(' ');
  }

  LotPreview withAsOf(DateTime t) =>
      LotPreview(variantId: variantId, trackLots: trackLots, qty: qty, shortBy: shortBy, expiredUnits: expiredUnits, allocations: allocations, serverTime: serverTime, asOf: t);

  factory LotPreview.fromJson(Map<String, dynamic> j, {DateTime? asOf}) => LotPreview(
    variantId: '${j['variantId'] ?? ''}',
    trackLots: j['trackLots'] == true,
    qty: _int(j['qty']) ?? 0,
    shortBy: _int(j['shortBy']) ?? 0,
    expiredUnits: _int(j['expiredUnits']) ?? 0,
    allocations: [
      for (final a in (j['allocations'] as List? ?? const []))
        if (a is Map) LotAllocation.fromJson(a.cast<String, dynamic>()),
    ],
    serverTime: DateTime.tryParse('${j['serverTime'] ?? ''}')?.toLocal(),
    asOf: asOf ?? DateTime.tryParse('${j['asOf'] ?? ''}')?.toLocal(),
  );

  Map<String, dynamic> toJson() => {
    'variantId': variantId,
    'trackLots': trackLots,
    'qty': qty,
    'shortBy': shortBy,
    'expiredUnits': expiredUnits,
    'allocations': [for (final a in allocations) a.toJson()],
    'serverTime': serverTime?.toUtc().toIso8601String(),
    'asOf': asOf?.toUtc().toIso8601String(),
  };
}

/// One lot a sold line was taken from (on the sale response). Cost is deliberately not read: the till never shows it.
class SaleLot {
  const SaleLot({required this.lotId, required this.lotNumber, required this.qty, this.expiryDate, this.expired = false});
  final String lotId, lotNumber;
  final int qty;
  final DateTime? expiryDate;
  final bool expired;

  factory SaleLot.fromJson(Map<String, dynamic> j) => SaleLot(
    lotId: '${j['lotId'] ?? ''}',
    lotNumber: '${j['lotNumber'] ?? ''}',
    qty: _int(j['qty']) ?? 0,
    expiryDate: DateTime.tryParse('${j['expiryDate'] ?? ''}')?.toLocal(),
    expired: j['expired'] == true,
  );

  /// "Lot B-12 ×3"
  String get label => 'Lot $lotNumber ×$qty';
}
