import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// One line of the purchase order being written: an existing variant, how many, and the unit cost typed in the currency's own units.
class PoFormLine {
  PoFormLine({required this.variantId, required this.name, this.sku, this.optionsLabel = '', int qty = 1, String costText = ''}) : qty = qty.obs, costText = costText.obs;
  final String variantId, name, optionsLabel;
  final String? sku;
  final RxInt qty;
  final RxString costText;
}

/// New purchase order or edit of one (managers). Costs are typed in major units and sent as integer MINOR units at the exponent of the
/// currency the server stated (never a configured one). An edit sends the lines again; the server returns an approved / sent order to draft.
class PoFormController extends GetxController {
  PoFormController({this.orderId, this.presetSupplierId, PosRepository? repository, String? storeId, Duration? searchDebounce}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId {
    search = SupplyProductSearch(repository: _repo, storeId: () => supplyStoreId(_storeIdOverride), debounce: searchDebounce ?? const Duration(milliseconds: 350));
  }
  final String? orderId;
  final String? presetSupplierId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  late final SupplyProductSearch search;

  final RxList<Supplier> suppliers = <Supplier>[].obs;
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final Rxn<Supplier> supplier = Rxn<Supplier>();
  final RxList<PoFormLine> lines = <PoFormLine>[].obs;
  final Rxn<DateTime> expectedAt = Rxn<DateTime>();
  final RxString notes = ''.obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString loadError = RxnString();
  PurchaseOrder? _editing;

  bool get isEdit => orderId != null;
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
    final list = await _repo.getSuppliers(sid);
    if (list == null) {
      loadError.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the suppliers. Try again.');
      loading.value = false;
      return;
    }
    suppliers.assignAll(list.suppliers);
    cur.value = list.cur;
    if (isEdit && _editing == null) {
      final d = await _repo.getSupplyOrder(sid, orderId!);
      if (d == null) {
        loadError.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this purchase order. Try again.');
        loading.value = false;
        return;
      }
      final o = _editing = d.order;
      cur.value ??= o.cur ?? d.cur;
      supplier.value = suppliers.firstWhereOrNull((s) => s.id == o.supplierId) ?? (o.supplierId == null ? null : Supplier(id: o.supplierId!, name: o.supplierName));
      expectedAt.value = o.expectedAt;
      notes.value = o.notes;
      final ex = cur.value?.exponent ?? 2;
      lines.assignAll([
        for (final i in o.items)
          PoFormLine(variantId: i.variantId, name: i.name, sku: i.sku, optionsLabel: i.optionsLabel, qty: i.ordered, costText: i.unitCostMinor == null ? '' : supplyMinorToText(i.unitCostMinor!, ex)),
      ]);
    } else if (presetSupplierId != null && supplier.value == null) {
      supplier.value = suppliers.firstWhereOrNull((s) => s.id == presetSupplierId);
    }
    loading.value = false;
  }

  void pickSupplier(Supplier s) => supplier.value = s;

  /// Adds the product as a line (a product already on the order just gets one more). The cost is prefilled from the store's last cost when the server sent one.
  void addProduct(InvRow row) {
    final existing = lines.firstWhereOrNull((l) => l.variantId == row.variantId);
    if (existing != null) {
      existing.qty.value += 1;
      return;
    }
    final ex = exponent ?? 2;
    lines.add(
      PoFormLine(
        variantId: row.variantId,
        name: row.productName,
        sku: row.sku.isEmpty ? null : row.sku,
        optionsLabel: row.optionsLabel,
        costText: row.costMinor == null || exponent == null ? '' : supplyMinorToText(row.costMinor!, ex),
      ),
    );
  }

  /// G5.1 scan-to-add: the scanned barcode / SKU becomes a line (or one more of it). Returns the line to show under the camera.
  Future<String> addByCode(String code) async {
    final rows = await _repo.lookupInventory(await supplyStoreId(_storeIdOverride), code);
    if (rows == null) return 'Could not look up $code — check the connection.';
    if (rows.isEmpty) return 'Not found: $code';
    final row = rows.first;
    addProduct(row);
    final n = lines.firstWhereOrNull((l) => l.variantId == row.variantId)?.qty.value ?? 1;
    return 'Added ${row.productName}${row.optionsLabel.isEmpty ? '' : ' (${row.optionsLabel})'} — $n';
  }

  void removeLine(PoFormLine l) => lines.remove(l);

  /// The unit cost of a line in minor units, or null when the text is not a valid amount for the currency (0 is allowed).
  int? unitCostMinor(PoFormLine l) => exponent == null ? null : supplyMinorFromText(l.costText.value, exponent!, allowZero: true);

  int? get totalMinor {
    var t = 0;
    for (final l in lines) {
      final c = unitCostMinor(l);
      if (c == null) return null;
      t += c * l.qty.value;
    }
    return t;
  }

  bool get canSubmit => supplier.value != null && lines.isNotEmpty && !busy.value && exponent != null;

  /// The request body (cost in minor units at the response's exponent). Null when something is not valid yet.
  Map<String, dynamic>? buildPayload() {
    final s = supplier.value;
    if (s == null || lines.isEmpty || exponent == null) return null;
    final items = <Map<String, dynamic>>[];
    for (final l in lines) {
      final c = unitCostMinor(l);
      if (c == null || l.qty.value < 1) return null;
      items.add({'variantId': l.variantId, 'quantityOrdered': l.qty.value, 'unitCostMinor': c});
    }
    return {
      'supplierId': s.id,
      'items': items,
      if (expectedAt.value != null) 'expectedAt': expectedAt.value!.toUtc().toIso8601String() else if (isEdit) 'expectedAt': null,
      'notes': notes.value.trim(),
    };
  }

  Future<PurchaseOrder?> submit() async {
    if (busy.value) return null;
    error.value = null;
    if (supplier.value == null) {
      error.value = supplyErrorMessage('SUPPLIER_REQUIRED');
      return null;
    }
    if (lines.isEmpty) {
      error.value = supplyErrorMessage('ITEMS_REQUIRED');
      return null;
    }
    if (exponent == null) {
      error.value = 'The currency of this store is not known yet. Reload and try again.';
      return null;
    }
    final payload = buildPayload();
    if (payload == null) {
      error.value = 'Check every line: a whole quantity of 1 or more and a cost with at most $exponent decimal places.';
      return null;
    }
    if (!supplyOnline()) {
      error.value = 'Needs internet.';
      return null;
    }
    busy.value = true;
    try {
      final sid = await supplyStoreId(_storeIdOverride);
      final r = isEdit ? await _repo.updateSupplyOrder(sid, orderId!, payload) : await _repo.createSupplyOrder(sid, payload);
      if (!r.success || r.order == null) {
        error.value = supplyErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return null;
      }
      return r.order;
    } finally {
      busy.value = false;
    }
  }
}
