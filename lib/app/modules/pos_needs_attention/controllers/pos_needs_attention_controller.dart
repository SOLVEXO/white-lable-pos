import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
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
  PosNeedsAttentionController({PendingSaleSyncService? syncService, PosRepository? posRepository, PosPaymentsRepository? paymentsRepository})
      : _sync = syncService ?? Get.find<PendingSaleSyncService>(),
        _repo = posRepository ?? PosRepository(),
        _payments = paymentsRepository ?? PosPaymentsRepository();

  final PendingSaleSyncService _sync;
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
    PosRole.isCurrentEmployeeManager().then((v) => isManager.value = v);
    _sync.refreshCounts();
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

  Future<void> syncNow() => _sync.syncNow(ignoreBackoff: true);

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
