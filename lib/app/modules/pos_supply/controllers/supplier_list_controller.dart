import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// Suppliers (managers / owners): name, contact, what is owed and open orders. Online only: offline the screen says "Needs internet".
class SupplierListController extends GetxController {
  SupplierListController({PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxList<Supplier> items = <Supplier>[].obs;
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxString query = ''.obs;
  Worker? _online;

  List<Supplier> get visible {
    final q = query.value.trim().toLowerCase();
    return q.isEmpty ? items : items.where((s) => '${s.name} ${s.contactName ?? ''} ${s.phone ?? ''}'.toLowerCase().contains(q)).toList();
  }

  @override
  void onInit() {
    super.onInit();
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

  Future<void> load() async {
    error.value = null;
    if (!supplyOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final r = await _repo.getSuppliers(await supplyStoreId(_storeIdOverride));
    if (r == null) {
      items.clear();
      error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the suppliers. Try again.');
    } else {
      items.assignAll(r.suppliers);
      cur.value = r.cur;
    }
    loading.value = false;
  }

  void upsert(Supplier s) {
    final i = items.indexWhere((e) => e.id == s.id);
    if (i >= 0) {
      final old = items[i];
      items[i] = Supplier(
        id: s.id,
        name: s.name,
        contactName: s.contactName,
        phone: s.phone,
        email: s.email,
        address: s.address,
        ntn: s.ntn,
        strn: s.strn,
        paymentTerms: s.paymentTerms,
        leadTimeDays: s.leadTimeDays,
        notes: s.notes,
        status: s.status,
        balanceMinor: old.balanceMinor,
        openOrders: old.openOrders,
      );
    } else {
      items.insert(0, s);
    }
  }
}
