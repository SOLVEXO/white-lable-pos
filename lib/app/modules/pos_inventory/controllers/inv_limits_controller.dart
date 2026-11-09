import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Approval limits, read-only (editing is owner-only and not part of the till).
class InvLimitsController extends GetxController {
  InvLimitsController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxList<InvLimit> limits = <InvLimit>[].obs;
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      final r = await _repo.getInventoryLimits(await invStoreId(_storeIdOverride));
      if (r == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the limits. Check the connection and try again.');
      } else {
        cur.value = r.cur;
        limits.assignAll(r.limits);
      }
    } finally {
      loading.value = false;
    }
  }
}
