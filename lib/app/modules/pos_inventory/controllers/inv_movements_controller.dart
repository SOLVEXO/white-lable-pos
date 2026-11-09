import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Movement history (managers / owners): type filter chips, infinite list. A cashier is refused by the server (`forbidden`).
class InvMovementsController extends GetxController {
  InvMovementsController({PosRepository? repository, String? storeId, this.variantId, this.pageSize = 30}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final String? variantId;
  final int pageSize;

  static const types = <(String?, String)>[
    (null, 'All'),
    ('sale', 'Sales'),
    ('return', 'Returns'),
    ('void', 'Voids'),
    ('adjustment', 'Adjustments'),
    ('count', 'Counts'),
    ('receive', 'Received'),
    ('write_off', 'Write-offs'),
  ];

  final RxList<InvMovement> items = <InvMovement>[].obs;
  final RxBool loading = true.obs;
  final RxBool loadingMore = false.obs;
  final RxnString error = RxnString();
  final RxBool forbidden = false.obs;
  final RxnString type = RxnString();
  final RxBool hasMore = false.obs;
  int _page = 1;
  int _ticket = 0;
  String storeId = '';

  @override
  void onInit() {
    super.onInit();
    reload();
  }

  void setType(String? t) {
    if (type.value == t) return;
    type.value = t;
    reload();
  }

  Future<void> reload() async {
    final ticket = ++_ticket;
    loading.value = true;
    error.value = null;
    forbidden.value = false;
    _page = 1;
    storeId = await invStoreId(_storeIdOverride);
    final r = await _repo.getInventoryMovements(storeId, variantId: variantId, type: type.value, page: 1, limit: pageSize);
    if (ticket != _ticket) return;
    if (r == null) {
      items.clear();
      hasMore.value = false;
      final code = _repo.lastErrorCode;
      forbidden.value = code == 'POS_ACTION_FORBIDDEN';
      error.value = invErrorMessage(code, fallback: 'Could not load the history. Check the connection and try again.');
    } else {
      items.assignAll(r.items);
      hasMore.value = r.hasMore;
    }
    loading.value = false;
  }

  Future<void> loadMore() async {
    if (loading.value || loadingMore.value || !hasMore.value) return;
    final ticket = _ticket;
    loadingMore.value = true;
    try {
      final r = await _repo.getInventoryMovements(storeId, variantId: variantId, type: type.value, page: _page + 1, limit: pageSize);
      if (ticket != _ticket || r == null) return;
      _page = r.page;
      items.addAll(r.items);
      hasMore.value = r.hasMore;
    } finally {
      loadingMore.value = false;
    }
  }
}
