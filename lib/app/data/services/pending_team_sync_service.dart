import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Drains the on-device queue of clock events made offline (clock in / out, breaks).
///
///  * **In order, one at a time**, oldest first. A retryable failure (no network, timeout, 5xx) stops the pass and is retried with the sale queue's
///    backoff; a reconnect, the app returning to the foreground and a scheduled retry resume it. Never a tight loop.
///  * **Exactly once.** Every replay carries its ORIGINAL request id and the time the person really tapped (`deviceAt`); `duplicate: true` is success.
///  * **A person is never blocked offline.** The server records a late event as it happened and raises any inconsistency as an anomaly for a manager,
///    so a clock event is always accepted locally; only a definite refusal (validation, EMPLOYEE_REQUIRED) is parked under Needs attention (Retry / Dismiss).
///  * Attendance events do NOT block closing a shift or signing out.
class PendingTeamSyncService extends GetxController with WidgetsBindingObserver {
  PendingTeamSyncService({PosRepository? posRepository, PendingTeamLocalStore? localStore, Future<String?> Function()? currentStoreId, DateTime Function()? clock, bool Function()? hasCredentials})
    : _repo = posRepository ?? PosRepository(),
      _store = localStore ?? PendingTeamLocalStore(),
      _currentStoreId = currentStoreId ?? AppPreferences.getStoreId,
      _clock = clock ?? DateTime.now,
      _hasCredentials = hasCredentials ?? (() => true);

  final PosRepository _repo;
  final PendingTeamLocalStore _store;
  final Future<String?> Function() _currentStoreId;
  final DateTime Function() _clock;
  final bool Function() _hasCredentials;

  final RxInt pendingCount = 0.obs;
  final RxInt failedCount = 0.obs;
  final RxList<PendingClockRecord> items = <PendingClockRecord>[].obs;
  final RxBool isSyncing = false.obs;

  /// goes up every time at least one queued event reached the server (screens refresh their state from the server when it changes)
  final RxInt syncedTick = 0.obs;

  Worker? _onlineWorker;
  Timer? _retryTimer;
  bool _syncing = false;

  static Duration backoff(int attempts) => PendingSaleSyncService.backoff(attempts);

  Future<void> init() async {
    await refreshCounts();
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

  /// Queues a clock event the person tapped at [deviceAt]. It is accepted locally whatever the server will say later.
  Future<PendingClockRecord> enqueue({
    required String storeId,
    required String requestId,
    required String action,
    required DateTime deviceAt,
    required String employeeId,
    String? note,
    String? employeeToken,
  }) async {
    final r = await _store.enqueue(id: requestId, action: action, deviceAt: deviceAt, storeId: storeId, employeeId: employeeId, note: note, employeeToken: employeeToken);
    await refreshCounts();
    return r;
  }

  Future<List<PendingClockRecord>> records() => _store.getAll();

  Future<void> refreshCounts() async {
    final all = await _store.getAll();
    pendingCount.value = all.where((r) => r.isPending).length;
    failedCount.value = all.where((r) => r.isFailed).length;
    items.assignAll(all);
  }

  /// The events of [employeeId] that are still waiting to be sent, oldest first: what the local clock state is derived from.
  List<PendingClockRecord> pendingFor(String employeeId) => [
    for (final r in items)
      if (r.isPending && r.employeeId == employeeId) r,
  ];

  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(syncNow()));
  }

  Future<void> retry(String id) async {
    await _store.resetForRetry(id);
    await refreshCounts();
    unawaited(syncNow(ignoreBackoff: true));
  }

  Future<void> dismiss(String id) async {
    await _store.remove(id);
    await refreshCounts();
  }

  Future<void> syncNow({bool ignoreBackoff = false}) async {
    if (_syncing || !_hasCredentials()) return;
    _syncing = true;
    isSyncing.value = true;
    var backingOff = false;
    var any = false;
    try {
      final storeId = await _currentStoreId();
      for (final r in await _store.getAll()) {
        if (!r.isPending || (storeId != null && r.storeId != storeId) || r.unreadable) continue;
        if (!ignoreBackoff && r.nextAttemptAt != null && r.nextAttemptAt!.isAfter(_clock())) {
          backingOff = true;
          break; // in order: this one's backoff gates the later ones
        }
        final res = await _repo.teamClock(r.storeId, action: r.action, requestId: r.id, deviceAt: r.deviceAt, note: r.note, employeeToken: r.employeeToken);
        if (res.success) {
          await _store.remove(r.id); // duplicate:true is success too
          any = true;
        } else if (res.retryable) {
          await _store.recordAttempt(r.id, attempts: r.attempts + 1, nextAttemptAt: _clock().add(backoff(r.attempts)), errorMessage: res.message);
          backingOff = true;
          break;
        } else {
          await _store.markFailed(r.id, teamErrorMessage(res.code, fallback: res.message), errorCode: res.code);
        }
      }
    } finally {
      _syncing = false;
      isSyncing.value = false;
      await refreshCounts();
      if (any) syncedTick.value++;
      if (backingOff && pendingCount.value > 0) scheduleSync(delay: const Duration(seconds: 30));
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
