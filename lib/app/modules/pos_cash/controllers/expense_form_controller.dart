import 'dart:convert';
import 'dart:io';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';

/// Adding an expense: category, amount, payee, how it was paid (cash from the drawer / bank / other), a note ("other" needs one) and an optional receipt
/// photo. A DRAWER expense works offline (queued with its request id and device time; its photo uploads after reconnect, then the local copy is deleted);
/// bank / other expenses are online only. The amount is typed in the currency's own units and sent as integer minor units at the stated exponent. One
/// request id per expense: a retry sends the same id, so the server records it once. Above the limit the server asks for a manager's PIN.
class ExpenseFormController extends GetxController {
  ExpenseFormController({
    PosRepository? repository,
    CashConfigCache? cache,
    PendingCashSyncService? queue,
    String? storeId,
    Future<String?> Function()? sessionIdProvider,
    Future<String?> Function()? employeeTokenProvider,
    CashApprovalRequester? approval,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  }) : _repo = repository ?? PosRepository(),
       _cache = cache ?? CashConfigCache.instance,
       _queueOverride = queue,
       _storeIdOverride = storeId,
       _sessionId = sessionIdProvider ?? cashOpenSessionId,
       _employeeToken = employeeTokenProvider ?? cashEmployeeToken,
       _approval = approval ?? ManagerApproval.request,
       _newId = requestIdFactory ?? newCashRequestId,
       _clock = clock ?? DateTime.now;

  final PosRepository _repo;
  final CashConfigCache _cache;
  final PendingCashSyncService? _queueOverride;
  final String? _storeIdOverride;
  final Future<String?> Function() _sessionId, _employeeToken;
  final CashApprovalRequester _approval;
  final String Function() _newId;
  final DateTime Function() _clock;
  PendingCashSyncService? get _queue => _queueOverride ?? cashQueue();

  final Rx<CashConfig> config = const CashConfig().obs;
  final RxBool loadingConfig = true.obs;
  final RxnString sessionId = RxnString();
  final RxnString category = RxnString();
  final RxString method = 'cash'.obs;
  final RxString amountText = ''.obs;
  final RxString payee = ''.obs;
  final RxString note = ''.obs;
  final Rxn<File> photo = Rxn<File>();
  final RxBool busy = false.obs;
  final RxnString error = RxnString();

  /// set after saving: the new expense (null when it was only queued) and what happened to the photo
  final Rxn<CashOutcome> outcome = Rxn<CashOutcome>();
  final Rxn<Expense> saved = Rxn<Expense>();
  final RxnString photoNotice = RxnString();

  String? _requestId, _fingerprint;
  DateTime? _occurredAt;
  bool _started = false;

  InvCur? get cur => config.value.cur;
  bool get hasOpenShift => (sessionId.value ?? '').isNotEmpty;
  bool get noteRequired => category.value == 'other';
  int? get amountMinor => cur == null ? null : cashMinorFromText(amountText.value, cur!.exponent);

  /// Offline only a drawer expense can be made (it is queued); bank / other need the server.
  bool methodAllowed(String m) => m == 'cash' || cashOnline();

  bool get canSubmit =>
      category.value != null && amountMinor != null && (!noteRequired || note.value.trim().isNotEmpty) && (method.value != 'cash' || hasOpenShift) && methodAllowed(method.value) && !busy.value;

  @override
  void onInit() {
    super.onInit();
    start();
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    sessionId.value = await _sessionId();
    final c = await loadCashConfig(_repo, _cache, await cashStoreId(_storeIdOverride));
    if (c != null) config.value = c;
    if (!hasOpenShift) method.value = 'bank';
    loadingConfig.value = false;
  }

  void pickCategory(String c) => category.value = c;
  void pickMethod(String m) {
    if (methodAllowed(m)) method.value = m;
  }

