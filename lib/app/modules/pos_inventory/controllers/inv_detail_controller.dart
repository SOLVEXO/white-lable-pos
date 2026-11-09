import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

/// One item: stock, committed / damaged, locations, lots with expiry, the last movements (managers) and the Adjust action.
class InvDetailController extends GetxController {
  InvDetailController({required this.variantId, PosRepository? repository, String? storeId, String? role}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId, _roleOverride = role;
  final String variantId;
  final PosRepository _repo;
  final String? _storeIdOverride, _roleOverride;

  final Rxn<InvDetail> detail = Rxn<InvDetail>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxString role = InvRole.cashier.obs;
  String storeId = '';

  bool get canManage => InvRole.canManage(role.value);

  @override
  void onInit() {
    super.onInit();
    if (_roleOverride != null) {
      role.value = _roleOverride;
    } else {
      invGuessRole().then((r) => role.value = r);
    }
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      storeId = await invStoreId(_storeIdOverride);
      final d = await _repo.getInventoryVariant(storeId, variantId);
      if (d == null) {
        error.value = invErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this item. Check the connection and try again.');
      } else {
        detail.value = d;
      }
    } finally {
      loading.value = false;
    }
  }
}
