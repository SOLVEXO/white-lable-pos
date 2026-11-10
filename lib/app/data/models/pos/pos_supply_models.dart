import 'dart:math';

import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

/// G3.4 supply: suppliers, purchase orders, goods receipts, supplier returns, payables and payments. Money is integer MINOR units
/// (`...Minor`) next to the response's own currency and exponent ([InvCur]). A field the server leaves out (a cashier never gets costs)
/// stays null and nothing is rendered for it; there is no fallback currency.
int? _int(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
String _id(Map<String, dynamic> j) => '${j['id'] ?? j['_id'] ?? ''}';

/// A client-made id for ONE submit of a receipt / payment / return. The same id is sent again when the same submit is retried, so the
/// server can recognise the retry (`duplicate: true`) instead of doing it twice.
String newSupplyRequestId([Random? random]) {
  final r = random ?? Random.secure();
  final bits = List<int>.generate(8, (_) => r.nextInt(256));
  return 'sup-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${bits.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// What the cashier / manager typed in the currency's own units ("12.5") as integer minor units (1250 at exponent 2). Null when it is not
/// a number, has more decimals than the currency allows, or is zero (unless [allowZero]).
int? supplyMinorFromText(String text, int exponent, {bool allowZero = false}) {
  final t = text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{1,12})(?:\.(\d*))?$').firstMatch(t);
  if (m == null) return null;
  final frac = m.group(2) ?? '';
  if (frac.length > exponent) return null;
  var p = 1;
  for (var i = 0; i < exponent; i++) {
    p *= 10;
  }
  final minor = int.parse(m.group(1)!) * p + (frac.isEmpty ? 0 : int.parse(frac.padRight(exponent, '0')));
  return (minor > 0 || allowZero) ? minor : null;
}

/// Minor units as the plain text a field shows ("1250" at exponent 2 -> "12.50").
String supplyMinorToText(int minor, int exponent) {
  if (exponent == 0) return '$minor';
  var p = 1;
  for (var i = 0; i < exponent; i++) {
    p *= 10;
  }
  return '${minor ~/ p}.${(minor % p).toString().padLeft(exponent, '0')}';
}

abstract final class PoStatus {
  static const draft = 'draft', approved = 'approved', sent = 'sent', partiallyReceived = 'partially_received', received = 'received', closedShort = 'closed_short', cancelled = 'cancelled';

  /// the filter chips of the list (`all` plus the six the till works with)
  static const filters = <(String, String)>[
    ('all', 'All'),
    (draft, 'Draft'),
    (approved, 'Approved'),
    (sent, 'Sent'),
    (partiallyReceived, 'Partially received'),
    (received, 'Received'),
    (cancelled, 'Cancelled'),
  ];

  static String label(String s) => switch (s) {
    draft => 'Draft',
    approved => 'Approved',
    sent => 'Sent',
    'ordered' => 'Ordered',
    partiallyReceived => 'Partially received',
    received => 'Received',
    closedShort => 'Closed short',
    cancelled => 'Cancelled',
    '' => 'Unknown',
    _ => '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}',
  };

  static bool receivable(String s) => s == approved || s == sent || s == partiallyReceived;
}

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.ntn,
    this.strn,
    this.paymentTerms,
    this.leadTimeDays,
    this.notes,
    this.status = 'active',
    this.balanceMinor,
    this.openOrders,
  });
  final String id, name, status;
  final String? contactName, phone, email, address, ntn, strn, paymentTerms, notes;
  final int? leadTimeDays;

  /// what the store owes this supplier (list only; absent = not stated, shows no money)
  final int? balanceMinor;
  final int? openOrders;

  String get contact => [if (contactName != null) contactName!, if (phone != null) phone!].join(' · ');

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
    id: _id(j),
    name: j['name'] as String? ?? '',
    contactName: _str(j['contactName']),
    phone: _str(j['phone']),
    email: _str(j['email']),
    address: _str(j['address']),
    ntn: _str(j['ntn']),
    strn: _str(j['strn']),
    paymentTerms: _str(j['paymentTerms']),
    leadTimeDays: _int(j['leadTimeDays']),
    notes: _str(j['notes']),
    status: j['status'] as String? ?? 'active',
    balanceMinor: _int(j['balanceMinor']),
    openOrders: _int(j['openOrders']),
  );
}

class SupplierList {
  const SupplierList({required this.suppliers, this.cur});
  final List<Supplier> suppliers;
  final InvCur? cur;
  factory SupplierList.fromJson(Map<String, dynamic> j) => SupplierList(suppliers: [for (final s in _maps(j['suppliers'])) Supplier.fromJson(s)], cur: InvCur.fromJson(j));
}

