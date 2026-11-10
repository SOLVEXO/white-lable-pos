import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// One supplier's ledger (managers / owners): every bill, payment and credit, newest first, each with the running balance.
class SupplierLedgerController extends GetxController {
  SupplierLedgerController({required this.supplierId, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String supplierId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<SupplierLedger> ledger = Rxn<SupplierLedger>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  Worker? _online;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(supplyOnlineRx(), (on) {
      if (on && ledger.value == null) load();
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
    final l = await _repo.getSupplierLedger(await supplyStoreId(_storeIdOverride), supplierId);
    if (l == null) {
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the ledger. Try again.');
    } else {
      ledger.value = l;
    }
    loading.value = false;
  }
}
