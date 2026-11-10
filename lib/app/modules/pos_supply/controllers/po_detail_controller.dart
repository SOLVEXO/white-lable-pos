import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// One purchase order: lines (ordered / received / damaged / remaining), status and the actions of that status. The buttons only follow
/// the order's status; WHO may press them is the server's decision (approving above the store's limit needs the owner, and the server's
/// answer is shown in plain words). A manager's PIN approval is asked for when the server answers `POS_APPROVAL_REQUIRED`.
class PoDetailController extends GetxController {
  PoDetailController({required this.orderId, PosRepository? repository, String? storeId, SupplyApprovalRequester? approval})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _approval = approval ?? ManagerApproval.request;
  final String orderId;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final SupplyApprovalRequester _approval;

  final Rxn<PoDetail> detail = Rxn<PoDetail>();
  final RxBool loading = true.obs;
  final RxBool busy = RxBool(false);
  final RxnString error = RxnString();
  final RxnString actionError = RxnString();
  final RxnString notice = RxnString();
  final RxBool canManageHint = false.obs;
  Worker? _online;

  PurchaseOrder? get order => detail.value?.order;

  /// manager / owner: by role, or because the server sent costs (it only does for them)
  bool get canManage => canManageHint.value || (order?.hasCosts ?? false);
  bool get canApprove => canManage && order?.status == PoStatus.draft;
  bool get canSend => canManage && order?.status == PoStatus.approved;
  bool get canEdit => canManage && (order?.editable ?? false) && !(order?.items.any((i) => i.received + i.damaged > 0) ?? false);
  bool get canCancel => canEdit;
  bool get canCloseShort => canManage && order?.status == PoStatus.partiallyReceived;
  bool get canReceive => order?.receivable ?? false;

  @override
  void onInit() {
    super.onInit();
    supplyGuessCanManage().then((v) => canManageHint.value = v);
    load();
    _online = ever<bool>(supplyOnlineRx(), (on) {
      if (on && detail.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> load({bool silent = false}) async {
    error.value = null;
    if (!supplyOnline()) {
      loading.value = false;
      return;
    }
    if (!silent) loading.value = true;
    final d = await _repo.getSupplyOrder(await supplyStoreId(_storeIdOverride), orderId);
    if (d == null) {
      if (detail.value == null) error.value = supplyErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this purchase order. Try again.');
    } else {
      detail.value = d;
    }
    loading.value = false;
  }

  /// [action]: approve | send | cancel | close-short.
  Future<bool> run(String action) async {
    if (busy.value) return false;
    busy.value = true;
    actionError.value = null;
    notice.value = null;
    try {
      if (!supplyOnline()) {
        actionError.value = 'Needs internet.';
        return false;
      }
      final sid = await supplyStoreId(_storeIdOverride);
      var r = await _repo.supplyOrderAction(sid, orderId, action);
      if (!r.success && r.code == 'POS_APPROVAL_REQUIRED') {
        final token = await _approval(reason: 'This purchase order needs a manager\'s approval.', repository: _repo);
        if (token == null) {
          actionError.value = supplyErrorMessage('POS_APPROVAL_REQUIRED');
          return false;
        }
        r = await _repo.supplyOrderAction(sid, orderId, action, approverToken: token);
      }
      if (!r.success) {
        actionError.value = supplyErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return false;
      }
      notice.value = switch (action) {
        'approve' => 'Purchase order approved.',
        'send' => 'Purchase order marked as sent.',
        'cancel' => 'Purchase order cancelled.',
        _ => 'Purchase order closed short.',
      };
      final o = r.order;
      final d = detail.value;
      if (o != null && d != null) {
        detail.value = PoDetail(order: o, receipts: d.receipts, cur: d.cur);
      } else {
        await load(silent: true);
      }
      return true;
    } finally {
      busy.value = false;
    }
  }
}
