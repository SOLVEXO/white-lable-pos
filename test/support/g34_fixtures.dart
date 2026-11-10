import 'package:cryptography/cryptography.dart';
import 'package:solvexo_pos/app/data/local/pos_supply_cache.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';

/// A supply-orders cache with a fixed key (no secure storage needed in tests).
SupplyOrdersCache testSupplyCache() => SupplyOrdersCache(
  sealed: SealedText(cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 7)))),
);

const usd = InvCur('USD', 2);
const jpy = InvCur('JPY', 0);
const kwd = InvCur('KWD', 3);

/// A purchase-order line exactly as the server sends it; [costs] false = what a cashier gets (no money fields at all).
Map<String, dynamic> poLineJson({
  String id = 'li1',
  String variantId = 'v1',
  String name = 'Dev Latte',
  int ordered = 10,
  int received = 0,
  int damaged = 0,
  int unitCostMinor = 250,
  bool costs = true,
  bool? trackLots,
}) => {
  'id': id,
  'productId': 'p-$variantId',
  'variantId': variantId,
  'name': name,
  'sku': 'DEV-$variantId',
  'image': null,
  'options': [
    {'name': 'Size', 'value': 'Large'},
  ],
  'quantityOrdered': ordered,
  'quantityReceived': received,
  'quantityDamaged': damaged,
  'quantityReturned': 0,
  'quantityRemaining': (ordered - received - damaged).clamp(0, ordered),
  if (costs) 'unitCostMinor': unitCostMinor,
  if (costs) 'lineTotalMinor': unitCostMinor * ordered,
  'trackLots': trackLots,
};

Map<String, dynamic> poJson({
  String id = 'po1',
  String number = 'PO-000001',
  String status = 'approved',
  bool costs = true,
  List<Map<String, dynamic>>? items,
  String currency = 'USD',
  int exponent = 2,
  bool editable = true,
  String supplierName = 'Dev Supplies',
}) => {
  'id': id,
  'poNumber': number,
  'status': status,
  'supplierId': 's1',
  'supplierName': supplierName,
  'locationId': null,
  'expectedAt': '2026-11-20T00:00:00.000Z',
  'notes': 'Call first',
  'createdAt': '2026-11-01T09:00:00.000Z',
  'currency': currency,
  'currencyExponent': exponent,
  'editable': editable,
  'items': items ?? [poLineJson(costs: costs)],
  if (costs) 'subtotalMinor': 2500,
  if (costs) 'shippingMinor': 100,
  if (costs) 'taxMinor': 50,
  if (costs) 'totalMinor': 2650,
};

PurchaseOrder po({String id = 'po1', String status = 'approved', bool costs = true, List<Map<String, dynamic>>? items, bool editable = true}) =>
    PurchaseOrder.fromJson(poJson(id: id, status: status, costs: costs, items: items, editable: editable));

Map<String, dynamic> poListData(List<Map<String, dynamic>> orders, {String currency = 'USD', int exponent = 2}) => {'currency': currency, 'currencyExponent': exponent, 'orders': orders};
PoList poList(List<Map<String, dynamic>> orders) => PoList.fromJson(poListData(orders));

Supplier supplier({String id = 's1', String name = 'Dev Supplies', int? balance = 5000, int? open = 2}) =>
    Supplier(id: id, name: name, contactName: 'Sam', phone: '0300111', ntn: '1234567-8', strn: 'STRN-1', paymentTerms: 'Net 30', balanceMinor: balance, openOrders: open);

SupplierList supplierList(List<Supplier> s, {InvCur? cur = usd}) => SupplierList(suppliers: s, cur: cur);

Map<String, dynamic> receiptJson({String id = 'r1', String number = 'GRN-000001', bool costs = true, String? lot}) => {
  'id': id,
  'receiptNumber': number,
  'purchaseOrderId': 'po1',
  'poNumber': 'PO-000001',
  'supplierId': 's1',
  'supplierName': 'Dev Supplies',
  'createdAt': '2026-11-09T10:00:00.000Z',
  'currency': 'USD',
  'currencyExponent': 2,
  'lines': [
    {
      'id': 'rl1',
      'poItemId': 'li1',
      'variantId': 'v1',
      'productId': 'p-v1',
      'name': 'Dev Latte',
      'qtyGood': 8,
      'qtyDamaged': 2,
      'lotId': lot == null ? null : 'lot1',
      'lotNumber': lot,
      'expiryDate': null,
      if (costs) 'unitCostMinor': 250,
      if (costs) 'lineTotalMinor': 2500,
    },
  ],
  if (costs) 'totalMinor': 2500,
};

SupplyReceipt receipt({bool costs = true, String? lot}) => SupplyReceipt.fromJson(receiptJson(costs: costs, lot: lot));

ReceiveResult receiveResult({bool costs = true, bool duplicate = false}) =>
    ReceiveResult.fromJson({'currency': 'USD', 'currencyExponent': 2, 'receipt': receiptJson(costs: costs), 'order': null, 'duplicate': duplicate});

Aging aging({int balance = 5000, int current = 3000, int d30 = 1500, int d60 = 500, int d90 = 0}) => Aging(balanceMinor: balance, currentMinor: current, d30Minor: d30, d60Minor: d60, d90Minor: d90);

SupplierProfile supplierProfile({InvCur? cur = usd}) => SupplierProfile(supplier: supplier(), aging: aging(), orders: [po()], receipts: [receipt()], cur: cur);

Payables payables({InvCur? cur = usd}) => Payables(
  totals: aging(balance: 8000, current: 5000, d30: 2000, d60: 1000),
  suppliers: [
    PayableRow(supplierId: 's1', supplierName: 'Dev Supplies', aging: aging()),
    PayableRow(supplierId: 's2', supplierName: 'Other Co', aging: aging(balance: 3000, current: 2000, d30: 1000, d60: 0)),
  ],
  cur: cur,
);

SupplierLedger ledger({InvCur? cur = usd}) => SupplierLedger(
  supplier: supplier(),
  aging: aging(),
  cur: cur,
  entries: [
    LedgerEntry(id: 'e2', type: 'payment', amountMinor: -1000, balanceAfterMinor: 5000, method: 'bank', reference: 'TT-9', createdAt: DateTime(2026, 11, 8)),
    LedgerEntry(id: 'e1', type: 'bill', amountMinor: 6000, balanceAfterMinor: 6000, refNumber: 'GRN-000001', createdAt: DateTime(2026, 11, 1)),
  ],
);

InvRow invRow({String id = 'v1', String name = 'Dev Latte', bool trackLots = false, int? costMinor = 250}) =>
    InvRow.fromJson({'variantId': id, 'productId': 'p-$id', 'productName': name, 'sku': 'DEV-$id', 'stock': 5, 'trackLots': trackLots, if (costMinor != null) 'costMinor': costMinor});