class Aging {
  const Aging({this.balanceMinor = 0, this.currentMinor = 0, this.d30Minor = 0, this.d60Minor = 0, this.d90Minor = 0});
  final int balanceMinor, currentMinor, d30Minor, d60Minor, d90Minor;
  factory Aging.fromJson(Map<String, dynamic> j) => Aging(
    balanceMinor: _int(j['balanceMinor']) ?? 0,
    currentMinor: _int(j['currentMinor']) ?? 0,
    d30Minor: _int(j['d30Minor']) ?? 0,
    d60Minor: _int(j['d60Minor']) ?? 0,
    d90Minor: _int(j['d90Minor']) ?? 0,
  );
}

class PoLine {
  const PoLine({
    required this.id,
    required this.variantId,
    required this.productId,
    required this.name,
    this.sku,
    this.options = const [],
    this.ordered = 0,
    this.received = 0,
    this.damaged = 0,
    this.returned = 0,
    this.remaining = 0,
    this.unitCostMinor,
    this.lineTotalMinor,
    this.trackLots = false,
  });
  final String id, variantId, productId, name;
  final String? sku;
  final List<String> options;
  final int ordered, received, damaged, returned, remaining;

  /// absent for a cashier (the server hides costs)
  final int? unitCostMinor, lineTotalMinor;

  /// the variant tracks lots (the server states it on every PO line): the receive screen shows the lot number and expiry up front
  final bool trackLots;

  String get optionsLabel => options.join(' · ');

  factory PoLine.fromJson(Map<String, dynamic> j) => PoLine(
    id: _id(j),
    variantId: '${j['variantId'] ?? ''}',
    productId: '${j['productId'] ?? ''}',
    name: j['name'] as String? ?? '',
    sku: _str(j['sku']),
    options: [
      for (final o in (j['options'] as List? ?? const []))
        if (o is Map) '${o['value'] ?? o['name'] ?? ''}' else '$o',
    ].where((e) => e.isNotEmpty).toList(),
    ordered: _int(j['quantityOrdered']) ?? 0,
    received: _int(j['quantityReceived']) ?? 0,
    damaged: _int(j['quantityDamaged']) ?? 0,
    returned: _int(j['quantityReturned']) ?? 0,
    remaining: _int(j['quantityRemaining']) ?? 0,
    unitCostMinor: _int(j['unitCostMinor']),
    lineTotalMinor: _int(j['lineTotalMinor']),
    trackLots: j['trackLots'] == true,
  );
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.poNumber,
    required this.status,
    required this.supplierName,
    this.supplierId,
    this.locationId,
    this.expectedAt,
    this.notes = '',
    this.approvedBy,
    this.approvedAt,
    this.sentAt,
    this.receivedAt,
    this.createdAt,
    this.cur,
    this.editable = false,
    this.items = const [],
    this.subtotalMinor,
    this.shippingMinor,
    this.taxMinor,
    this.totalMinor,
  });
  final String id, poNumber, status, supplierName, notes;
  final String? supplierId, locationId, approvedBy;
  final DateTime? expectedAt, approvedAt, sentAt, receivedAt, createdAt;
  final InvCur? cur;
  final bool editable;
  final List<PoLine> items;
  final int? subtotalMinor, shippingMinor, taxMinor, totalMinor;

  /// the server sent costs (managers / owners); a cashier's order has none
  bool get hasCosts => totalMinor != null;
  bool get receivable => PoStatus.receivable(status);
  bool get partlyReceived => status == PoStatus.partiallyReceived;
  int get remainingUnits => items.fold(0, (s, i) => s + i.remaining);

  factory PurchaseOrder.fromJson(Map<String, dynamic> j) => PurchaseOrder(
    id: _id(j),
    poNumber: '${j['poNumber'] ?? ''}',
    status: j['status'] as String? ?? '',
    supplierName: j['supplierName'] as String? ?? '',
    supplierId: _str(j['supplierId']),
    locationId: _str(j['locationId']),
    expectedAt: _date(j['expectedAt']),
    notes: j['notes'] as String? ?? '',
    approvedBy: _str(j['approvedBy']),
    approvedAt: _date(j['approvedAt']),
    sentAt: _date(j['sentAt']),
    receivedAt: _date(j['receivedAt']),
    createdAt: _date(j['createdAt']),
    cur: InvCur.fromJson(j),
    editable: j['editable'] == true,
    items: [for (final i in _maps(j['items'])) PoLine.fromJson(i)],
    subtotalMinor: _int(j['subtotalMinor']),
    shippingMinor: _int(j['shippingMinor']),
    taxMinor: _int(j['taxMinor']),
    totalMinor: _int(j['totalMinor']),
  );
}

