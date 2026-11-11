import 'dart:io';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';

/// What a cash in / out ended as.
enum CashOutcome { booked, queued }

/// A cash in / out on the OPEN shift, always with a category (and a note for "other"). The amount is typed in the currency's own units and sent as integer
/// minor units at the exponent of the currency the server stated (remembered from the last answer, so it also works offline). Works OFFLINE: the request
/// is queued with its request id and the device time and replays exactly once when the till reconnects. Above the store's limit the server asks for a
/// manager's PIN (POS_APPROVAL_REQUIRED): the same approval sheet is asked and the SAME request is sent again with the approver token.
class CashMovementController extends GetxController {
  CashMovementController({
    String initialType = 'cash_in',
    PosRepository? repository,
    CashConfigCache? cache,
    PendingCashSyncService? queue,
    String? storeId,
    Future<String?> Function()? sessionIdProvider,
    Future<String?> Function()? employeeTokenProvider,
    CashApprovalRequester? approval,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  }) : type = initialType.obs,
       _repo = repository ?? PosRepository(),
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

  /// the offline queue (null on a till without one): the sheet shows how many movements of this shift are waiting to sync
  PendingCashSyncService? get queue => _queue;

  final RxString type;
  final RxnString category = RxnString();
  final RxString amountText = ''.obs;
  final RxString note = ''.obs;
  final Rx<CashConfig> config = const CashConfig().obs;
  final RxBool loadingConfig = true.obs;
  final RxnString sessionId = RxnString();
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final Rxn<CashOutcome> outcome = Rxn<CashOutcome>();

  /// G5.1: an optional photo of the slip — uploaded right after an ONLINE booking (an offline movement queues without it)
  final Rxn<File> photo = Rxn<File>();
  final RxnString photoNotice = RxnString();
  void setPhoto(File? f) => photo.value = f;

  String? _requestId, _fingerprint;
  DateTime? _occurredAt;
  bool _started = false;

  InvCur? get cur => config.value.cur;
  bool get isIn => type.value == 'cash_in';
  List<String> get categories => isIn ? config.value.cashInCategories : config.value.cashOutCategories;
  bool get noteRequired => category.value != null && config.value.noteRequired(category.value!);
  bool get hasOpenShift => (sessionId.value ?? '').isNotEmpty;

  /// The typed amount as minor units at the stated exponent (null when it is not valid or the currency is not known yet).
  int? get amountMinor => cur == null ? null : cashMinorFromText(amountText.value, cur!.exponent);

  bool get canSubmit => category.value != null && amountMinor != null && (!noteRequired || note.value.trim().isNotEmpty) && hasOpenShift && !busy.value;

  @override
  void onInit() {
    super.onInit();
    start();
  }

  /// Loads the categories / currency (server, else the remembered copy) and the open shift. Safe to call twice.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    sessionId.value = await _sessionId();
    final sid = await cashStoreId(_storeIdOverride);
    CashConfig? c;
    if (cashOnline()) {
      c = await _repo.getCashConfig(sid);
      if (c != null) await _cache.save(sid, c);
    }
    c ??= await _cache.load(sid);
    if (c != null) config.value = c;
    loadingConfig.value = false;
  }

  void setType(String t) {
    if (type.value == t) return;
    type.value = t;
    category.value = null;
  }

  void pickCategory(String c) => category.value = c;

  Future<bool> submit() async {
    if (busy.value) return false;
    error.value = null;
    final minor = amountMinor;
    if (!hasOpenShift) {
      error.value = cashErrorMessage('NO_OPEN_SHIFT');
      return false;
    }
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
    final body = {'type': type.value, 'category': category.value, 'amountMinor': minor, 'note': note.value.trim(), 'sessionId': sessionId.value};
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
      Future<({bool success, String? message, String? code, bool retryable, CashMovementResult? result})> send([String? token]) => _repo.recordCashMovement(
        sid,
        type: type.value,
        category: category.value!,
        amountMinor: minor,
        sessionId: sessionId.value!,
        requestId: _requestId!,
        note: note.value,
        occurredAt: _occurredAt,
        approverToken: token,
      );
      var r = await send();
      if (!r.success && r.code == 'POS_APPROVAL_REQUIRED') {
        final token = await _approval(reason: 'This ${isIn ? 'cash in' : 'cash out'} needs a manager\'s approval.', repository: _repo);
        if (token == null) {
          error.value = cashErrorMessage('POS_APPROVAL_REQUIRED');
          return false;
        }
        r = await send(token);
      }
      if (r.success) {
        outcome.value = CashOutcome.booked;
        final f = photo.value;
        if (f != null) {
          final up = await _repo.uploadCashMovementReceipt(sid, _requestId!, f);
          photoNotice.value = up.success ? null : 'The cash movement is recorded, but the photo could not be uploaded: ${cashErrorMessage(up.code, fallback: up.message)}';
        }
        _reset();
        return true;
      }
      if (r.retryable && _queue != null) {
        // no answer / timeout / 5xx: the outcome is unknown, so queue it under the SAME request id; the server books it only once
        return await _queueIt(sid, minor);
      }
      error.value = cashErrorMessage(r.code, fallback: r.message);
      return false;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> _queueIt(String storeId, int minor) async {
    final q = _queue;
    if (q == null) {
      error.value = 'Needs internet.';
      return false;
    }
    await q.enqueueMovement(
      storeId: storeId,
      requestId: _requestId!,
      type: type.value,
      category: category.value!,
      amountMinor: minor,
      sessionId: sessionId.value!,
      currency: cur!.code,
      currencyExponent: cur!.exponent,
      note: note.value,
      occurredAt: _occurredAt,
      employeeToken: await _employeeToken(),
    );
    outcome.value = CashOutcome.queued;
    if (photo.value != null) photoNotice.value = 'Saved on this device. The photo was not kept — a photo can only be attached online.';
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
