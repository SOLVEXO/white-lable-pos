import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:path/path.dart' as p;
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:sqflite/sqflite.dart' show getDatabasesPath;

/// Drains the on-device queue of cash requests made offline: cash in / out, DRAWER expenses and the photo of an expense.
///
///  * **In order, one at a time**, oldest first (the order they were made in). A retryable failure (no network, timeout, 5xx, "still in
///    progress") stops the pass and is retried with exponential backoff (the sale queue's schedule); a reconnect, the app returning to the
///    foreground and a scheduled retry resume it. Never a tight loop.
///  * **Exactly once.** Every replay carries its ORIGINAL request id (the idempotency key) and the device time (`occurredAt`); the server
///    answers `duplicate: true` for one it already has, which is a success here.
///  * **Conflicts are not retried.** A definite "no" (the shift closed meanwhile, over the limit with nobody to approve, validation) turns the
///    row `failed` with a clear message and waits under Needs attention for Retry or Dismiss. It never blocks the rows after it.
///  * **Receipt photos** wait for their expense to exist on the server, then upload; the local copy of the photo is deleted once it is uploaded
///    (or the entry is dismissed), and only then.
class PendingCashSyncService extends GetxController with WidgetsBindingObserver {
  PendingCashSyncService({
    PosRepository? posRepository,
    PendingCashLocalStore? localStore,
    Future<String?> Function()? currentStoreId,
    DateTime Function()? clock,
    bool Function()? hasCredentials,
    Future<void> Function(String path)? deleteFile,
    Future<String> Function(File source)? keepFile,
  }) : _repo = posRepository ?? PosRepository(),
       _store = localStore ?? PendingCashLocalStore(),
       _currentStoreId = currentStoreId ?? AppPreferences.getStoreId,
       _clock = clock ?? DateTime.now,
       _hasCredentials = hasCredentials ?? (() => true),
       _deleteFile = deleteFile ?? _defaultDelete,
       _keepFile = keepFile ?? _defaultKeep;

  final PosRepository _repo;
  final PendingCashLocalStore _store;
  final Future<String?> Function() _currentStoreId;
  final DateTime Function() _clock;
  final bool Function() _hasCredentials;
  final Future<void> Function(String path) _deleteFile;
  final Future<String> Function(File source) _keepFile;