class PoList {
  const PoList({required this.orders, this.cur, this.asOf, this.raw});
  final List<PurchaseOrder> orders;
  final InvCur? cur;

  /// set when the list came from the on-device copy (read only)
  final DateTime? asOf;

  /// the response `data` as received (what the offline copy stores)
  final Map<String, dynamic>? raw;

  PoList withAsOf(DateTime t) => PoList(orders: orders, cur: cur, asOf: t, raw: raw);

  factory PoList.fromJson(Map<String, dynamic> j) {
    final cur = InvCur.fromJson(j);
    return PoList(
      orders: [
        for (final o in _maps(j['orders']))
          PurchaseOrder.fromJson({...o, if (cur != null && o['currency'] == null) 'currency': cur.code, if (cur != null && o['currencyExponent'] == null) 'currencyExponent': cur.exponent}),
      ],
      cur: cur,
      raw: j,
    );
  }
}

class ReceiptLine {
  const ReceiptLine({
    required this.id,
    required this.variantId,
    required this.name,
    this.poItemId,
    this.sku,
    this.qtyGood = 0,
    this.qtyDamaged = 0,
    this.lotId,
    this.lotNumber,
    this.expiryDate,
    this.unitCostMinor,
    this.lineTotalMinor,
  });
  final String id, variantId, name;
  final String? poItemId, sku, lotId, lotNumber;
  final int qtyGood, qtyDamaged;
  final DateTime? expiryDate;
  final int? unitCostMinor, lineTotalMinor;

  /// good + damaged: what can still go back to the supplier (before earlier returns)
  int get qtyTotal => qtyGood + qtyDamaged;

  factory ReceiptLine.fromJson(Map<String, dynamic> j) => ReceiptLine(
    id: _id(j),
    variantId: '${j['variantId'] ?? ''}',
    name: j['name'] as String? ?? '',
    poItemId: _str(j['poItemId']),
    sku: _str(j['sku']),
    qtyGood: _int(j['qtyGood']) ?? 0,
    qtyDamaged: _int(j['qtyDamaged']) ?? 0,
    lotId: _str(j['lotId']),
    lotNumber: _str(j['lotNumber']),
    expiryDate: _date(j['expiryDate']),
    unitCostMinor: _int(j['unitCostMinor']),
    lineTotalMinor: _int(j['lineTotalMinor']),
  );
}

class SupplyReceipt {
  const SupplyReceipt({
    required this.id,
    required this.receiptNumber,
    required this.supplierName,
    this.purchaseOrderId,
    this.poNumber,
    this.supplierId,
    this.supplierInvoiceNumber,
    this.supplierInvoiceDate,
    this.note,
    this.createdAt,
    this.cur,
    this.lines = const [],
    this.totalMinor,
  });
  final String id, receiptNumber, supplierName;
  final String? purchaseOrderId, poNumber, supplierId, supplierInvoiceNumber, note;
  final DateTime? supplierInvoiceDate, createdAt;
  final InvCur? cur;
  final List<ReceiptLine> lines;
  final int? totalMinor;

  factory SupplyReceipt.fromJson(Map<String, dynamic> j) => SupplyReceipt(
    id: _id(j),
    receiptNumber: '${j['receiptNumber'] ?? ''}',
    supplierName: j['supplierName'] as String? ?? '',
    purchaseOrderId: _str(j['purchaseOrderId']),
    poNumber: _str(j['poNumber']),
    supplierId: _str(j['supplierId']),
    supplierInvoiceNumber: _str(j['supplierInvoiceNumber']),
    supplierInvoiceDate: _date(j['supplierInvoiceDate']),
    note: _str(j['note']),
    createdAt: _date(j['createdAt']),
    cur: InvCur.fromJson(j),
    lines: [for (final l in _maps(j['lines'])) ReceiptLine.fromJson(l)],
    totalMinor: _int(j['totalMinor']),
  );
}

class PoDetail {
  const PoDetail({required this.order, this.receipts = const [], this.cur});
  final PurchaseOrder order;
  final List<SupplyReceipt> receipts;
  final InvCur? cur;
  factory PoDetail.fromJson(Map<String, dynamic> j) {
    final cur = InvCur.fromJson(j);
    return PoDetail(order: PurchaseOrder.fromJson(_map(j['order'])), receipts: [for (final r in _maps(j['receipts'])) SupplyReceipt.fromJson(r)], cur: cur);
  }
}

