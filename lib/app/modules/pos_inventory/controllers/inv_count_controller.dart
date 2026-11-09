import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Stock count by scan. A manager starts and finishes / cancels it; any signed-in person may enter counts. The server owns every rule
/// (one open count per store, who may finish, how variances are posted) — this only drives the screens.
class InvCountController extends GetxController {
  InvCountController({PosRepository? repository, String? storeId, String? role})
      : _repo = repository ?? PosRepository(),
        _storeIdOverride = storeId,
        _roleOverride = role {
    if (role != null) this.role.value = role;
  }
  final PosRepository _repo;
  final String? _storeIdOverride, _roleOverride;

  final Rxn<InvCount> count = Rxn<InvCount>();
  final RxList<InvCount> history = <InvCount>[].obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxString role = InvRole.cashier.obs;

  /// The line being counted (from a scan / typed code / a tap on the list) and the quantity typed for it.
  final Rxn<InvCountItem> current = Rxn<InvCountItem>();
  final RxInt qty = 0.obs;
  final RxBool notOnCount = false.obs;
  final RxnString lastSaved = RxnString();

  /// Set after Finish: what the server applied.
  final Rxn<InvCountResult> result = Rxn<InvCountResult>();
  String storeId = '';

  bool get canManage => InvRole.canManage(role.value);
  bool get hasOpenCount => count.value?.isOpen ?? false;

  @override
  void onInit() {
    super.onInit();
    if (_roleOverride == null) invGuessRole().then((r) => role.value = r);
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      storeId = await invStoreId(_storeIdOverride);
      final list = await _repo.listInventoryCounts(storeId);
      if (list == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the stock counts. Check the connection and try again.');
        return;
      }
      history.assignAll(list);
      final open = list.firstWhereOrNull((c) => c.isOpen);
      if (open == null) {
        count.value = null;
        return;
      }
      // the list may not carry the lines: always read the open count itself
      final full = await _repo.getInventoryCount(storeId, open.id);
      if (full == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not open the stock count.');
        return;
      }
      count.value = full;
    } finally {
      loading.value = false;
    }
  }

  Future<bool> start() async {
    if (busy.value || !canManage) return false;
    busy.value = true;
    error.value = null;
    try {
      final r = await _repo.startInventoryCount(storeId.isEmpty ? await invStoreId(_storeIdOverride) : storeId);
      if (!r.success || r.count == null) {
        error.value = r.code == 'POS_ACTION_FORBIDDEN' ? 'Only a manager can start a stock count.' : (r.message ?? invErrorMessage(r.code, fallback: 'Could not start the stock count.'));
        return false;
      }
      count.value = r.count;
      return true;
    } finally {
      busy.value = false;
    }
  }

  void select(InvCountItem item) {
    notOnCount.value = false;
    lastSaved.value = null;
    current.value = item;
    qty.value = item.countedQty ?? 0;
  }

  void clearCurrent() {
    current.value = null;
    notOnCount.value = false;
  }

  void setQty(int v) => qty.value = v < 0 ? 0 : v;

  /// Resolve a scanned / typed barcode or SKU to its line on this count.
  Future<bool> find(String code) async {
    final c = count.value;
    if (c == null || code.trim().isEmpty || busy.value) return false;
    busy.value = true;
    error.value = null;
    notOnCount.value = false;
    lastSaved.value = null;
    try {
      final r = await _repo.findInventoryCountItem(storeId, c.id, code);
      if (r == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not look that code up. Check the connection and try again.');
        return false;
      }
      if (!r.found || r.item == null) {
        current.value = null;
        notOnCount.value = true;
        return false;
      }
      // the local copy is the freshest: prefill with the previous counted value
      final local = c.items.firstWhereOrNull((i) => i.id == r.item!.id) ?? r.item!;
      select(local);
      return true;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> saveCurrent() async {
    final c = count.value, it = current.value;
    if (c == null || it == null || busy.value) return false;
    busy.value = true;
    error.value = null;
    try {
      final r = await _repo.enterInventoryCount(storeId, c.id, it.id, qty.value);
      if (!r.success) {
        error.value = invErrorMessage(r.code, fallback: r.message);
        return false;
      }
      count.value =
          r.count ?? c.copyWithItem(InvCountItem(id: it.id, variantId: it.variantId, productName: it.productName, sku: it.sku, barcode: it.barcode, systemQty: it.systemQty, countedQty: qty.value));
      lastSaved.value = '${it.productName}: counted ${qty.value}';
      current.value = null;
      return true;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> finish() async {
    final c = count.value;
    if (c == null || busy.value || !canManage) return false;
    busy.value = true;
    error.value = null;
    try {
      final r = await _repo.finishInventoryCount(storeId, c.id);
      if (!r.success || r.result == null) {
        error.value = r.code == 'POS_ACTION_FORBIDDEN' ? 'Only a manager can finish a stock count.' : (r.message ?? invErrorMessage(r.code, fallback: 'Could not finish the stock count.'));
        return false;
      }
      result.value = r.result;
      count.value = null;
      return true;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> cancel() async {
    final c = count.value;
    if (c == null || busy.value || !canManage) return false;
    busy.value = true;
    error.value = null;
    try {
      final r = await _repo.cancelInventoryCount(storeId, c.id);
      if (!r.success) {
        error.value = r.message ?? invErrorMessage(r.code, fallback: 'Could not cancel the stock count.');
        return false;
      }
      count.value = null;
      current.value = null;
      return true;
    } finally {
      busy.value = false;
    }
  }
}
