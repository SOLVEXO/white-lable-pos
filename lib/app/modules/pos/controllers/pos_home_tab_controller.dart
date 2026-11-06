import 'package:flutter/foundation.dart' show debugPrint;
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_dashboard_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// The Home tab. Read-only: it composes numbers the app ALREADY has an endpoint for (session report, daily report, 7-day
/// range report, low-stock summary, the offline queue). Nothing here writes, and nothing here is computed locally that the
/// server computes — every figure shown is a server figure.
class PosHomeTabController extends GetxController {
  PosHomeTabController({PosRepository? posRepository, InventoryRepository? inventoryRepository, PosPaymentsRepository? paymentsRepository, PosAccess? accessOverride})
      : _pos = posRepository ?? PosRepository(),
        _payments = paymentsRepository ?? PosPaymentsRepository(),
        _inventory = inventoryRepository ?? InventoryRepository(),
        _accessOverride = accessOverride;

  final PosRepository _pos;
  final InventoryRepository _inventory;
  final PosPaymentsRepository _payments;
  final PosAccess? _accessOverride;

  final Rx<PosAccess> access = PosAccess.cashier.obs;
  final RxBool loading = true.obs;
  final RxBool failed = false.obs;

  /// The current shift (everyone).
  final Rx<PosSessionReportModel?> shift = Rx(null);

  /// Business numbers (manager / owner only). `pulseLocked` = the server refused (needs a manager PIN session): shown as a note, not an error.
  final Rx<PosDailyReportModel?> today = Rx(null);
  final Rx<PosRangeReportModel?> week = Rx(null);
  final RxBool pulseLocked = false.obs;
  final RxnInt lowStockCount = RxnInt();

  /// Business verification (KYB) status for digital payments — read-only, managers / owners only (null = not loaded / not allowed).
  final Rxn<PosKybStatus> kyb = Rxn<PosKybStatus>();

  /// Digital (Raast) payments a manager has to look at: paid after expiry, paid but no sale, amount mismatch, failed refund.
  final RxInt digitalAttention = 0.obs;

  /// G2.6: the server's role-based business pulse (a cashier gets only their own shift). Null until loaded / when it can't be had.
  final Rxn<PosDashboard> dashboard = Rxn<PosDashboard>();

  final RxString employeeName = ''.obs;

  int get unresolvedSales => Get.isRegistered<PendingSaleSyncService>() ? Get.find<PendingSaleSyncService>().unresolvedCount.value : 0;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> _loadDashboard(String storeId) async {
    try {
      final j = await _pos.getDashboard(storeId);
      dashboard.value = j == null ? null : PosDashboard.fromJson(j);
    } catch (_) {
      dashboard.value = null; // the pulse is an extra: the rest of Home still shows
    }
  }

  Future<void> load() async {
    loading.value = true;
    failed.value = false;
    try {
      access.value = _accessOverride ?? await PosAccess.current();
      employeeName.value = (await AppPreferences.getPosEmployeeName()) ?? '';
      final storeId = await AppPreferences.getStoreId() ?? '';
      final sessionId = await AppPreferences.getPosSessionId();
      if (storeId.isEmpty) {
        failed.value = true;
        return;
      }

      final jobs = <Future<void>>[
        _loadDashboard(storeId),
        if (sessionId != null && sessionId.isNotEmpty) _pos.getSessionReport(sessionId).then((r) => shift.value = r),
      ];
      if (access.value.canManage) {
        final now = DateTime.now();
        String day(DateTime d) => d.toIso8601String().split('T').first;
        jobs.addAll([
          _pos.getDailyReport(storeId).then((r) {
            today.value = r;
            pulseLocked.value = r == null;
          }),
          _pos.getRangeReport(storeId, from: day(now.subtract(const Duration(days: 6))), to: day(now)).then((r) => week.value = r),
          _inventory.getLowStockSummary(storeId).then((r) => lowStockCount.value = r?.count),
          _payments.verification(storeId: storeId).then((r) => kyb.value = r),
          _payments.attention(storeId: storeId).then((r) => digitalAttention.value = r.items.length),
        ]);
      }
      await Future.wait(jobs.map((j) => j.catchError((_) {})));
      failed.value = shift.value == null && today.value == null && !pulseLocked.value && (sessionId != null && sessionId.isNotEmpty);
    } catch (e) {
      debugPrint('❌ PosHomeTabController.load: $e');
      failed.value = true;
    } finally {
      loading.value = false;
    }
  }
}