class SupplierProfile {
  const SupplierProfile({required this.supplier, required this.aging, this.orders = const [], this.receipts = const [], this.cur});
  final Supplier supplier;
  final Aging aging;
  final List<PurchaseOrder> orders;
  final List<SupplyReceipt> receipts;
  final InvCur? cur;
  factory SupplierProfile.fromJson(Map<String, dynamic> j) => SupplierProfile(
    supplier: Supplier.fromJson(_map(j['supplier'])),
    aging: Aging.fromJson(_map(j['aging'])),
    orders: [for (final o in _maps(j['orders'])) PurchaseOrder.fromJson(o)],
    receipts: [for (final r in _maps(j['receipts'])) SupplyReceipt.fromJson(r)],
    cur: InvCur.fromJson(j),
  );
}

class ReceiveResult {
  const ReceiveResult({required this.receipt, this.order, this.duplicate = false, this.cur});
  final SupplyReceipt receipt;
  final PurchaseOrder? order;
  final bool duplicate;
  final InvCur? cur;
  factory ReceiveResult.fromJson(Map<String, dynamic> j) => ReceiveResult(
    receipt: SupplyReceipt.fromJson(_map(j['receipt'])),
    order: j['order'] is Map ? PurchaseOrder.fromJson(_map(j['order'])) : null,
    duplicate: j['duplicate'] == true,
    cur: InvCur.fromJson(j),
  );
}

class SupplierReturnResult {
  const SupplierReturnResult({
    required this.id,
    required this.returnNumber,
    required this.supplierName,
    required this.reason,
    this.creditMinor,
    this.duplicate = false,
    this.cur,
    this.items = const [],
  });
  final String id, returnNumber, supplierName, reason;
  final int? creditMinor;
  final bool duplicate;
  final InvCur? cur;
  final List<({String name, int quantity})> items;
  factory SupplierReturnResult.fromJson(Map<String, dynamic> j) {
    final r = _map(j['return']);
    return SupplierReturnResult(
      id: _id(r),
      returnNumber: '${r['returnNumber'] ?? ''}',
      supplierName: r['supplierName'] as String? ?? '',
      reason: r['reason'] as String? ?? 'other',
      creditMinor: _int(r['creditMinor']),
      duplicate: j['duplicate'] == true,
      cur: InvCur.fromJson(j),
      items: [for (final i in _maps(r['items'])) (name: i['name'] as String? ?? '', quantity: _int(i['quantity']) ?? 0)],
    );
  }
}

class PayableRow {
  const PayableRow({required this.supplierId, required this.supplierName, required this.aging});
  final String supplierId, supplierName;
  final Aging aging;
  factory PayableRow.fromJson(Map<String, dynamic> j) => PayableRow(supplierId: '${j['supplierId'] ?? ''}', supplierName: j['supplierName'] as String? ?? 'Supplier', aging: Aging.fromJson(j));
}

class Payables {
  const Payables({required this.totals, required this.suppliers, this.cur});
  final Aging totals;
  final List<PayableRow> suppliers;
  final InvCur? cur;
  factory Payables.fromJson(Map<String, dynamic> j) =>
      Payables(totals: Aging.fromJson(_map(j['totals'])), suppliers: [for (final s in _maps(j['suppliers'])) PayableRow.fromJson(s)], cur: InvCur.fromJson(j));
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.balanceAfterMinor,
    this.refNumber,
    this.method,
    this.reference,
    this.supplierInvoiceNumber,
    this.note,
    this.createdAt,
  });
  final String id, type;
  final int amountMinor, balanceAfterMinor;
  final String? refNumber, method, reference, supplierInvoiceNumber, note;
  final DateTime? createdAt;

  String get typeLabel => switch (type) {
    'bill' => 'Goods received',
    'payment' => 'Payment',
    'credit' => 'Return credit',
    'adjustment' => 'Adjustment',
    _ => type.isEmpty ? 'Entry' : '${type[0].toUpperCase()}${type.substring(1)}',
  };

  factory LedgerEntry.fromJson(Map<String, dynamic> j) => LedgerEntry(
    id: _id(j),
    type: j['type'] as String? ?? '',
    amountMinor: _int(j['amountMinor']) ?? 0,
    balanceAfterMinor: _int(j['balanceAfterMinor']) ?? 0,
    refNumber: _str(j['refNumber']),
    method: _str(j['method']),
    reference: _str(j['reference']),
    supplierInvoiceNumber: _str(j['supplierInvoiceNumber']),
    note: _str(j['note']),
    createdAt: _date(j['createdAt']),
  );
}