  static Future<void> _defaultDelete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Copies a picked photo into the app's own folder (the picker's temp file may be cleaned up before the upload).
  static Future<String> _defaultKeep(File source) async {
    final dir = Directory(p.join(await getDatabasesPath(), 'cash_receipts'));
    await dir.create(recursive: true);
    final ext = p.extension(source.path).isEmpty ? '.jpg' : p.extension(source.path);
    final dest = p.join(dir.path, 'r-${DateTime.now().microsecondsSinceEpoch}$ext');
    await source.copy(dest);
    return dest;
  }

  final RxInt pendingCount = 0.obs;
  final RxInt failedCount = 0.obs;
  final RxInt unresolvedCount = 0.obs;
  final RxList<PendingCashRecord> items = <PendingCashRecord>[].obs;
  final RxBool isSyncing = false.obs;

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

  Future<String> keepPhoto(File source) => _keepFile(source);

  /// Queues a cash in / out. [sessionId] is the open shift it belongs to; [employeeToken] replays it as the employee who made it.
  Future<PendingCashRecord> enqueueMovement({
    required String storeId,
    required String requestId,
    required String type,
    required String category,
    required int amountMinor,
    required String sessionId,
    required String currency,
    required int currencyExponent,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
  }) async {
    final r = await _store.enqueue(
      id: requestId,
      kind: PendingCashKind.movement,
      storeId: storeId,
      sessionId: sessionId,
      employeeToken: employeeToken,
      payload: {
        'type': type,
        'category': category,
        'amountMinor': amountMinor,
        'sessionId': sessionId,
        'requestId': requestId,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'occurredAt': (occurredAt ?? _clock()).toUtc().toIso8601String(),
        'currency': currency,
        'currencyExponent': currencyExponent,
      },
    );
    await refreshCounts();
    return r;
  }

  /// Queues a DRAWER (cash) expense. Bank / other expenses are online only and never come here.
  Future<PendingCashRecord> enqueueExpense({
    required String storeId,
    required String requestId,
    required String category,
    required int amountMinor,
    required String sessionId,
    required String currency,
    required int currencyExponent,
    String? payee,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
  }) async {
    final r = await _store.enqueue(
      id: requestId,
      kind: PendingCashKind.expense,
      storeId: storeId,
      sessionId: sessionId,
      employeeToken: employeeToken,
      payload: {
        'category': category,
        'method': 'cash',
        'amountMinor': amountMinor,
        'sessionId': sessionId,
        'requestId': requestId,
        if (payee != null && payee.trim().isNotEmpty) 'payee': payee.trim(),
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        'occurredAt': (occurredAt ?? _clock()).toUtc().toIso8601String(),
        'currency': currency,
        'currencyExponent': currencyExponent,
      },
    );
    await refreshCounts();
    return r;
  }

  /// Queues the photo of an expense. [expenseRequestId] = the request id of an expense still in this queue; or pass [expenseId] when the expense
  /// is already on the server. [path] is a copy kept by [keepPhoto].
  Future<PendingCashRecord> enqueueReceipt({required String storeId, required String path, String? expenseRequestId, String? expenseId, String? employeeToken}) async {
    final r = await _store.enqueue(
      id: 'rcpt-${expenseRequestId ?? expenseId}-${_clock().microsecondsSinceEpoch}',
      kind: PendingCashKind.receipt,
      storeId: storeId,
      refId: expenseRequestId,
      employeeToken: employeeToken,
      payload: {'filePath': path, if (expenseId != null) 'expenseId': expenseId},
    );
    await refreshCounts();
    return r;
  }

  Future<List<PendingCashRecord>> records() => _store.getAll();

  Future<void> refreshCounts() async {
    pendingCount.value = await _store.countPending();
    failedCount.value = await _store.countFailed();
    unresolvedCount.value = pendingCount.value + failedCount.value;
    items.assignAll(await _store.getAll());
  }

  /// Unresolved (pending + failed) cash movements and expenses of one shift: what must be resolved before that shift closes.
  Future<int> unresolvedForSession(String sessionId) async => await _store.countPending(sessionId: sessionId) + await _store.countFailed(sessionId: sessionId);

  /// What is waiting for the shift [sessionId] (movements and expenses, not photos): "Waiting to sync" on the cash screen.
  List<PendingCashRecord> waitingForSession(String sessionId) => [
    for (final r in items)
      if (r.isPending && !r.isReceipt && r.sessionId == sessionId) r,
  ];

  void scheduleSync({Duration delay = const Duration(seconds: 5)}) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(syncNow()));
  }

  /// Retry a parked row now (sent as whoever is signed in).
  Future<void> retry(String id) async {
    await _store.resetForRetry(id);
    for (final c in await _store.childrenOf(id)) {
      if (c.isFailed) await _store.resetForRetry(c.id);
    }
    await refreshCounts();
    unawaited(syncNow(ignoreBackoff: true));
  }

  /// Gives up on a row (a manager's decision, made by the caller). Its photos go with it, and the local photo files are deleted.
  Future<void> dismiss(String id) async {
    final rec = await _store.getById(id);
    if (rec == null) return;
    for (final c in await _store.childrenOf(id)) {
      final path = c.payload['filePath'] as String?;
      if (path != null) await _deleteFile(path);
      await _store.remove(c.id);
    }
    final own = rec.payload['filePath'] as String?;
    if (own != null) await _deleteFile(own);
    await _store.remove(id);
    await refreshCounts();
  }

  /// Sends everything that is due, oldest first. Safe to call from anywhere (a mutex keeps it to one pass). [ignoreBackoff] tries rows that
  /// are backing off right away (manual "sync now", tests).
  Future<void> syncNow({bool ignoreBackoff = false}) async {
    if (_syncing || !_hasCredentials()) return;
    _syncing = true;
    isSyncing.value = true;
    var backingOff = false;
    try {
      final storeId = await _currentStoreId();
      final all = await _store.getAll();
      final failedExpenseIds = {
        for (final r in all)
          if (r.isExpense && r.isFailed) r.id,
      };
      for (final r in all) {
        if (!r.isPending || (storeId != null && r.storeId != storeId)) continue;
        if (!ignoreBackoff && r.nextAttemptAt != null && r.nextAttemptAt!.isAfter(_clock())) {
          backingOff = true;
          break; // in order: this one's backoff gates the later ones
        }
        if (r.unreadable) continue;
        if (r.isReceipt) {
          if (failedExpenseIds.contains(r.refId)) continue; // its expense is parked: the photo waits for it
          final fresh = await _store.getById(r.id) ?? r; // its expense may have just synced in this very pass
          final expenseId = fresh.payload['expenseId'] as String?;
          if (expenseId == null) {
            final parent = r.refId == null ? null : await _store.getById(r.refId!);
            if (parent != null) continue; // the expense is still ahead of it in the queue
            await _store.markFailed(r.id, 'The expense this photo belongs to is not on the server.', errorCode: 'EXPENSE_NOT_FOUND');
            continue;
          }
          final path = fresh.payload['filePath'] as String? ?? '';
          if (path.isEmpty || !await File(path).exists()) {
            await _store.markFailed(r.id, 'The photo is no longer on this device.', errorCode: 'FILE_REQUIRED');
            continue;
          }
          final res = await _repo.uploadExpenseReceipt(r.storeId, expenseId, File(path), employeeToken: r.employeeToken);
          if (res.success) {
            await _deleteFile(path);
            await _store.remove(r.id);
          } else if (res.retryable) {
            await _store.recordAttempt(r.id, attempts: r.attempts + 1, nextAttemptAt: _clock().add(backoff(r.attempts)), errorMessage: res.message);
            backingOff = true;
            break;
          } else {
            await _store.markFailed(r.id, cashErrorMessage(res.code, fallback: res.message), errorCode: res.code);
          }
          continue;
        }
        final bool success;
        final bool retryable;
        final String? code;
        final String? message;
        String? expenseId;
        if (r.isMovement) {
          final res = await _repo.recordCashMovement(
            r.storeId,
            type: r.payload['type'] as String,
            category: r.payload['category'] as String,
            amountMinor: r.amountMinor,
            sessionId: r.payload['sessionId'] as String? ?? r.sessionId,
            requestId: r.id,
            note: r.payload['note'] as String?,
            occurredAt: DateTime.tryParse('${r.payload['occurredAt']}'),
            employeeToken: r.employeeToken,
          );
          success = res.success;
          retryable = res.retryable;
          code = res.code;
          message = res.message;
        } else {
          final res = await _repo.recordExpense(
            r.storeId,
            category: r.payload['category'] as String,
            method: 'cash',
            amountMinor: r.amountMinor,
            requestId: r.id,
            sessionId: r.payload['sessionId'] as String? ?? r.sessionId,
            payee: r.payload['payee'] as String?,
            note: r.payload['note'] as String?,
            occurredAt: DateTime.tryParse('${r.payload['occurredAt']}'),
            employeeToken: r.employeeToken,
          );
          success = res.success;
          retryable = res.retryable;
          code = res.code;
          message = res.message;
          expenseId = res.result?.expense.id;
        }
        if (success) {
          // a duplicate (already booked by an earlier try) is success too
          if (expenseId != null && expenseId.isNotEmpty) await _store.attachExpenseId(r.id, expenseId);
          await _store.remove(r.id);
        } else if (retryable) {
          await _store.recordAttempt(r.id, attempts: r.attempts + 1, nextAttemptAt: _clock().add(backoff(r.attempts)), errorMessage: message);
          backingOff = true;
          break;
        } else {
          await _store.markFailed(r.id, cashErrorMessage(code, fallback: message), errorCode: code);
          if (r.isExpense) failedExpenseIds.add(r.id);
        }
      }
    } finally {
      _syncing = false;
      isSyncing.value = false;
      await refreshCounts();
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
