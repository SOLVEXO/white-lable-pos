import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Drains the on-device queue of sales that could not reach the server.
///
///  * **FIFO per session, one in flight at a time.** Oldest first; a sale that hits a retryable error stops its
///    session's turn (its backoff gates the later ones), other sessions continue.
///  * **Exponential backoff** per sale (5s, 10s, 20s … capped at 15 min), reset by a manager's Retry. Resumes on
///    reconnect, when the app returns to the foreground, and on a scheduled retry — never a tight loop.
///  * **Nothing is dropped.** A definite server "no" (sale too old, outside its session, plan not active when it was
///    made …) turns the row `failed` with the server's reason — it waits in the Needs-attention list for a manager to
///    retry or discard (with a reason, which is recorded in the server's audit log). A retryable error (no network,
///    timeout, 5xx, "still in progress") just keeps it pending.
///  * Every replay carries the sale's ORIGINAL idempotency key, `clientCreatedAt`, `settingsVersion` and `sessionId`,
///    so a replay after a crash or timeout can never create a second sale.
///  * Rows belong to a store; only the store currently signed in is synced, and sign-out never deletes rows.
class PendingSaleSyncService extends GetxController with WidgetsBindingObserver {
  PendingSaleSyncService({
    PosRepository? posRepository,
    PendingSaleLocalStore? localStore,
    Future<String?> Function()? currentStoreId,
    DateTime Function()? clock,
    this.persistLastSync = true,
    bool Function()? hasCredentials,
  })  : _posRepo = posRepository ?? PosRepository(),
        _store = localStore ?? PendingSaleLocalStore(),
        _currentStoreId = currentStoreId ?? AppPreferences.getStoreId,
        _clock = clock ?? DateTime.now,
        _hasCredentials = hasCredentials ?? (() => true);

  final PosRepository _posRepo;
  final PendingSaleLocalStore _store;
  final Future<String?> Function() _currentStoreId;
  final DateTime Function() _clock;
  final bool persistLastSync;

  /// False while the device has no usable credential (revoked / not set up): the queue just waits — nothing is sent, nothing
  /// is dropped — and drains once the owner registers the device again.
  final bool Function() _hasCredentials;

  /// Waiting to be sent (includes ones backing off).
  final RxInt pendingCount = 0.obs;

  /// Rejected by the server — needs a manager (retry / discard).
  final RxInt failedCount = 0.obs;

  /// pending + failed: everything that still blocks closing the shift / signing out.
  final RxInt unresolvedCount = 0.obs;

  /// Every queued row (newest data after each change) — what the Needs-attention screen shows.
  final RxList<PendingSaleRecord> items = <PendingSaleRecord>[].obs;

  final RxBool isSyncing = false.obs;
  final Rxn<DateTime> lastSuccessfulSync = Rxn<DateTime>();

  Worker? _onlineWorker;
  Timer? _retryTimer;
  bool _syncing = false;

  static const _lastSyncKey = 'pos_last_successful_sync';

  /// 5s, 10s, 20s … capped at 15 minutes.
  static Duration backoff(int attempts) {
    final secs = 5 * (1 << (attempts.clamp(0, 10)));
    return Duration(seconds: secs > 900 ? 900 : secs);
  }

  Future<void> init() async {
    await refreshCounts();
    if (persistLastSync) {
      final raw = await AppPreferences.getString(_lastSyncKey);
      lastSuccessfulSync.value = raw == null ? null : DateTime.tryParse(raw);
    }
    WidgetsBinding.instance.addObserver(this);
    if (Get.isRegistered<NetworkStatusService>()) {
      final net = Get.find<NetworkStatusService>();
      _onlineWorker = ever<bool>(net.isOnline, (online) {
        if (online) syncNow();
      });
      if (net.isOnline.value) unawaited(syncNow());
    } else {
      unawaited(syncNow());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncNow());
  }

  Future<void> enqueue(String id, Map<String, dynamic> payload, {String? employeeToken}) async {
    await _store.enqueue(id, payload, employeeToken: employeeToken);
    await refreshCounts();
  }

