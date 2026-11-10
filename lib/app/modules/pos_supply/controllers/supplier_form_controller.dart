import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// Add or edit a supplier. Only the name is required. The server decides who may save (`POS_ACTION_FORBIDDEN` for a cashier).
class SupplierFormController extends GetxController {
  SupplierFormController({this.existing, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId {
    final s = existing;
    if (s != null) {
      name.value = s.name;
      contactName.value = s.contactName ?? '';
      phone.value = s.phone ?? '';
      email.value = s.email ?? '';
      address.value = s.address ?? '';
      ntn.value = s.ntn ?? '';
      strn.value = s.strn ?? '';
      paymentTerms.value = s.paymentTerms ?? '';
      leadTimeDays.value = s.leadTimeDays?.toString() ?? '';
      notes.value = s.notes ?? '';
    }
  }
  final Supplier? existing;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final name = ''.obs, contactName = ''.obs, phone = ''.obs, email = ''.obs, address = ''.obs, ntn = ''.obs, strn = ''.obs, paymentTerms = ''.obs, leadTimeDays = ''.obs, notes = ''.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();

  bool get isEdit => existing != null;
  bool get canSubmit => name.value.trim().isNotEmpty && !busy.value;

  /// What is sent. On an edit an emptied field is sent empty (the server clears it); on a new supplier empty fields are left out.
  Map<String, dynamic> get fields {
    final all = <String, String>{
      'name': name.value,
      'contactName': contactName.value,
      'phone': phone.value,
      'email': email.value,
      'address': address.value,
      'ntn': ntn.value,
      'strn': strn.value,
      'paymentTerms': paymentTerms.value,
      'notes': notes.value,
    };
    final out = <String, dynamic>{
      for (final e in all.entries)
        if (isEdit || e.value.trim().isNotEmpty) e.key: e.value.trim(),
    };
    final lead = int.tryParse(leadTimeDays.value.trim());
    if (lead != null) {
      out['leadTimeDays'] = lead;
    } else if (isEdit && existing?.leadTimeDays != null) {
      out['leadTimeDays'] = null;
    }
    return out;
  }

  Future<Supplier?> submit() async {
    if (busy.value) return null;
    error.value = null;
    if (name.value.trim().isEmpty) {
      error.value = supplyErrorMessage('NAME_REQUIRED');
      return null;
    }
    if (!supplyOnline()) {
      error.value = 'Needs internet.';
      return null;
    }
    busy.value = true;
    try {
      final sid = await supplyStoreId(_storeIdOverride);
      final r = isEdit ? await _repo.updateSupplier(sid, existing!.id, fields) : await _repo.createSupplier(sid, fields);
      if (!r.success || r.supplier == null) {
        error.value = supplyErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return null;
      }
      return r.supplier;
    } finally {
      busy.value = false;
    }
  }
}