  void setPhoto(File? f) => photo.value = f;

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    final minor = amountMinor;
    if (category.value == null) {
      error.value = cashErrorMessage('INVALID_CATEGORY');
      return false;
    }
    if (cur == null) {
      error.value = 'The currency is not known yet. Connect once so the till can learn it, then try again.';
      return false;
    }
    if (minor == null) {
      error.value = cashErrorMessage('INVALID_AMOUNT');
      return false;
    }
    if (noteRequired && note.value.trim().isEmpty) {
      error.value = cashErrorMessage('NOTE_REQUIRED');
      return false;
    }
    if (method.value == 'cash' && !hasOpenShift) {
      error.value = cashErrorMessage('NO_OPEN_SHIFT');
      return false;
    }
    if (!methodAllowed(method.value)) {
      error.value = 'Needs internet. Only an expense paid from the drawer can be saved offline.';
      return false;
    }
    final body = {
      'category': category.value,
      'method': method.value,
      'amountMinor': minor,
      'payee': payee.value.trim(),
      'note': note.value.trim(),
      'sessionId': method.value == 'cash' ? sessionId.value : null,
    };
    final fp = jsonEncode(body);
    if (_requestId == null || _fingerprint != fp) {
      _requestId = _newId();
      _fingerprint = fp;
      _occurredAt = _clock();
    }
    busy.value = true;
    try {
      final sid = await cashStoreId(_storeIdOverride);
      if (!cashOnline()) return await _queueIt(sid, minor);
      Future<({bool success, String? message, String? code, bool retryable, ExpenseSaved? result})> send([String? token]) => _repo.recordExpense(
        sid,
        category: category.value!,
        method: method.value,
        amountMinor: minor,
        requestId: _requestId!,
        sessionId: method.value == 'cash' ? sessionId.value : null,
        payee: payee.value,
        note: note.value,
        occurredAt: _occurredAt,
        approverToken: token,
      );
      var r = await send();
      if (!r.success && r.code == 'POS_APPROVAL_REQUIRED') {
        final token = await _approval(reason: 'This expense needs a manager\'s approval.', repository: _repo);
        if (token == null) {
          error.value = cashErrorMessage('POS_APPROVAL_REQUIRED');
          return false;
        }
        r = await send(token);
      }
      if (r.success && r.result != null) {
        saved.value = r.result!.expense;
        outcome.value = CashOutcome.booked;
        await _uploadPhoto(sid, r.result!.expense.id);
        _reset();
        return true;
      }
      if (r.retryable && method.value == 'cash' && _queue != null) return await _queueIt(sid, minor);
      error.value = cashErrorMessage(r.code, fallback: r.message);
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<void> _uploadPhoto(String storeId, String expenseId) async {
    final f = photo.value;
    if (f == null) return;
    final r = await _repo.uploadExpenseReceipt(storeId, expenseId, f);
    if (r.success) {
      photoNotice.value = 'Receipt photo saved.';
    } else if (r.retryable && _queue != null) {
      final path = await _queue!.keepPhoto(f);
      await _queue!.enqueueReceipt(storeId: storeId, path: path, expenseId: expenseId, employeeToken: await _employeeToken());
      _queue!.scheduleSync();
      photoNotice.value = 'The expense is saved. The photo will upload when the till is online.';
    } else {
      photoNotice.value = 'The expense is saved, but the photo could not be uploaded: ${cashErrorMessage(r.code, fallback: r.message)}';
    }
  }

  Future<bool> _queueIt(String storeId, int minor) async {
    final q = _queue;
    if (q == null) {
      error.value = 'Needs internet.';
      return false;
    }
    final token = await _employeeToken();
    await q.enqueueExpense(
      storeId: storeId,
      requestId: _requestId!,
      category: category.value!,
      amountMinor: minor,
      sessionId: sessionId.value!,
      currency: cur!.code,
      currencyExponent: cur!.exponent,
      payee: payee.value,
      note: note.value,
      occurredAt: _occurredAt,
      employeeToken: token,
    );
    final f = photo.value;
    if (f != null) {
      final path = await q.keepPhoto(f);
      await q.enqueueReceipt(storeId: storeId, path: path, expenseRequestId: _requestId, employeeToken: token);
      photoNotice.value = 'The photo will upload after the expense syncs.';
    }
    outcome.value = CashOutcome.queued;
    _reset();
    q.scheduleSync();
    return true;
  }

  void _reset() {
    _requestId = null;
    _fingerprint = null;
    _occurredAt = null;
  }
}