  /// One sync attempt shortly from now (replaces a pending one) — for a sale queued while the device is *online*
  /// (timeout / 5xx), where no reconnect event will ever fire.
  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(syncNow()));
  }

  Future<List<PendingSaleRecord>> records() => _store.getAll();

  /// Unresolved (pending + failed) sales of one session — what must be resolved before that shift can close.
  Future<int> unresolvedForSession(String sessionId) => _store.countUnresolved(sessionId: sessionId);

  /// Anything unresolved at all (any session) for the signed-in store — what blocks sign-out.
  Future<int> unresolvedForStore() async => _store.countUnresolved(storeId: await _currentStoreId());

  Future<void> refreshCounts() async {
    pendingCount.value = await _store.countPending();
    failedCount.value = await _store.countFailed();
    unresolvedCount.value = pendingCount.value + failedCount.value;
    items.assignAll(await _store.getAll());
  }

  /// Manager pressed Retry on a failed (or backing-off) sale: try again right now.
  Future<void> retry(String id) async {
    await _store.resetForRetry(id);
    await refreshCounts();
    unawaited(syncNow());
  }

  /// A manager gives up on a sale. The caller must have checked the manager role and collected a [reason]. The row
  /// stays on the device as `discarding` until the discard is written to the server's audit log, then it is removed.
  Future<void> discard(String id, {required String reason, required String managerEmployeeId, String? managerToken}) async {
    if (reason.trim().length < 3) throw ArgumentError('A reason is required to discard an unsynced sale.');
    await _store.markDiscarding(id, reason: reason.trim(), discardedBy: managerEmployeeId, managerToken: managerToken);
    await refreshCounts();
    unawaited(syncNow());
  }

  /// Sends everything that is due. Safe to call from anywhere, any number of times (a mutex keeps it to one pass).
  /// With [ignoreBackoff] (tests, manual "sync now") rows backing off are tried immediately.
  Future<void> syncNow({bool ignoreBackoff = false}) async {
    if (_syncing || !_hasCredentials()) return;
    _syncing = true;
    isSyncing.value = true;
    var anyBackingOff = false;
    try {
      final storeId = await _currentStoreId();
      final all = await _store.getAll();
      final now = _clock();

      // 1) record manager discards in the audit log (they need the network, nothing else about them does)
      for (final d in all.where((r) => r.isDiscarding && (storeId == null || r.storeId == storeId))) {
        final res = await _posRepo.recordOfflineDiscard(
          storeId: d.storeId,
          idempotencyKey: d.id,
          reason: d.discardReason ?? '',
          summary: {'madeAt': d.madeAt.toIso8601String(), 'total': d.deviceTotal, 'items': d.summary, 'sessionId': d.sessionId, 'discardedBy': d.discardedBy},
          employeeToken: d.employeeToken,
        );
        if (res.recorded) {
          await _store.remove(d.id);
        } else if (res.alreadySynced) {
          // The sale actually reached the server (a replay succeeded after the manager decided) — it is a real
          // sale now, so the discard is moot: put it back as pending so the next pass confirms it.
          await _store.resetForRetry(d.id);
        } else if (res.connectivityError) {
          break;
        }
      }

      // 2) replay sales — FIFO per session, one at a time
      final bySession = <String, List<PendingSaleRecord>>{};
      for (final r in all.where((r) => r.isPending && (storeId == null || r.storeId == storeId))) {
        (bySession[r.sessionId] ??= []).add(r);
      }
      var offline = false;
      for (final queue in bySession.values) {
        if (offline) break;
        for (final record in queue) {
          if (!ignoreBackoff && record.nextAttemptAt != null && record.nextAttemptAt!.isAfter(now)) {
            anyBackingOff = true;
            break; // its backoff gates the later sales of this session
          }
          final result = await _posRepo.submitRawSale(record.payload, employeeToken: record.employeeToken);
          if (result.success) {
            await _store.remove(record.id);
            lastSuccessfulSync.value = _clock();
            if (persistLastSync) await AppPreferences.setString(_lastSyncKey, lastSuccessfulSync.value!.toIso8601String());
          } else if (result.connectivityError) {
            await _store.recordAttempt(record.id, attempts: record.attempts + 1, nextAttemptAt: _clock().add(backoff(record.attempts)), errorMessage: result.message);
            offline = true;
            anyBackingOff = true;
            break;
          } else if (result.retryable) {
            await _store.recordAttempt(record.id, attempts: record.attempts + 1, nextAttemptAt: _clock().add(backoff(record.attempts)), errorMessage: result.message);
            anyBackingOff = true;
            break;
          } else {
            // A definite rejection: keep the sale, show the reason, wait for a manager.
            await _store.markFailed(record.id, result.message ?? 'The server rejected this sale.', errorCode: result.code);
          }
        }
      }
    } finally {
      _syncing = false;
      isSyncing.value = false;
      await refreshCounts();
      if (anyBackingOff && unresolvedCount.value > 0) {
        // wake up for the earliest backoff instead of polling
        scheduleSync(delay: const Duration(seconds: 30));
      }
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _onlineWorker?.dispose();
    super.onClose();
  }
}
