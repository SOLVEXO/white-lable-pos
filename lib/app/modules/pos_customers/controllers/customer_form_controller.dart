import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';

/// Add or edit a customer. Only the name is required; phone, e-mail, address, NTN, CNIC, registration type, group, notes and marketing
/// consent are all optional (nothing here ever blocks on a tax id). The server validates and answers with a code; this maps it to the
/// field it belongs to. Creating needs the internet (never queued); a second submit while one is running does nothing.
class CustomerFormController extends GetxController {
  CustomerFormController({this.existing, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId {
    final e = existing;
    if (e != null) {
      name.value = e.name;
      phone.value = e.phone ?? '';
      email.value = e.email ?? '';
      address.value = e.address ?? '';
      ntn.value = e.ntn ?? '';
      cnic.value = e.cnic ?? '';
      group.value = e.group ?? '';
      notes.value = e.notes ?? '';
      registrationType.value = e.registrationType;
      marketingConsent.value = e.marketingConsent;
    }
  }
  final PosCustomer? existing;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxString name = ''.obs, phone = ''.obs, email = ''.obs, address = ''.obs, ntn = ''.obs, cnic = ''.obs, group = ''.obs, notes = ''.obs;
  final RxnString registrationType = RxnString();
  final RxBool marketingConsent = false.obs;
  final RxBool busy = false.obs;

  /// error text per field key (`name`, `phone`, `email`, `ntn`, `cnic`, `registrationType`)
  final RxMap<String, String> fieldErrors = <String, String>{}.obs;
  final RxnString error = RxnString();

  bool get isEdit => existing != null;
  bool get canSubmit => name.value.trim().isNotEmpty && !busy.value;

  static const _fieldOfCode = {
    'NAME_REQUIRED': 'name',
    'PHONE_INVALID': 'phone',
    'PHONE_IN_USE': 'phone',
    'EMAIL_INVALID': 'email',
    'NTN_INVALID': 'ntn',
    'CNIC_INVALID': 'cnic',
    'REGISTRATION_TYPE_INVALID': 'registrationType',
  };

  void setRegistrationType(String? v) => registrationType.value = registrationType.value == v ? null : v;

  Map<String, dynamic> _fields() => {
    'name': name.value.trim(),
    'phone': phone.value.trim(),
    'email': email.value.trim(),
    'address': address.value.trim(),
    'ntn': ntn.value.trim(),
    'cnic': cnic.value.trim(),
    'group': group.value.trim(),
    'notes': notes.value.trim(),
    'marketingConsent': marketingConsent.value,
    'registrationType': registrationType.value,
  };

  /// A new customer sends only what was filled in; an edit sends the fields that changed (an emptied one clears it on the server).
  Map<String, dynamic> _payload() {
    final all = _fields();
    final e = existing;
    if (e == null) {
      return {
        for (final f in all.entries)
          if (f.key == 'name' || (f.value is String ? (f.value as String).isNotEmpty : f.value != null && f.value != false)) f.key: f.value,
      };
    }
    final before = <String, dynamic>{
      'name': e.name,
      'phone': e.phone ?? '',
      'email': e.email ?? '',
      'address': e.address ?? '',
      'ntn': e.ntn ?? '',
      'cnic': e.cnic ?? '',
      'group': e.group ?? '',
      'notes': e.notes ?? '',
      'marketingConsent': e.marketingConsent,
      'registrationType': e.registrationType,
    };
    return {
      for (final f in all.entries)
        if (f.value != before[f.key] && !(f.key == 'registrationType' && f.value == null)) f.key: f.value,
    };
  }

  /// The saved customer, or null when it was refused (see [error] / [fieldErrors]). `existing: true` on the result means the phone number
  /// already belonged to that customer, so nothing new was created.
  Future<PosCustomer?> submit() async {
    if (busy.value) return null;
    fieldErrors.clear();
    error.value = null;
    if (name.value.trim().isEmpty) {
      fieldErrors['name'] = customerErrorMessage('NAME_REQUIRED');
      return null;
    }
    if (!customersOnline()) {
      error.value = 'Needs internet. Customers can only be saved while the till is online.';
      return null;
    }
    busy.value = true;
    try {
      final sid = await customerStoreId(_storeIdOverride);
      final payload = _payload();
      final r = isEdit ? await _repo.updatePosCustomer(sid, existing!.id, payload) : await _repo.createPosCustomer(sid, payload);
      if (r.success && r.customer != null) return r.customer;
      final code = r.code ?? _repo.lastErrorCode;
      final msg = customerErrorMessage(code, fallback: r.message ?? 'Could not save the customer. Try again.');
      final field = _fieldOfCode[code];
      if (field != null) {
        fieldErrors[field] = msg;
      } else {
        error.value = msg;
      }
      return null;
    } finally {
      busy.value = false;
    }
  }
}
