import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';

typedef InvApprovalRequester = Future<String?> Function({required String reason, PosRepository? repository});

/// Manual stock change of one item. A cashier may change a little; above the store's limit the SERVER answers `POS_APPROVAL_REQUIRED` and
/// this asks a manager's PIN (the existing [ManagerApproval] sheet) and sends the SAME change again with the approver token.
/// One request in flight at a time (double-tap safe, the approval sheet included).
class InvAdjustController extends GetxController {
  InvAdjustController({required this.variantId, required this.currentStock, PosRepository? repository, String? storeId, this.locationId, InvApprovalRequester? approval})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _approval = approval ?? ManagerApproval.request;
  final String variantId;
  final int currentStock;
  final String? locationId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final InvApprovalRequester _approval;

  static const reasons = <(String, String)>[('restocked', 'Restocked'), ('damaged', 'Damaged'), ('correction', 'Correction'), ('other', 'Other')];

  final RxInt delta = 0.obs;
  final RxnString reason = RxnString();
  final RxString note = ''.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString result = RxnString();

  bool get noteRequired => reason.value == 'other';
  bool get canSubmit => delta.value != 0 && reason.value != null && !busy.value;

  /// What the change will do, in words ("Marked damaged" moves units to the damaged pool and leaves on-hand stock alone).
  String get preview {
    final d = delta.value;
    if (d == 0) return '';
    if (reason.value == 'damaged') return 'Marked damaged: ${d.abs()} unit${d.abs() == 1 ? '' : 's'} move to the damaged pool.';
    return 'Stock goes from $currentStock to ${currentStock + d}.';
  }

  void setDelta(int v) => delta.value = v;
  void step(int by) => delta.value += by;
  void pickReason(String r) => reason.value = r;

  Future<bool> submit() async {
    if (!canSubmit) return false;
    busy.value = true;
    error.value = null;
    try {
      final sid = await invStoreId(_storeIdOverride);
      final d = delta.value, r = reason.value!, n = note.value;
      var res = await _repo.adjustInventory(sid, variantId, delta: d, reason: r, note: n, locationId: locationId);
      if (!res.success && res.code == 'POS_APPROVAL_REQUIRED') {
        final token = await _approval(reason: 'This stock change needs a manager\'s approval.', repository: _repo);
        if (token == null) {
          error.value = invErrorMessage('POS_APPROVAL_REQUIRED');
          return false;
        }
        res = await _repo.adjustInventory(sid, variantId, delta: d, reason: r, note: n, locationId: locationId, approverToken: token);
      }
      if (!res.success) {
        error.value = invErrorMessage(res.code, fallback: res.message);
        return false;
      }
      result.value = r == 'damaged' ? 'Marked damaged' : 'Stock updated';
      return true;
    } finally {
      busy.value = false;
    }
  }
}
