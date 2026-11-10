import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/clock_controller.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';

/// "Needs attention": every sale that has not (yet) reached the server, why, and what a manager can do about it —
/// plus sales the server RECORDED but flagged (oversold on sync, price changed while offline, payment shortfall).
/// Nothing here is ever dropped silently: a sale leaves the list only by syncing, or by a manager discarding it with
/// a reason that is written to the server's audit log.
class PosNeedsAttentionController extends GetxController {
  PosNeedsAttentionController({PendingSaleSyncService? syncService, PosRepository? posRepository, PosPaymentsRepository? paymentsRepository, PendingCashSyncService? cashQueue, PendingTeamSyncService? teamQueue})
      : _cashOverride = cashQueue,
        _teamOverride = teamQueue,
        _sync = syncService ?? Get.find<PendingSaleSyncService>(),
        _repo = posRepository ?? PosRepository(),
        _payments = paymentsRepository ?? PosPaymentsRepository();

  final PendingSaleSyncService _sync;
  final PendingCashSyncService? _cashOverride;
  final PendingTeamSyncService? _teamOverride;

  /// G3.6: clock events made offline (a third queue; it never blocks closing a shift) and, for managers, the attendance problems to review.
  PendingTeamSyncService? get _team => _teamOverride ?? (Get.isRegistered<PendingTeamSyncService>() ? Get.find<PendingTeamSyncService>() : null);
  RxList<PendingClockRecord> get teamItems => _team?.items ?? _noTeam;
  static final RxList<PendingClockRecord> _noTeam = <PendingClockRecord>[].obs;
  final RxList<AttendanceAnomaly> anomalies = <AttendanceAnomaly>[].obs;
  final RxBool isLoadingAnomalies = false.obs;
  final RxnString anomalyError = RxnString();

  /// G3.5: cash in / out, drawer expenses and receipt photos queued offline (a separate queue from the sales above; null when the till has none).
  PendingCashSyncService? get _cash => _cashOverride ?? (Get.isRegistered<PendingCashSyncService>() ? Get.find<PendingCashSyncService>() : null);
  RxList<PendingCashRecord> get cashItems => _cash?.items ?? _noCash;
  static final RxList<PendingCashRecord> _noCash = <PendingCashRecord>[].obs;
  final PosRepository _repo;
  final PosPaymentsRepository _payments;

  /// Digital (Raast) payments a manager must resolve. Cashiers see them read-only (the server only lists them to a PIN session).
  final RxList<PosAttentionItem> digital = <PosAttentionItem>[].obs;
  final RxBool isLoadingDigital = false.obs;

  final RxBool isManager = false.obs;
  final RxList<PosSaleModel> flaggedSales = <PosSaleModel>[].obs;
  final RxBool isLoadingFlagged = false.obs;

  RxList<PendingSaleRecord> get items => _sync.items;
  RxBool get isSyncing => _sync.isSyncing;
  Rxn<DateTime> get lastSync => _sync.lastSuccessfulSync;

  @override
  void onInit() {
    super.onInit();
    PosRole.isCurrentEmployeeManager().then((v) {
      isManager.value = v;
      if (v) loadAnomalies();
    });
    _team?.refreshCounts();
    _sync.refreshCounts();
    _cash?.refreshCounts();
    loadFlagged();
    loadDigital();
  }

  Future<void> loadDigital() async {
    final storeId = await AppPreferences.getStoreId();
    if (storeId == null || storeId.isEmpty) return;
    isLoadingDigital.value = true;
    try {
      final r = await _payments.attention(storeId: storeId);
      if (r.ok) digital.assignAll(r.items);
    } finally {
      isLoadingDigital.value = false;
    }
  }

  String amountOf(PosAttentionItem i) => Money.format(Money.fromMinor(i.amountMinor, i.currencyExponent), currency: i.currency, exponent: i.currencyExponent);

  // ── Digital payment actions (manager PIN session; the server enforces the role and audit-logs each one) ──────────────────
  Future<void> attachToSale(PosAttentionItem i) async {
    if (!_managerOnly()) return;
    final ref = await _ask(title: 'Attach to a sale', message: 'Enter the receipt number of the sale this payment belongs to (for example POS-00012).', label: 'Receipt number', action: 'Attach', minLength: 4);
    if (ref == null) return;
    final note = 'attached to $ref';
    final r = await _payments.reconcile(i.intentId, resolution: 'sale_recorded', saleNumber: ref.trim(), note: note, idempotencyKey: 'att-${i.intentId}-${ref.trim()}');
    _done(r, 'Payment attached to $ref.');
  }

