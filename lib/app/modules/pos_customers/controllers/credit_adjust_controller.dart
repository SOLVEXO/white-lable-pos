import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';

/// A manager adds or removes store credit by hand. The amount is typed in the currency's own units and sent as a signed integer of
/// MINOR units; a note is required. Above the manager's limit the server answers `POS_OWNER_REQUIRED` and the owner must do it.
class CreditAdjustController extends GetxController {
  CreditAdjustController({required this.customerId, required this.exponent, PosRepository? repository, String? storeId}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId;
  final String customerId;

  /// the exponent of the currency the balance is stated in (from the profile response)
  final int exponent;
  final PosRepository _repo;
  final String? _storeIdOverride;

  final RxBool adding = true.obs;
  final RxString amountText = ''.obs;
  final RxString note = ''.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();

  /// The typed amount as integer minor units (null when it is not a positive number with at most [exponent] decimals).
  int? get magnitudeMinor {
    final t = amountText.value.trim().replaceAll(',', '.');
    if (t.isEmpty) return null;
    final m = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(t);
    if (m == null) return null;
    final frac = m.group(2) ?? '';
    if (frac.length > exponent) return null;
    final whole = int.parse(m.group(1)!);
    var p = 1;
    for (var i = 0; i < exponent; i++) {
      p *= 10;
    }
    final minor = whole * p + (frac.isEmpty ? 0 : int.parse(frac.padRight(exponent, '0')));
    return minor > 0 ? minor : null;
  }

  int? get signedMinor => magnitudeMinor == null ? null : (adding.value ? magnitudeMinor : -magnitudeMinor!);
  bool get canSubmit => signedMinor != null && note.value.trim().isNotEmpty && !busy.value;

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    if (signedMinor == null) {
      error.value = customerErrorMessage('AMOUNT_INVALID');
      return false;
    }
    if (note.value.trim().isEmpty) {
      error.value = customerErrorMessage('NOTE_REQUIRED');
      return false;
    }
    if (!customersOnline()) {
      error.value = 'Needs internet.';
      return false;
    }
    busy.value = true;
    try {
      final sid = await customerStoreId(_storeIdOverride);
      final r = await _repo.adjustCustomerCredit(sid, customerId, amountMinor: signedMinor!, note: note.value);
      if (!r.success) {
        error.value = customerErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return false;
      }
      return true;
    } finally {
      busy.value = false;
    }
  }
}
