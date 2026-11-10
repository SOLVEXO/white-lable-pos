import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// What the store owes its suppliers (managers / owners): the total and, per supplier, the balance with its aging.
class PayablesController extends GetxController {
  PayablesController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<Payables> payables = Rxn<Payables>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  Worker? _online;

  InvCur? get cur => payables.value?.cur;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(supplyOnlineRx(), (on) {
      if (on && payables.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load() async {
    error.value = null;
    if (!supplyOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final p = await _repo.getPayables(await supplyStoreId(_storeIdOverride));
    if (p == null) {
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the payables. Try again.');
    } else {
      payables.value = p;
    }
    loading.value = false;
  }
}
