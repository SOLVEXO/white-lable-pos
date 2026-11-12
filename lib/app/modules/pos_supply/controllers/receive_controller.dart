import 'dart:convert';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// One line being received: how many arrived good and how many damaged, plus the lot number / expiry when the product tracks lots.
class ReceiveLine {
  ReceiveLine({required this.name, this.poItemId, this.variantId, this.sku, this.optionsLabel = '', this.remaining, bool showLot = false, this.costText = '', this.trackSerials = false}) : showLot = showLot.obs;

  /// G5.2: serial-tracked — one serial number per unit (good first, then damaged), typed or scanned one per line
  final bool trackSerials;
  final RxString serialsText = ''.obs;
  List<String> get serials => serialsText.value.split(RegExp(r'[\n,]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
  final String name, optionsLabel;
  final String? poItemId, variantId, sku;

  /// still due on the purchase order (null without a purchase order)
  final int? remaining;
  final RxInt good = 0.obs;
  final RxInt damaged = 0.obs;
  final RxString lotNumber = ''.obs;
  final Rxn<DateTime> expiry = Rxn<DateTime>();

  /// the lot fields are shown: the data says the product tracks lots, or the server asked for a lot (LOT_REQUIRED)
  final RxBool showLot;

  /// direct receiving only: the unit cost typed in the currency's own units
  final RxString costTextRx = ''.obs;
  final String costText;
  int get total => good.value + damaged.value;
}

/// Receiving stock. Against an approved purchase order (everyone the server allows; a cashier sends NO cost, the purchase-order cost is
/// used) or WITHOUT one (managers: pick the supplier and give each line its unit cost, typed in major units, sent as integer minor units
/// at the response's exponent). One `requestId` per submit: a retry of the SAME request sends the same id, so the server answers with the
/// original receipt instead of receiving twice; changing anything makes a new id.
class ReceiveController extends GetxController {
  ReceiveController({this.orderId, this.presetSupplierId, PosRepository? repository, String? storeId, String Function()? requestIdFactory, Duration? searchDebounce})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _newId = requestIdFactory ?? newSupplyRequestId {
    search = SupplyProductSearch(repository: _repo, storeId: () => supplyStoreId(_storeIdOverride), debounce: searchDebounce ?? const Duration(milliseconds: 350));
  }
  final String? orderId;
  final String? presetSupplierId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final String Function() _newId;
  late final SupplyProductSearch search;

  final Rxn<PurchaseOrder> order = Rxn<PurchaseOrder>();
  final RxList<ReceiveLine> lines = <ReceiveLine>[].obs;
  final RxList<Supplier> suppliers = <Supplier>[].obs;
  final Rxn<Supplier> supplier = Rxn<Supplier>();
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxString invoiceNumber = ''.obs;
  final Rxn<DateTime> invoiceDate = Rxn<DateTime>();
  final RxString note = ''.obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString loadError = RxnString();
  final Rxn<ReceiveResult> result = Rxn<ReceiveResult>();

  String? _requestId;
  String? _fingerprint;

  bool get direct => orderId == null;
  int? get exponent => cur.value?.exponent;

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  @override
  void onClose() {
    search.dispose();
    super.onClose();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    loading.value = true;
    loadError.value = null;
    if (!supplyOnline()) {
      loading.value = false;
      return;
    }
    final sid = await supplyStoreId(_storeIdOverride);
    if (direct) {
      final list = await _repo.getSuppliers(sid);
      if (list == null) {
        loadError.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the suppliers. Try again.');
      } else {
        suppliers.assignAll(list.suppliers);
        cur.value = list.cur;
        if (presetSupplierId != null) supplier.value ??= suppliers.firstWhereOrNull((s) => s.id == presetSupplierId);
      }
    } else {
      final d = await _repo.getSupplyOrder(sid, orderId!);
      if (d == null) {
        loadError.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this purchase order. Try again.');
      } else {
        order.value = d.order;
        cur.value = d.order.cur ?? d.cur;
        lines.assignAll([
          for (final i in d.order.items)
            if (i.remaining > 0) ReceiveLine(name: i.name, poItemId: i.id, variantId: i.variantId, sku: i.sku, optionsLabel: i.optionsLabel, remaining: i.remaining, showLot: i.trackLots, trackSerials: i.trackSerials),
        ]);
      }
    }
    loading.value = false;
  }

  void pickSupplier(Supplier s) => supplier.value = s;

  /// Direct receiving: add an existing product as a line (the search tells us whether it tracks lots).
  void addProduct(InvRow row) {
    if (lines.any((l) => l.variantId == row.variantId)) return;
    final l = ReceiveLine(name: row.productName, variantId: row.variantId, sku: row.sku.isEmpty ? null : row.sku, optionsLabel: row.optionsLabel, showLot: row.trackLots, trackSerials: row.trackSerials);
    if (row.costMinor != null && exponent != null) l.costTextRx.value = supplyMinorToText(row.costMinor!, exponent!);
    l.good.value = 1;
    lines.add(l);
  }

  /// G5.1 scan-to-receive: each scan is one more GOOD unit of that line (never above what is still due on the order); receiving without an order
  /// adds the product. Returns the line to show under the camera.
  Future<String> addByCode(String code) async {
    final rows = await _repo.lookupInventory(await supplyStoreId(_storeIdOverride), code);
    if (rows == null) return 'Could not look up $code — check the connection.';
    if (rows.isEmpty) return 'Not found: $code';
    final row = rows.first;
    final line = lines.firstWhereOrNull((l) => l.variantId == row.variantId);
    if (line == null) {
      if (!direct) return '${row.productName} is not on this order';
      addProduct(row);
      return 'Added ${row.productName} — 1';
    }
    final max = maxFor(line, good: true);
    if (max != null && line.good.value >= max) return '${line.name}: all ${line.remaining} already counted';
    line.good.value += 1;
    return '${line.name} — ${line.good.value}${line.remaining != null ? ' of ${line.remaining}' : ''}';
  }

  void removeLine(ReceiveLine l) => lines.remove(l);

  /// Quantities are capped by the stepper at what is still due; the server enforces it anyway (OVER_RECEIPT).
  int? maxFor(ReceiveLine l, {required bool good}) {
    final rem = l.remaining;
    if (rem == null) return null;
    return good ? (rem - l.damaged.value) : (rem - l.good.value);
  }

  bool get hasQuantity => lines.any((l) => l.total > 0);
  bool get canSubmit => hasQuantity && !busy.value && (!direct || supplier.value != null);

  static String _isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// The request body WITHOUT its requestId. A cashier's PO receipt never carries a cost; a direct receipt gives each line its cost in minor units.
  /// Null when a direct line's cost is not a valid amount.
  Map<String, dynamic>? buildPayload() {
    final out = <Map<String, dynamic>>[];
    for (final l in lines) {
      if (l.total == 0) continue;
      final lot = l.lotNumber.value.trim();
      final m = <String, dynamic>{
        if (direct) 'variantId': l.variantId else 'poItemId': l.poItemId,
        'qtyGood': l.good.value,
        'qtyDamaged': l.damaged.value,
        if (lot.isNotEmpty) 'lotNumber': lot,
        if (l.expiry.value != null) 'expiryDate': _isoDay(l.expiry.value!),
        if (l.trackSerials) 'serialNumbers': l.serials,
      };
      if (direct) {
        final c = exponent == null ? null : supplyMinorFromText(l.costTextRx.value, exponent!, allowZero: true);
        if (c == null) return null;
        m['unitCostMinor'] = c;
      }
      out.add(m);
    }
    final inv = invoiceNumber.value.trim();
    final n = note.value.trim();
    return {
      if (direct) 'supplierId': supplier.value?.id else 'purchaseOrderId': orderId,
      'lines': out,
      if (inv.isNotEmpty) 'supplierInvoiceNumber': inv,
      if (invoiceDate.value != null) 'supplierInvoiceDate': _isoDay(invoiceDate.value!),
      if (n.isNotEmpty) 'note': n,
    };
  }

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    if (!hasQuantity) {
      error.value = supplyErrorMessage('LINES_REQUIRED');
      return false;
    }
    if (direct && supplier.value == null) {
      error.value = supplyErrorMessage('SUPPLIER_REQUIRED');
      return false;
    }
    final body = buildPayload();
    if (body == null) {
      error.value = 'Enter the unit cost of every line (at most ${exponent ?? 2} decimal places).';
      return false;
    }
    if (!supplyOnline()) {
      error.value = 'Needs internet.';
      return false;
    }
    // the same request again (a retry after a timeout) keeps its id; a changed request is a new one
    final fp = jsonEncode(body);
    if (_requestId == null || _fingerprint != fp) {
      _requestId = _newId();
      _fingerprint = fp;
    }
    busy.value = true;
    try {
      final r = await _repo.receiveSupply(await supplyStoreId(_storeIdOverride), {...body, 'requestId': _requestId});
      if (!r.success || r.result == null) {
        final code = r.code ?? _repo.lastErrorCode;
        if (code == 'LOT_REQUIRED') {
          for (final l in lines) {
            if (l.good.value > 0 && l.lotNumber.value.trim().isEmpty) l.showLot.value = true;
          }
        }
        error.value = supplyFailure(code, r.message);
        return false;
      }
      result.value = r.result;
      _requestId = null;
      _fingerprint = null;
      return true;
    } finally {
      busy.value = false;
    }
  }
}
