/// G4.6 read models: stock transfers between the store's locations (ship → in transit → received / cancelled) and lots by how soon they expire
/// (expired / within 7 days / within 30 days, store time) with value at cost for managers. Money in minor units with the response's currency.
library;

int _int(dynamic v) => v is num ? v.toInt() : 0;
String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];

class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.productName,
    this.variantLabel,
    this.sku,
    required this.fromLocationName,
    required this.toLocationName,
    required this.quantity,
    this.receivedQuantity = 0,
    required this.status,
    this.createdAt,
    this.receivedAt,
    this.note,
    this.transferredByName,
    this.receivedByName,
  });
  final String id, productName, fromLocationName, toLocationName, status;
  final String? variantLabel, sku, note, transferredByName, receivedByName;
  final int quantity, receivedQuantity;
  final DateTime? createdAt, receivedAt;

  int get outstanding => (quantity - receivedQuantity).clamp(0, quantity);
  bool get open => status == 'in_transit' || status == 'partially_received';

  /// cancel only before anything arrived (the server decides)
  bool get cancellable => status == 'in_transit';

  String get statusLabel => switch (status) {
    'in_transit' => 'In transit',
    'partially_received' => 'Partly received',
    'received' => 'Received',
    'cancelled' => 'Cancelled',
    _ => status.replaceAll('_', ' '),
  };

  String get itemName => variantLabel == null || variantLabel!.isEmpty ? productName : '$productName · $variantLabel';

  factory StockTransfer.fromJson(Map<String, dynamic> j) => StockTransfer(
    id: '${j['_id'] ?? j['id'] ?? ''}',
    productName: '${j['productName'] ?? ''}',
    variantLabel: _str(j['variantLabel']),
    sku: _str(j['sku']),
    fromLocationName: '${j['fromLocationName'] ?? ''}',
    toLocationName: '${j['toLocationName'] ?? ''}',
    quantity: _int(j['quantity']),
    receivedQuantity: _int(j['receivedQuantity']),
    status: '${j['status'] ?? 'in_transit'}',
    createdAt: _date(j['createdAt']),
    receivedAt: _date(j['receivedAt']),
    note: _str(j['note']),
    transferredByName: _str(j['transferredByName']),
    receivedByName: _str(j['receivedByName']),
  );

  static List<StockTransfer> listFrom(Map<String, dynamic> j) => [for (final t in _maps(j['list'])) StockTransfer.fromJson(t)];
}

class ExpiringLot {
  const ExpiringLot({required this.lotId, required this.lotNumber, required this.variantId, this.sku, required this.productName, this.expiryDate, required this.remaining, required this.daysLeft, this.valueMinor});
  final String lotId, lotNumber, variantId, productName;
  final String? sku;
  final DateTime? expiryDate;
  final int remaining, daysLeft;

  /// at cost; only for roles that see cost
  final int? valueMinor;

  /// "Expired 3 days ago" / "Expires today" / "2 days left"
  String get when => daysLeft < 0
      ? 'Expired ${-daysLeft} day${daysLeft == -1 ? '' : 's'} ago'
      : daysLeft == 0
      ? 'Expires today'
      : '$daysLeft day${daysLeft == 1 ? '' : 's'} left';

  factory ExpiringLot.fromJson(Map<String, dynamic> j) => ExpiringLot(
    lotId: '${j['lotId'] ?? ''}',
    lotNumber: '${j['lotNumber'] ?? ''}',
    variantId: '${j['variantId'] ?? ''}',
    sku: _str(j['sku']),
    productName: '${j['productName'] ?? ''}',
    expiryDate: _date(j['expiryDate']),
    remaining: _int(j['remaining']),
    daysLeft: _int(j['daysLeft']),
    valueMinor: j['valueMinor'] is num ? (j['valueMinor'] as num).toInt() : null,
  );
}

class ExpiryBuckets {
  const ExpiryBuckets({required this.currency, required this.exponent, this.expired = const [], this.within7 = const [], this.within30 = const []});
  final String currency;
  final int exponent;
  final List<ExpiringLot> expired, within7, within30;
  bool get empty => expired.isEmpty && within7.isEmpty && within30.isEmpty;
  bool get showsValue => [...expired, ...within7, ...within30].any((l) => l.valueMinor != null);
  int value(List<ExpiringLot> l) => l.fold(0, (n, x) => n + (x.valueMinor ?? 0));

  factory ExpiryBuckets.fromJson(Map<String, dynamic> j) => ExpiryBuckets(
    currency: '${j['currency'] ?? 'USD'}'.toUpperCase(),
    exponent: j['currencyExponent'] is num ? (j['currencyExponent'] as num).toInt() : 2,
    expired: [for (final l in _maps(j['expired'])) ExpiringLot.fromJson(l)],
    within7: [for (final l in _maps(j['within7'])) ExpiringLot.fromJson(l)],
    within30: [for (final l in _maps(j['within30'])) ExpiringLot.fromJson(l)],
  );
}

/// Server refusals of the stock operations, in words (the inventory service's own wording is kept when it has one).
String stockOpsErrorMessage(String? code, {String? message}) => switch (code) {
  'POS_ACTION_FORBIDDEN' => 'Your role cannot do this. Ask a manager.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  'NOTHING_LOW' => message ?? 'Nothing from this supplier is low on stock.',
  'SUPPLIER_NOT_FOUND' => 'That supplier was not found.',
  _ => message ?? 'Something went wrong. Please try again.',
};
