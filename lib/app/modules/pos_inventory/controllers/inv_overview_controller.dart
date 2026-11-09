import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// Inventory overview: counts, stock value (managers only — the server leaves it out for a cashier), the open stock count.
class InvOverviewController extends GetxController {
  InvOverviewController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<InvOverview> overview = Rxn<InvOverview>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxString roleHint = InvRole.cashier.obs;
  String storeId = '';

  /// What the server said, else the best guess until it answers.
  String get role => overview.value?.role ?? roleHint.value;
  bool get canManage => InvRole.canManage(role);

  @override
  void onInit() {
    super.onInit();
    invGuessRole().then((r) => roleHint.value = r);
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      storeId = await invStoreId(_storeIdOverride);
      final o = await _repo.getInventoryOverview(storeId);
      if (o == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the inventory. Check the connection and try again.');
      } else {
        overview.value = o;
      }
    } finally {
      loading.value = false;
    }
  }
}
