import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Stock list: debounced search, All / Low / Out filter, infinite scroll. [lowOnly] is the "Low stock" screen — the same list, pre-filtered.
class InvStockListController extends GetxController {
  InvStockListController({PosRepository? repository, String? storeId, this.lowOnly = false, this.initialFilter = 'all', this.pageSize = 30, this.debounce = const Duration(milliseconds: 350), Future<List<StoreLocationModel>> Function(String storeId)? locations})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _locations = locations;
  final PosRepository _repo;
  final Future<List<StoreLocationModel>> Function(String storeId)? _locations;

  /// G5.1: the store's locations (the location filter is shown only when there are some) and the one picked (null = all locations)
  final RxList<StoreLocationModel> locations = <StoreLocationModel>[].obs;
  final RxnString locationId = RxnString();
  void setLocation(String? id) {
    if (locationId.value == id) return;
    locationId.value = id;
    reload();
  }
  Future<void> _loadLocations() async {
    try {
      final sid = await invStoreId(_storeIdOverride);
      final all = _locations != null ? await _locations(sid) : (await _repo.getStoreLocations(sid) ?? const <StoreLocationModel>[]);
      locations.assignAll(all.where((l) => l.status != 'inactive'));
    } catch (_) {/* the filter is a convenience; the list works without it */}
  }
  final String? _storeIdOverride;
  final bool lowOnly;
  /// the chip selected when the screen opens (the Home "Expiring soon" row opens it on `expiring`)
  final String initialFilter;
  final int pageSize;
  final Duration debounce;

  final RxList<InvRow> items = <InvRow>[].obs;
  /// the currency of the last page, as the server stated it (null = it did not: money is then not shown)
  final Rxn<InvCur> cur = Rxn<InvCur>();

  /// G4.8: the owner hides costs from this manager
  final RxBool costsHidden = false.obs;
  final RxBool loading = true.obs;
  final RxBool loadingMore = false.obs;
  final RxnString error = RxnString();
  final RxString filter = 'all'.obs;
  final RxBool hasMore = false.obs;
  final RxInt total = 0.obs;
  String query = '';
  int _page = 1;
  int _ticket = 0; // a slow answer to an older search must never overwrite a newer one
  Timer? _timer;
  String storeId = '';

  @override
  void onInit() {
    super.onInit();
    filter.value = lowOnly ? 'low' : initialFilter;
    reload();
    if (!lowOnly) _loadLocations();
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void onQueryChanged(String q) {
    _timer?.cancel();
    _timer = Timer(debounce, () {
      query = q.trim();
      reload();
    });
  }

  void setFilter(String f) {
    if (lowOnly || filter.value == f) return;
    filter.value = f;
    reload();
  }

  Future<void> reload() async {
    final ticket = ++_ticket;
    loading.value = true;
    error.value = null;
    _page = 1;
    storeId = await invStoreId(_storeIdOverride);
    final r = await _repo.getInventoryStock(storeId, search: query, filter: filter.value, page: 1, limit: pageSize, locationId: locationId.value);
    if (ticket != _ticket) return;
    if (r == null) {
      items.clear();
      hasMore.value = false;
      error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the stock. Check the connection and try again.');
    } else {
      items.assignAll(r.items);
      cur.value = r.cur;
      costsHidden.value = r.costsHidden;
      total.value = r.total;
      hasMore.value = r.hasMore;
    }
    loading.value = false;
  }

  Future<void> loadMore() async {
    if (loading.value || loadingMore.value || !hasMore.value) return;
    final ticket = _ticket;
    loadingMore.value = true;
    try {
      final r = await _repo.getInventoryStock(storeId, search: query, filter: filter.value, page: _page + 1, limit: pageSize, locationId: locationId.value);
      if (ticket != _ticket || r == null) return;
      _page = r.page;
      items.addAll(r.items);
      cur.value = r.cur ?? cur.value;
      total.value = r.total;
      hasMore.value = r.hasMore;
    } finally {
      loadingMore.value = false;
    }
  }
}
