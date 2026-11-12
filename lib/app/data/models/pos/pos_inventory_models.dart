import 'package:solvexo_pos/utils/money.dart';

/// G3.1 inventory read models. The server sends money as integer MINOR units (`...Minor`) plus `currencyExponent`; [invMoney] turns
/// that into text through the shared [Money] helper (the only place a minor amount is converted).
String invMoney(int minor, InvCur cur) => cur.format(minor);

/// The currency of a server response: its code AND exponent, exactly as the server states them. There is NO fallback to the app's configured
/// currency — when a response does not state both, money in it is not shown at all (the server contract guarantees both on every money response).
class InvCur {
  const InvCur(this.code, this.exponent);
  final String code;
  final int exponent;

  String format(int minor) {
    var p = 1;
    for (var i = 0; i < exponent; i++) {
      p *= 10;
    }
    return Money.format(minor / p, currency: code, exponent: exponent);
  }

  static InvCur? fromJson(Map<String, dynamic> j) {
    final c = j['currency'];
    final e = j['currencyExponent'];
    return c is String && c.length == 3 && e is num ? InvCur(c.toUpperCase(), e.toInt()) : null;
  }

  @override
  bool operator ==(Object other) => other is InvCur && other.code == code && other.exponent == exponent;
  @override
  int get hashCode => Object.hash(code, exponent);
}

int? _int(dynamic v) => v is num ? v.toInt() : null;
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];

/// Roles as the server reports them in `overview.role`.
abstract final class InvRole {
  static const cashier = 'cashier';
  static const manager = 'manager';
  static const owner = 'owner';
  static bool canManage(String role) => role == manager || role == owner;
}

class InvOverview {
  const InvOverview({
    required this.role,
    required this.skuCount,
    required this.lowStockCount,
    required this.outOfStockCount,
    required this.expiredLots,
    required this.expiringIn7Days,
    required this.expiringIn30Days,
    this.openCountId,
    this.openCountStartedAt,
    this.stockValueMinor,
    this.variantsWithoutCost,
    this.cur,
    this.costsHidden = false,
  });

  /// G4.8: the owner hides costs from managers — the stock value is not sent; the screen says so instead of showing nothing
  final bool costsHidden;
  final String role;
  final int skuCount, lowStockCount, outOfStockCount, expiredLots, expiringIn7Days, expiringIn30Days;
  final String? openCountId;
  final DateTime? openCountStartedAt;
  final int? stockValueMinor, variantsWithoutCost;
  final InvCur? cur;

  bool get canManage => InvRole.canManage(role);
  bool get hasOpenCount => openCountId != null;

  factory InvOverview.fromJson(Map<String, dynamic> j) {
    final open = j['openStockCount'] is Map ? (j['openStockCount'] as Map).cast<String, dynamic>() : null;
    return InvOverview(
      role: j['role'] as String? ?? InvRole.cashier,
      skuCount: _int(j['skuCount']) ?? 0,
      lowStockCount: _int(j['lowStockCount']) ?? 0,
      outOfStockCount: _int(j['outOfStockCount']) ?? 0,
      expiredLots: _int(j['expiredLots']) ?? 0,
      expiringIn7Days: _int(j['expiringIn7Days']) ?? 0,
      expiringIn30Days: _int(j['expiringIn30Days']) ?? 0,
      openCountId: open?['id']?.toString(),
      openCountStartedAt: DateTime.tryParse('${open?['startedAt'] ?? ''}')?.toLocal(),
      stockValueMinor: _int(j['stockValueMinor']),
      variantsWithoutCost: _int(j['variantsWithoutCost']),
      cur: InvCur.fromJson(j),
      costsHidden: j['costsHidden'] == true,
    );
  }
}

class InvRow {
  const InvRow({
    required this.variantId,
    required this.productId,
    required this.productName,
    this.image,
    this.sku = '',
    this.barcode,
    this.options = const [],
    this.stock = 0,
    this.committed = 0,
    this.damaged = 0,
    this.unlimited = false,
    this.trackLots = false,
    this.trackSerials = false,
    this.reorderPoint,
    this.out = false,
    this.low = false,
    this.costMinor,
    this.valueMinor,
    this.expiredUnits = 0,
    this.nextExpiryAt,
    this.cur,
    this.locationStock,
  });

  /// G5.1: the quantity at the location the list is filtered by (null = the list is not filtered by a location)
  final int? locationStock;

  final String variantId, productId, productName, sku;
  final String? image, barcode;
  final List<String> options;
  final int stock, committed, damaged;
  final bool unlimited, trackLots, out, low;

  /// G5.2: serial-tracked (receiving asks one serial per unit)
  final bool trackSerials;
  final int? reorderPoint, costMinor, valueMinor;
  /// G3.2: units of lots already past their expiry date, and the nearest expiry among the lots still in stock
  final int expiredUnits;
  final DateTime? nextExpiryAt;
  /// set when the row itself states its currency (the barcode lookup); list rows use the page's
  final InvCur? cur;

