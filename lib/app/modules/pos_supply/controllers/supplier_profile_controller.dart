import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// One supplier: NTN / STRN, payment terms, aging buckets (current / 30 / 60 / 90+), recent purchase orders and receipts.
class SupplierProfileController extends GetxController {
  SupplierProfileController({required this.supplierId, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String supplierId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final Rxn<SupplierProfile> profile = Rxn<SupplierProfile>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  Worker? _online;

  @override
  void onInit() {
    super.onInit();
    load();
    _online = ever<bool>(supplyOnlineRx(), (on) {
      if (on && profile.value == null) load();
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
    final p = await _repo.getSupplier(await supplyStoreId(_storeIdOverride), supplierId);
    if (p == null) {
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this supplier. Try again.');
    } else {
      profile.value = p;
    }
    loading.value = false;
  }

  void applyEdit(Supplier s) {
    final p = profile.value;
    if (p == null) return;
    profile.value = SupplierProfile(supplier: s, aging: p.aging, orders: p.orders, receipts: p.receipts, cur: p.cur);
  }
}