  Future<void> refund(PosAttentionItem i) async {
    if (!_managerOnly()) return;
    final ok = await _confirm(title: 'Refund ${amountOf(i)} to the customer?', message: 'The money goes back through Raast to the payer. This is written to the audit log.', action: 'Refund');
    if (!ok) return;
    final r = await _payments.reconcile(i.intentId, resolution: 'refund', note: 'refund from Needs attention', idempotencyKey: 'rf-${i.intentId}');
    _done(r, 'Refund sent.');
  }

  Future<void> resolveWithNote(PosAttentionItem i) async {
    if (!_managerOnly()) return;
    final note = await _ask(title: 'Resolve with a note', message: 'Explain what was done (at least 10 characters). It is written to the audit log.', label: 'Note (required)', action: 'Resolve', minLength: 10);
    if (note == null) return;
    final r = await _payments.reconcile(i.intentId, resolution: 'resolved', note: note, idempotencyKey: 'rs-${i.intentId}');
    _done(r, 'Marked as resolved.');
  }

  bool _managerOnly() {
    if (isManager.value) return true;
    CustomAppSnackbar.warning('Only a manager can do this.');
    return false;
  }

  void _done(PaymentCall r, String okMessage) {
    if (r.intent != null) {
      CustomAppSnackbar.success(okMessage);
      loadDigital();
    } else {
      CustomAppSnackbar.error(r.message ?? (r.connectivityError ? 'No connection — nothing was changed.' : 'That did not work.'));
    }
  }

