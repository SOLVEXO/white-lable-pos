import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_supply_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// Purchase orders. A manager sees every order (with costs) and can filter by status; a cashier is sent only the receivable orders and NO
/// money (the server hides it, so none is rendered). Online it always asks the server and remembers the answer; offline it shows the last
/// remembered list, READ ONLY, marked "Last synced <time>" ([asOf]). With nothing remembered, offline shows "Needs internet".
class PoListController extends GetxController {
  PoListController({PosRepository? repository, SupplyOrdersCache? cache, String? storeId, this.supplierId})
    : _repo = repository ?? PosRepository(),
      _cache = cache ?? SupplyOrdersCache.instance,
      _storeIdOverride = storeId;
  final PosRepository _repo;
  final SupplyOrdersCache _cache;
  final String? _storeIdOverride;
  final String? supplierId;

  final RxList<PurchaseOrder> orders = <PurchaseOrder>[].obs;
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxString status = 'all'.obs;

  /// set when the list on screen is the remembered copy (read only)
  final Rxn<DateTime> asOf = Rxn<DateTime>();

  /// true when offline with nothing remembered: the screen says "Needs internet"
  final RxBool needsInternet = false.obs;
  final RxBool canManageHint = false.obs;
  Worker? _online;

  /// Managers see costs and every status; the server sent no money to a cashier.
  bool get canManage => canManageHint.value || orders.any((o) => o.hasCosts);
  bool get readOnly => asOf.value != null;

  /// the orders under the selected chip (offline the chip filters the remembered list on the till)
  List<PurchaseOrder> get visible => (status.value == 'all' || !readOnly) ? orders : orders.where((o) => o.status == status.value).toList();

  @override
  void onInit() {
    super.onInit();
    supplyGuessCanManage().then((v) => canManageHint.value = v);
    load();
    _online = ever<bool>(supplyOnlineRx(), (on) {
      if (on) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  void setStatus(String s) {
    if (status.value == s) return;
    status.value = s;
    if (!readOnly) load();
  }

  Future<void> load() async {
    error.value = null;
    needsInternet.value = false;
    loading.value = true;
    final sid = await supplyStoreId(_storeIdOverride);
    final PoList? r = supplyOnline() ? await _repo.getSupplyOrders(sid, status: status.value, supplierId: supplierId) : null;
    if (r != null) {
      orders.assignAll(r.orders);
      cur.value = r.cur;
      asOf.value = null;
      if (status.value == 'all' && supplierId == null) await _cache.save(sid, r);
    } else if (!supplyOnline() || _repo.lastErrorCode == null) {
      // no answer at all: the till is offline. Show the last remembered list, read only.
      final cached = supplierId == null ? await _cache.load(sid) : null;
      if (cached != null) {
        orders.assignAll(cached.orders);
        cur.value = cached.cur;
        asOf.value = cached.asOf;
      } else {
        orders.clear();
        asOf.value = null;
        needsInternet.value = true;
      }
    } else {
      orders.clear();
      asOf.value = null;
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the purchase orders. Try again.');
    }
    loading.value = false;
  }
}
