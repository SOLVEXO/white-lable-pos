import 'dart:convert';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Paying a supplier (managers / owners). The amount is typed in the currency's own units and sent as integer minor units at the exponent
/// of the currency the server stated. Cash is paid from the OPEN shift's drawer, so it needs the open shift's session id (the same one the
/// cash in / out screen uses): with no open shift cash is disabled and the sheet says "Open a shift to pay cash". Bank and other are only
/// recorded. One `requestId` per attempt (a retry of the same payment sends the same id, so it can never pay twice). The server decides about
/// limits: above the manager's limit it asks for the owner, and says so in plain words.
class PaySupplierController extends GetxController {
  PaySupplierController({
    required this.supplierId,
    required this.exponent,
    this.balanceMinor,
    PosRepository? repository,
    String? storeId,
    Future<String?> Function()? sessionIdProvider,
    SupplyApprovalRequester? approval,
    String Function()? requestIdFactory,
  }) : _repo = repository ?? PosRepository(),
       _storeIdOverride = storeId,
       _sessionId = sessionIdProvider ?? AppPreferences.getPosSessionId,
       _approval = approval,
       _newId = requestIdFactory ?? newSupplyRequestId;
  final String supplierId;

  /// the exponent of the currency the balance is stated in (from the response)
  final int exponent;
  final int? balanceMinor;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final Future<String?> Function() _sessionId;
  final SupplyApprovalRequester? _approval;
  final String Function() _newId;

  final RxString amountText = ''.obs;
  final RxString method = 'bank'.obs;
  final RxString reference = ''.obs;
  final RxnString sessionId = RxnString();
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final Rxn<SupplierPaymentResult> result = Rxn<SupplierPaymentResult>();
  String? _requestId, _fingerprint;

  bool get canPayCash => (sessionId.value ?? '').isNotEmpty;
  int? get amountMinor => supplyMinorFromText(amountText.value, exponent);
  bool get canSubmit => amountMinor != null && !busy.value && (method.value != 'cash' || canPayCash);

  @override
  void onInit() {
    super.onInit();
    _sessionId().then((s) {
      sessionId.value = s;
      if (canPayCash) method.value = 'cash';
    });
  }

  void pickMethod(String m) => method.value = m;

  /// "Pay the full balance": fills the amount from what is owed.
  String? get fullBalanceText => balanceMinor != null && balanceMinor! > 0 ? supplyMinorToText(balanceMinor!, exponent) : null;

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    final minor = amountMinor;
    if (minor == null) {
      error.value = supplyErrorMessage('INVALID_AMOUNT');
      return false;
    }
    if (method.value == 'cash' && !canPayCash) {
      error.value = supplyErrorMessage('NO_OPEN_SHIFT');
      return false;
    }
    if (!supplyOnline()) {
      error.value = 'Needs internet.';
      return false;
    }
    final body = {'amountMinor': minor, 'method': method.value, 'reference': reference.value.trim(), 'sessionId': method.value == 'cash' ? sessionId.value : null};
    final fp = jsonEncode(body);
    if (_requestId == null || _fingerprint != fp) {
      _requestId = _newId();
      _fingerprint = fp;
    }
    busy.value = true;
    try {
      final sid = await supplyStoreId(_storeIdOverride);
      Future<({bool success, String? message, String? code, SupplierPaymentResult? result})> send([String? token]) =>
          _repo.paySupplier(sid, supplierId, amountMinor: minor, method: method.value, requestId: _requestId!, reference: reference.value, sessionId: sessionId.value, approverToken: token);
      var r = await send();
      if (!r.success && r.code == 'POS_APPROVAL_REQUIRED') {
        final token = await (_approval ?? ManagerApproval.request)(reason: 'This payment needs a manager\'s approval.', repository: _repo);
        if (token == null) {
          error.value = supplyErrorMessage('POS_APPROVAL_REQUIRED');
          return false;
        }
        r = await send(token);
      }
      if (!r.success || r.result == null) {
        error.value = supplyErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return false;
      }
      result.value = r.result;
      _requestId = null;
      _fingerprint = null;
      return true;
    } finally {
      busy.value = false;
    }
  }
}