  /// "Large · Red" — empty when the item has no options.
  String get optionsLabel => options.join(' · ');

  factory InvRow.fromJson(Map<String, dynamic> j) => InvRow(
    variantId: '${j['variantId'] ?? ''}',
    productId: '${j['productId'] ?? ''}',
    productName: j['productName'] as String? ?? '',
    image: j['image'] as String?,
    sku: j['sku'] as String? ?? '',
    barcode: j['barcode'] as String?,
    options: [
      for (final o in (j['options'] as List? ?? const []))
        if (o is Map) '${o['value'] ?? o['name'] ?? ''}' else '$o',
    ].where((e) => e.isNotEmpty).toList(),
    stock: _int(j['stock']) ?? 0,
    committed: _int(j['committed']) ?? 0,
    damaged: _int(j['damaged']) ?? 0,
    unlimited: j['unlimited'] == true,
    trackLots: j['trackLots'] == true,
    trackSerials: j['trackSerials'] == true,
    reorderPoint: _int(j['reorderPoint']),
    out: j['out'] == true,
    low: j['low'] == true,
    costMinor: _int(j['costMinor']),
    valueMinor: _int(j['valueMinor']),
    expiredUnits: _int(j['expiredUnits']) ?? 0,
    nextExpiryAt: DateTime.tryParse('${j['nextExpiryAt'] ?? ''}')?.toLocal(),
    cur: InvCur.fromJson(j),
    locationStock: _int(j['locationStock']),
  );
}

class InvPage<T> {
  const InvPage({required this.items, required this.total, required this.page, required this.hasMore, this.cur, this.costsHidden = false});
  final InvCur? cur;

  /// G4.8: costs hidden from this manager by the owner
  final bool costsHidden;
  final List<T> items;
  final int total, page;
  final bool hasMore;
}

class InvLocationStock {
  const InvLocationStock(this.locationId, this.name, this.stock);
  final String locationId, name;
  final int stock;
}

class InvLot {
  const InvLot({required this.lotId, required this.lotNumber, this.expiryDate, required this.remaining, this.costMinor});
  final String lotId, lotNumber;
  final DateTime? expiryDate;
  final int remaining;
  final int? costMinor;

  /// Days until expiry counted from [now] (negative = already expired); null when the lot has no expiry.
  int? daysLeft(DateTime now) {
    final e = expiryDate;
    if (e == null) return null;
    final a = DateTime(e.year, e.month, e.day), b = DateTime(now.year, now.month, now.day);
    return a.difference(b).inDays;
  }

  factory InvLot.fromJson(Map<String, dynamic> j) => InvLot(
    lotId: '${j['lotId'] ?? ''}',
    lotNumber: '${j['lotNumber'] ?? ''}',
    expiryDate: DateTime.tryParse('${j['expiryDate'] ?? ''}')?.toLocal(),
    remaining: _int(j['remaining']) ?? 0,
    costMinor: _int(j['costMinor']),
  );
}

class InvMovement {
  const InvMovement({
    required this.id,
    required this.at,
    required this.type,
    required this.qtyDelta,
    this.damagedDelta = 0,
    this.reason,
    this.note,
    this.productName,
    this.sku,
    this.variantId,
    this.unitCostMinor,
  });

  final String id, type;
  final DateTime? at;
  final int qtyDelta, damagedDelta;
  final String? reason, note, productName, sku, variantId;
  final int? unitCostMinor;

  /// A "damaged" adjustment leaves on-hand stock alone and moves units into the damaged pool.
  bool get isMarkedDamaged => qtyDelta == 0 && damagedDelta > 0;

  String get typeLabel => invMovementTypeLabel(type, markedDamaged: isMarkedDamaged);

  factory InvMovement.fromJson(Map<String, dynamic> j) => InvMovement(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
    type: j['type'] as String? ?? '',
    qtyDelta: _int(j['qtyDelta']) ?? 0,
    damagedDelta: _int(j['damagedDelta']) ?? 0,
    reason: j['reason'] as String?,
    note: j['note'] as String?,
    productName: j['productName'] as String?,
    sku: j['sku'] as String?,
    variantId: j['variantId']?.toString(),
    unitCostMinor: _int(j['unitCostMinor']),
  );
}

/// Movement types in plain words.
String invMovementTypeLabel(String type, {bool markedDamaged = false}) {
  if (markedDamaged) return 'Marked damaged';
  return switch (type) {
    'sale' => 'Sale',
    'return' => 'Return',
    'void' => 'Voided sale',
    'adjustment' => 'Adjustment',
    'count' => 'Stock count',
    'receive' => 'Received',
    'write_off' => 'Written off',
    'supplier_return' => 'Returned to supplier',
    'expired' => 'Expired',
    'transfer_out' => 'Transferred out',
    'transfer_in' => 'Transferred in',
    _ => type.isEmpty ? 'Movement' : type,
  };
}

/// Reason words as the till shows them.
String invReasonLabel(String? reason) => switch (reason) {
  'restocked' => 'Restocked',
  'damaged' => 'Damaged',
  'correction' => 'Correction',
  'other' => 'Other',
  null || '' => '',
  final r => r.replaceAll('_', ' '),
};

