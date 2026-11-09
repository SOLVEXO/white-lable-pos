import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';

/// Customer directory and the cart's customer picker: debounced search over name / phone / e-mail. When the server cannot be reached the
/// last remembered results are shown, marked "as of <time>" ([asOf] is then set). The newest search always wins over a slower older one.
class CustomerListController extends GetxController {
  CustomerListController({PosRepository? repository, CustomerCache? cache, String? storeId, this.debounce = const Duration(milliseconds: 350)})
    : _repo = repository ?? PosRepository(),
      _cache = cache ?? CustomerCache.instance,
      _storeIdOverride = storeId;
  final PosRepository _repo;
  final CustomerCache _cache;
  final String? _storeIdOverride;
  final Duration debounce;

  final RxList<PosCustomer> items = <PosCustomer>[].obs;

  /// the currency of the balances as the server stated it (null = it did not: no money is shown)
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();

  /// set when the list came from the on-device memory because the server could not be reached
  final Rxn<DateTime> asOf = Rxn<DateTime>();
  final RxBool canManage = false.obs;
  String query = '';
  String storeId = '';
  int _ticket = 0;
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    customerGuessCanManage().then((v) => canManage.value = v);
    search('');
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void onQueryChanged(String q) {
    _timer?.cancel();
    _timer = Timer(debounce, () => search(q));
  }

  Future<void> reload() => search(query);

  Future<void> search(String q) async {
    final ticket = ++_ticket;
    query = q.trim();
    loading.value = true;
    error.value = null;
    storeId = await customerStoreId(_storeIdOverride);
    final page = await _repo.searchPosCustomers(storeId, query);
    if (ticket != _ticket) return; // a newer search is already running
    if (page != null) {
      items.assignAll(page.items);
      cur.value = page.cur;
      asOf.value = null;
      await _cache.saveSearch(storeId, query, page);
    } else if (_repo.lastErrorCode == null) {
      // no answer at all: the till is offline — use what it remembers
      final cached = await _cache.loadSearch(storeId, query);
      if (ticket != _ticket) return;
      if (cached != null) {
        items.assignAll(cached.items);
        cur.value = cached.cur;
        asOf.value = cached.asOf;
      } else {
        items.clear();
        asOf.value = null;
        error.value = 'No internet, and no customers are remembered on this till yet.';
      }
    } else {
      items.clear();
      asOf.value = null;
      error.value = customerErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the customers. Try again.');
    }
    loading.value = false;
  }

  /// A customer was just added or edited: show it at the top without another round trip.
  void upsert(PosCustomer c) {
    items.removeWhere((e) => e.id == c.id);
    items.insert(0, c);
  }
}
