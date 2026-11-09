import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

/// JSON as the G3.1 server sends it, parsed through the real models.
Map<String, dynamic> rowJson({
  String id = 'v1',
  String name = 'Dev Latte',
  String sku = 'DEV-LATTE',
  int stock = 20,
  int committed = 0,
  int damaged = 0,
  bool low = false,
  bool out = false,
  bool unlimited = false,
  bool manager = true,
  List<dynamic> options = const [],
  bool trackLots = false,
}) => {
  'variantId': id,
  'productId': 'p-$id',
  'productName': name,
  'image': null,
  'sku': sku,
  'barcode': '100000000$id',
  'options': options,
  'stock': stock,
  'committed': committed,
  'damaged': damaged,
  'unlimited': unlimited,
  'trackLots': trackLots,
  'reorderPoint': 5,
  'out': out,
  'low': low,
  if (manager) 'costMinor': 250,
  if (manager) 'valueMinor': 250 * stock,
};

InvRow row({String id = 'v1', String name = 'Dev Latte', int stock = 20, bool low = false, bool out = false, bool manager = true, bool unlimited = false}) =>
    InvRow.fromJson(rowJson(id: id, name: name, stock: stock, low: low, out: out, manager: manager, unlimited: unlimited));

Map<String, dynamic> pageJson(List<InvRow> rows, {int total = 0, int page = 1, bool hasMore = false}) => {'items': rows, 'total': total == 0 ? rows.length : total, 'page': page, 'hasMore': hasMore};

InvPage<InvRow> rowsPage(List<InvRow> rows, {int? total, int page = 1, bool hasMore = false}) => InvPage(items: rows, total: total ?? rows.length, page: page, hasMore: hasMore);

InvOverview overview({String role = 'manager', bool openCount = false, int low = 3, int out = 1}) => InvOverview.fromJson({
  'role': role,
  'skuCount': 42,
  'lowStockCount': low,
  'outOfStockCount': out,
  'expiredLots': 1,
  'expiringIn7Days': 2,
  'expiringIn30Days': 4,
  'openStockCount': openCount ? {'id': 'c1', 'startedAt': '2026-11-08T09:30:00.000Z'} : null,
  if (role != 'cashier') 'stockValueMinor': 1234500,
  if (role != 'cashier') 'variantsWithoutCost': 2,
  if (role != 'cashier') 'currencyExponent': 2,
});

InvMovement movement({String id = 'm1', String type = 'sale', int qty = -2, int damaged = 0, String? reason, String? note, bool manager = true}) => InvMovement.fromJson({
  'id': id,
  'at': '2026-11-08T10:15:00.000Z',
  'type': type,
  'qtyDelta': qty,
  'damagedDelta': damaged,
  'reason': reason,
  'note': note,
  'productName': 'Dev Latte',
  'sku': 'DEV-LATTE',
  'variantId': 'v1',
  if (manager) 'unitCostMinor': 250,
});

InvDetail detail({bool manager = true, bool withLots = true, bool withMoves = true, DateTime? ledger, bool unlimited = false, bool noLedger = false}) => InvDetail.fromJson({
  ...rowJson(manager: manager, committed: 2, damaged: 1, trackLots: withLots, unlimited: unlimited),
  'locations': [
    {'locationId': 'l1', 'name': 'Main shop', 'stock': 15},
    {'locationId': 'l2', 'name': 'Back store', 'stock': 5},
  ],
  'lots': withLots
      ? [
          {'lotId': 'lot1', 'lotNumber': 'A-100', 'expiryDate': '2026-11-05T00:00:00.000Z', 'remaining': 3, if (manager) 'costMinor': 240},
          {'lotId': 'lot2', 'lotNumber': 'A-101', 'expiryDate': '2026-11-12T00:00:00.000Z', 'remaining': 7},
          {'lotId': 'lot3', 'lotNumber': 'A-102', 'expiryDate': '2026-12-01T00:00:00.000Z', 'remaining': 10},
        ]
      : [],
  'recentMovements': manager && withMoves
      ? [
          {'id': 'm1', 'at': '2026-11-08T10:15:00.000Z', 'type': 'sale', 'qtyDelta': -2, 'damagedDelta': 0, 'productName': 'Dev Latte', 'sku': 'DEV-LATTE', if (manager) 'unitCostMinor': 250},
          {
            'id': 'm2',
            'at': '2026-11-08T11:00:00.000Z',
            'type': 'adjustment',
            'qtyDelta': 0,
            'damagedDelta': 1,
            'reason': 'damaged',
            'note': 'dropped',
            'productName': 'Dev Latte',
            'sku': 'DEV-LATTE',
          },
        ]
      : [],
  'ledgerStartsAt': noLedger ? null : (ledger ?? DateTime.utc(2026, 11, 1)).toIso8601String(),
  'currencyExponent': 2,
});

InvCount count({int counted = 1, bool item2Counted = false}) => InvCount.fromJson({
  '_id': 'c1',
  'status': 'open',
  'createdAt': '2026-11-08T09:30:00.000Z',
  'items': [
    {'_id': 'i1', 'variantId': 'v1', 'productName': 'Dev Latte', 'sku': 'DEV-LATTE', 'barcode': '1000000000011', 'systemQty': 20, 'countedQty': counted == 0 ? null : 18},
    {'_id': 'i2', 'variantId': 'v2', 'productName': 'Dev Beans 1kg', 'sku': 'DEV-BEANS', 'barcode': '1000000000042', 'systemQty': 8, 'countedQty': item2Counted ? 8 : null},
    {'_id': 'i3', 'variantId': 'v3', 'productName': 'Dev Croissant', 'sku': 'DEV-CROISSANT', 'barcode': '1000000000035', 'systemQty': 2, 'countedQty': null},
  ],
});