class SupplierLedger {
  const SupplierLedger({required this.supplier, required this.aging, required this.entries, this.cur});
  final Supplier supplier;
  final Aging aging;
  final List<LedgerEntry> entries;
  final InvCur? cur;
  factory SupplierLedger.fromJson(Map<String, dynamic> j) => SupplierLedger(
    supplier: Supplier.fromJson(_map(j['supplier'])),
    aging: Aging.fromJson(_map(j['aging'])),
    entries: [for (final e in _maps(j['entries'])) LedgerEntry.fromJson(e)],
    cur: InvCur.fromJson(j),
  );
}

class SupplierPaymentResult {
  const SupplierPaymentResult({required this.amountMinor, required this.method, this.balanceMinor, this.duplicate = false, this.cur});
  final int amountMinor;
  final String method;
  final int? balanceMinor;
  final bool duplicate;
  final InvCur? cur;
  factory SupplierPaymentResult.fromJson(Map<String, dynamic> j) {
    final p = _map(j['payment']);
    return SupplierPaymentResult(
      amountMinor: _int(p['amountMinor']) ?? 0,
      method: p['method'] as String? ?? '',
      balanceMinor: _int(j['balanceMinor']),
      duplicate: j['duplicate'] == true,
      cur: InvCur.fromJson(j),
    );
  }
}

const supplierReturnReasons = <(String, String)>[
  ('damaged', 'Damaged'),
  ('defective', 'Defective'),
  ('wrong_item', 'Wrong item'),
  ('overstock', 'Overstock'),
  ('expired', 'Expired'),
  ('other', 'Other'),
];

String supplyMethodLabel(String? m) => switch (m) {
  'cash' => 'Cash',
  'bank' => 'Bank',
  'other' => 'Other',
  _ => '',
};

/// Server error codes of the supply endpoints in plain English (the server enforces; this only explains).
String supplyErrorMessage(String? code, {String? fallback}) => switch (code) {
  'OVER_RECEIPT' => 'That is more than is still due on this purchase order. Lower the quantity.',
  'LOT_REQUIRED' => 'This product tracks lots. Enter the lot number from the supplier\'s delivery.',
  'PO_NOT_EDITABLE' => 'Receiving has started on this purchase order, so it can no longer be edited. Create a new one for the rest.',
  'PO_NOT_CANCELLABLE' => 'Receiving has started. Close the order short instead of cancelling it.',
  'PO_NOT_DRAFT' => 'Only a draft purchase order can be approved.',
  'PO_NOT_APPROVED' => 'Only an approved purchase order can be sent.',
  'PO_NOT_PARTIAL' => 'Only a partially received purchase order can be closed short.',
  'PO_NOT_RECEIVABLE' => 'This purchase order cannot be received right now. It must be approved first.',
  'PO_NOT_FOUND' => 'That purchase order was not found.',
  'SUPPLIER_NOT_FOUND' => 'That supplier was not found.',
  'SUPPLIER_REQUIRED' => 'Choose a supplier.',
  'NAME_REQUIRED' => 'Enter the supplier\'s name.',
  'ITEMS_REQUIRED' => 'Add at least one product.',
  'LINES_REQUIRED' => 'Enter a quantity for at least one product.',
  'DUPLICATE_LINE' => 'The same product is listed twice. Combine the quantities into one line.',
  'INVALID_QUANTITY' => 'Enter whole numbers of units.',
  'INVALID_AMOUNT' => 'Enter a valid amount.',
  'INVALID_DATE' => 'One of the dates is not valid.',
  'INVALID_EXPIRY' => 'The expiry date is not valid.',
  'INVALID_METHOD' => 'Choose how it was paid: cash, bank or other.',
  'EXCEEDS_BALANCE' => 'That is more than is owed to this supplier.',
  'EXCEEDS_RECEIPT' => 'That is more than is left of this receipt to send back.',
  'NOT_ON_RECEIPT' => 'That product was not on the receipt.',
  'NO_OPEN_SHIFT' => 'Paying cash from the drawer needs an open shift.',
  'COST_NOT_ALLOWED' => 'A cashier receives at the purchase-order cost. Costs cannot be entered here.',
  'SERIALS_NOT_SUPPORTED' => 'This product is serial-tracked. Receive it from the dashboard so each serial number is recorded.',
  'UNLIMITED_STOCK' => 'This product has unlimited stock, so there is nothing to receive.',
  'POS_OWNER_REQUIRED' => 'This amount is above the manager limit. The store owner must do this.',
  'POS_APPROVAL_REQUIRED' => 'A manager must approve this.',
  'POS_ACTION_FORBIDDEN' => 'Your role is not allowed to do this.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};