  Future<bool> _confirm({required String title, required String message, required String action}) async {
    final ok = await Get.dialog<bool>(AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')), TextButton(onPressed: () => Get.back(result: true), child: Text(action))]));
    return ok == true;
  }

  Future<String?> _ask({required String title, required String message, required String label, required String action, required int minLength}) async {
    final controller = TextEditingController();
    final result = await Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, maxLength: 300, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.length < minLength) {
                CustomAppSnackbar.warning('Please write at least $minLength characters.');
                return;
              }
              Get.back(result: t);
            },
            child: Text(action),
          ),
        ],
      ),
    );
    // not at once: the dialog is still animating out and its text field would read a disposed controller
    Future<void>.delayed(const Duration(milliseconds: 500), controller.dispose);
    return result;
  }

  Future<void> loadFlagged() async {
    final storeId = await AppPreferences.getStoreId();
    if (storeId == null || storeId.isEmpty) return;
    isLoadingFlagged.value = true;
    try {
      flaggedSales.assignAll(await _repo.getSalesNeedingReview(storeId));
    } finally {
      isLoadingFlagged.value = false;
    }
  }

  Future<void> syncNow() async {
    await _sync.syncNow(ignoreBackoff: true);
    await _cash?.syncNow(ignoreBackoff: true);
    await _team?.syncNow(ignoreBackoff: true);
  }

  // ── G3.6 attendance problems (managers) and clock events refused by the server ──────────────────────────────────────────────────

  /// Missing clock-outs, double clock-ins, overlaps, clock without clock-in, device clock ahead, late syncs: what a manager should look at.
  Future<void> loadAnomalies() async {
    final storeId = await AppPreferences.getStoreId();
    if (storeId == null || storeId.isEmpty || !isManager.value) return;
    isLoadingAnomalies.value = true;
    anomalyError.value = null;
    try {
      final l = await _repo.getAttendanceAnomalies(storeId);
      if (l != null) {
        anomalies.assignAll(l);
        if (Get.isRegistered<TeamClockController>()) Get.find<TeamClockController>().anomalyCount.value = l.length;
      } else if (_repo.lastErrorCode != null) {
        anomalyError.value = teamErrorMessage(_repo.lastErrorCode);
      }
    } catch (_) {
      /* a list that could not be loaded just stays empty */
    } finally {
      isLoadingAnomalies.value = false;
    }
  }

  /// The attendance record an anomaly is about (so "Fix" can open the Correct sheet on it), or null when it cannot be found.
  Future<AttendanceRecord?> findRecord(AttendanceAnomaly a) async {
    final storeId = await AppPreferences.getStoreId();
    final at = a.at;
    if (storeId == null || !a.fixable || at == null) return null;
    final list = await _repo.getAttendanceRecords(storeId, from: at.subtract(const Duration(days: 2)), to: at.add(const Duration(days: 2)), employeeId: a.employeeId);
    return list?.firstWhereOrNull((r) => r.recordId == a.recordId);
  }

  /// "Seen, no action needed": the server stops listing it. Managers only.
  Future<void> ackAnomaly(AttendanceAnomaly a) async {
    if (!isManager.value) {
      CustomAppSnackbar.warning('Only a manager can acknowledge this.');
      return;
    }
    final storeId = await AppPreferences.getStoreId();
    if (storeId == null || !a.ackable) return;
    final r = await _repo.ackAttendanceAnomaly(storeId, employeeId: a.employeeId, eventId: a.eventId!, kind: a.kind);
    if (r.success) {
      anomalies.remove(a);
      if (Get.isRegistered<TeamClockController>()) Get.find<TeamClockController>().anomalyCount.value = anomalies.length;
      CustomAppSnackbar.success('Acknowledged.');
    } else {
      CustomAppSnackbar.error(teamErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message));
    }
  }

  Future<void> retryClock(PendingClockRecord r) async {
    await _team?.retry(r.id);
    CustomAppSnackbar.success('Retrying…');
  }

  /// Manager-only: give up on a clock event the server refused (a manager can add the time by hand from the attendance record).
  Future<void> dismissClock(PendingClockRecord r) async {
    if (!isManager.value) {
      CustomAppSnackbar.warning('Only a manager can dismiss a clock event.');
      return;
    }
    final ok = await _confirm(title: 'Dismiss this clock event?', message: 'It was never recorded on the server. Dismissing removes it from this device for good; a manager can add the missing time from the attendance record.', action: 'Dismiss');
    if (!ok) return;
    await _team?.dismiss(r.id);
    CustomAppSnackbar.success('Clock event dismissed.');
  }

  /// Retry a rejected cash entry (it is sent again as whoever is signed in).
  Future<void> retryCash(PendingCashRecord r) async {
    await _cash?.retry(r.id);
    CustomAppSnackbar.success('Retrying…');
  }

  /// Manager-only: give up on a cash entry that the server refused (it is NOT in the books and never will be). Asks for confirmation first.
  Future<void> dismissCash(PendingCashRecord r) async {
    if (!isManager.value) {
      CustomAppSnackbar.warning('Only a manager can dismiss a cash entry.');
      return;
    }
    final ok = await _confirm(
      title: 'Dismiss this entry?',
      message: 'It was never recorded on the server. Dismissing removes it from this device for good, so the drawer count may differ from the books by this amount.',
      action: 'Dismiss',
    );
    if (!ok) return;
    await _cash?.dismiss(r.id);
    CustomAppSnackbar.success('Entry dismissed.');
  }

  Future<void> retry(PendingSaleRecord r) async {
    if (!isManager.value && r.isFailed) {
      CustomAppSnackbar.warning('Only a manager can retry a rejected sale.');
      return;
    }
    await _sync.retry(r.id);
    CustomAppSnackbar.success('Retrying…');
  }

  /// Manager-only. Asks for a reason (required), then keeps the sale on the device until the discard is on the
  /// server's audit log.
  Future<void> discard(PendingSaleRecord r) async {
    if (!isManager.value) {
      CustomAppSnackbar.warning('Only a manager can discard an unsynced sale.');
      return;
    }
    final reason = await _askReason(
      title: 'Discard this sale?',
      message: 'It was never recorded on the server. The reason you give is written to the audit log; the sale is kept on this device until that is done.',
      action: 'Discard sale',
    );
    if (reason == null) return;
    await _sync.discard(
      r.id,
      reason: reason,
      managerEmployeeId: await AppPreferences.getPosEmployeeId() ?? '',
      managerToken: await AppPreferences.getPosEmployeeToken(),
    );
    CustomAppSnackbar.success('Discard recorded.');
  }

  Future<void> markReviewed(PosSaleModel sale) async {
    if (!isManager.value) {
      CustomAppSnackbar.warning('Only a manager can mark a sale as reviewed.');
      return;
    }
    final note = await _askReason(title: 'Mark as reviewed', message: 'What did you check or correct?', action: 'Mark reviewed');
    if (note == null) return;
    final res = await _repo.resolveSaleReview(sale.id, note);
    if (res.success) {
      flaggedSales.remove(sale);
      CustomAppSnackbar.success('Marked as reviewed.');
    } else {
      CustomAppSnackbar.error(res.message ?? 'Could not mark as reviewed.');
    }
  }

  Future<String?> _askReason({required String title, required String message, required String action}) async {
    final controller = TextEditingController();
    final result = await Get.dialog<String>(
      AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          const SizedBox(height: 12),
          TextField(controller: controller, autofocus: true, maxLength: 300, decoration: const InputDecoration(labelText: 'Reason (required)', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final t = controller.text.trim();
              if (t.length < 3) {
                CustomAppSnackbar.warning('Please write a short reason.');
                return;
              }
              Get.back(result: t);
            },
            child: Text(action),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }
}
