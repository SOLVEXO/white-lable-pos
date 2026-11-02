import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/pos_role.dart';

/// "Needs attention": every sale that has not (yet) reached the server, why, and what a manager can do about it —
/// plus sales the server RECORDED but flagged (oversold on sync, price changed while offline, payment shortfall).
/// Nothing here is ever dropped silently: a sale leaves the list only by syncing, or by a manager discarding it with
/// a reason that is written to the server's audit log.
class PosNeedsAttentionController extends GetxController {
  PosNeedsAttentionController({PendingSaleSyncService? syncService, PosRepository? posRepository})
      : _sync = syncService ?? Get.find<PendingSaleSyncService>(),
        _repo = posRepository ?? PosRepository();

  final PendingSaleSyncService _sync;
  final PosRepository _repo;

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
