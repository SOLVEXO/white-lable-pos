import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';

/// Drains the on-device queue of sales that failed to reach the backend due
/// to a connectivity error (see `PosRepository.createSale`/`_isConnectivityError`)
/// as soon as `NetworkStatusService` reports a reconnect. Each queued sale
/// carries the same `idempotencyKey` the backend already dedupes on
/// (`sales.schema.ts` unique sparse index), so a retry — even a duplicate
/// one across app restarts — can never create two sale records.
///
/// `Get.put(PendingSaleSyncService(), permanent: true).init()` in main.dart,
/// mirroring `NetworkStatusService`'s own init pattern.
class PendingSaleSyncService extends GetxController {
  PendingSaleSyncService({PosRepository? posRepository, PendingSaleLocalStore? localStore})
      : _posRepo = posRepository ?? PosRepository(),
        _store = localStore ?? PendingSaleLocalStore();

  final PosRepository _posRepo;
  final PendingSaleLocalStore _store;

  final RxInt pendingCount = 0.obs;

  Worker? _onlineWorker;
  bool _syncing = false;

  Future<void> init() async {
    await _refreshCount();
    if (Get.isRegistered<NetworkStatusService>()) {
      final net = Get.find<NetworkStatusService>();
      _onlineWorker = ever<bool>(net.isOnline, (online) {
        if (online) syncNow();
      });
      if (net.isOnline.value) unawaited(syncNow());
    }
  }

  Future<void> enqueue(String id, Map<String, dynamic> payload) async {
    await _store.enqueue(id, payload);
    await _refreshCount();
  }

  /// Attempts to resubmit every still-pending sale, oldest first. Stops the
  /// pass (rather than skipping ahead) the moment a submission fails for
  /// connectivity reasons again — the rest would fail identically, and
  /// they'll all get another attempt on the next reconnect.
  Future<void> syncNow() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final pending = await _store.getAll();
      for (final record in pending) {
        if (record.status != 'pending') continue;
        final result = await _posRepo.submitRawSale(record.payload);
        if (result.success) {
          await _store.remove(record.id);
        } else if (result.connectivityError) {
          break;
        } else {
          // A real server rejection (e.g. the session/register this sale
          // referenced no longer exists) won't resolve itself by retrying —
          // flag it for manual review instead of retrying forever.
          await _store.markFailed(record.id, result.message ?? 'Sync failed');
        }
      }
    } finally {
      _syncing = false;
      await _refreshCount();
    }
  }

  Future<void> _refreshCount() async {
    pendingCount.value = await _store.countPending();
  }

  @override
  void onClose() {
    _onlineWorker?.dispose();
    super.onClose();
  }
}
