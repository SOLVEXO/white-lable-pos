import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// What is still waiting to reach the server, for deciding whether an action that ends a shift / session of work may
/// proceed. Pure data so it can be unit-tested without UI.
class UnsyncedStatus {
  final int pending;
  final int failed;
  const UnsyncedStatus({required this.pending, required this.failed});
  int get total => pending + failed;
  bool get blocks => total > 0;
}

/// Blocks Close Shift / sign-out while sales rung up on this device have not reached the server — the queue is the
/// only copy of that money. They must sync, or a manager must resolve each one (retry, or discard with a reason).
class UnsyncedGuard {
  /// Tries one immediate sync (the queue may only be waiting on a backoff timer), then reports what is left for
  /// [sessionId] (or for the whole signed-in store when null).
  static Future<UnsyncedStatus> check({String? sessionId, PendingSaleSyncService? service}) async {
    final sync = service ?? (Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>() : null);
    if (sync == null) return const UnsyncedStatus(pending: 0, failed: 0);
    if (sync.unresolvedCount.value > 0) await sync.syncNow(ignoreBackoff: true);
    final left = sessionId != null ? await sync.unresolvedForSession(sessionId) : await sync.unresolvedForStore();
    if (left == 0) return const UnsyncedStatus(pending: 0, failed: 0);
    final rows = (await sync.records()).where((r) => r.isUnresolved && (sessionId == null || r.sessionId == sessionId));
    return UnsyncedStatus(pending: rows.where((r) => r.isPending).length, failed: rows.where((r) => r.isFailed).length);
  }

  /// Shows the blocking dialog when something is unsynced; returns true if the caller must STOP.
  static Future<bool> blockIfUnsynced({required String action, String? sessionId, PendingSaleSyncService? service}) async {
    final status = await check(sessionId: sessionId, service: service);
    if (!status.blocks) return false;
    final parts = [if (status.pending > 0) '${status.pending} waiting to sync', if (status.failed > 0) '${status.failed} rejected by the server'];
    await Get.dialog<void>(
      AlertDialog(
        title: Text("Can't $action yet"),
        content: Text(
          '${status.total} sale${status.total == 1 ? '' : 's'} on this device ${status.total == 1 ? "hasn't" : "haven't"} reached the server (${parts.join(', ')}).\n\n'
          'Connect to the internet so they can sync, or ask a manager to review and resolve each one. Nothing is lost — they stay on this device until then.',
        ),
        actions: [
          TextButton(onPressed: () => Get.back(), child: const Text('OK')),
          TextButton(
            onPressed: () {
              Get.back();
              Get.toNamed(Routes.posNeedsAttention);
            },
            child: const Text('Review'),
          ),
        ],
      ),
    );
    return true;
  }
}