class InvDetail {
  const InvDetail({required this.row, this.locations = const [], this.lots = const [], this.recentMovements = const [], this.ledgerStartsAt, this.cur, this.costsHidden = false});
  final InvRow row;

  /// G4.8: costs hidden from this manager by the owner
  final bool costsHidden;
  final List<InvLocationStock> locations;
  final List<InvLot> lots;
  final List<InvMovement> recentMovements;
  final DateTime? ledgerStartsAt;
  final InvCur? cur;

  factory InvDetail.fromJson(Map<String, dynamic> j) => InvDetail(
    row: InvRow.fromJson(j),
    locations: [for (final l in _maps(j['locations'])) InvLocationStock('${l['locationId'] ?? ''}', l['name'] as String? ?? '', _int(l['stock']) ?? 0)],
    lots: [for (final l in _maps(j['lots'])) InvLot.fromJson(l)],
    recentMovements: [for (final m in _maps(j['recentMovements'])) InvMovement.fromJson(m)],
    ledgerStartsAt: DateTime.tryParse('${j['ledgerStartsAt'] ?? ''}')?.toLocal(),
    cur: InvCur.fromJson(j),
    costsHidden: j['costsHidden'] == true,
  );
}

class InvCountItem {
  InvCountItem({required this.id, required this.variantId, required this.productName, this.sku = '', this.barcode, required this.systemQty, this.countedQty});
  final String id, variantId, productName, sku;
  final String? barcode;
  final int systemQty;
  final int? countedQty;

  int? get variance => countedQty == null ? null : countedQty! - systemQty;

  factory InvCountItem.fromJson(Map<String, dynamic> j) => InvCountItem(
    id: '${j['_id'] ?? j['id'] ?? ''}',
    variantId: '${j['variantId'] ?? ''}',
    productName: j['productName'] as String? ?? '',
    sku: j['sku'] as String? ?? '',
    barcode: j['barcode'] as String?,
    systemQty: _int(j['systemQty']) ?? 0,
    countedQty: _int(j['countedQty']),
  );
}

class InvCount {
  const InvCount({required this.id, required this.status, this.items = const [], this.startedAt});
  final String id, status;
  final List<InvCountItem> items;
  final DateTime? startedAt;

  bool get isOpen => status == 'open';
  int get countedCount => items.where((i) => i.countedQty != null).length;

  /// Counted lines whose counted quantity differs from the system quantity (uncounted lines are never touched by a finish).
  List<InvCountItem> get variances => [
    for (final i in items)
      if (i.countedQty != null && i.countedQty != i.systemQty) i,
  ];

  InvCount copyWithItem(InvCountItem item) => InvCount(id: id, status: status, startedAt: startedAt, items: [for (final i in items) i.id == item.id ? item : i]);

  factory InvCount.fromJson(Map<String, dynamic> j) => InvCount(
    id: '${j['_id'] ?? j['id'] ?? ''}',
    status: j['status'] as String? ?? 'open',
    startedAt: DateTime.tryParse('${j['createdAt'] ?? j['startedAt'] ?? ''}')?.toLocal(),
    items: [for (final i in _maps(j['items'])) InvCountItem.fromJson(i)],
  );
}

class InvCountResult {
  const InvCountResult({required this.applied, required this.skipped});
  final int applied;
  final List<String> skipped;
}

class InvLimit {
  const InvLimit({required this.key, required this.label, required this.kind, required this.value, required this.defaultValue});
  final String key, label, kind;
  final int value, defaultValue;
  bool get isMoney => kind == 'minor';

  /// money limits need the response's currency; without it a money limit is not shown (never formatted with a guessed one)
  String? format(int v, InvCur? cur) => isMoney ? cur?.format(v) : '$v';

  factory InvLimit.fromJson(Map<String, dynamic> j) =>
      InvLimit(key: '${j['key'] ?? ''}', label: j['label'] as String? ?? '${j['key']}', kind: j['kind'] as String? ?? 'qty', value: _int(j['value']) ?? 0, defaultValue: _int(j['defaultValue']) ?? 0);
}

/// Server error codes of the inventory endpoints in plain English (the server enforces; this only explains).
String invErrorMessage(String? code, {String? fallback}) => switch (code) {
  'DELTA_INVALID' => 'Enter a whole number of units that is not zero.',
  'REASON_INVALID' => 'Pick a reason for the change.',
  'NOTE_REQUIRED' => 'Add a short note when the reason is "Other".',
  'UNLIMITED_STOCK' => 'This item has unlimited stock, so there is nothing to adjust.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN to change stock.',
  'POS_ACTION_FORBIDDEN' => 'Your role is not allowed to do this.',
  'POS_APPROVAL_REQUIRED' => 'A manager must approve this change.',
  'POS_OWNER_REQUIRED' => 'Only the store owner can do this.',
  'QTY_INVALID' => 'Enter a whole number of units, zero or more.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};
