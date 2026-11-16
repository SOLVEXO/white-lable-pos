import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/server_capabilities.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// G6.3 — two extra "needs attention" counts for the Home dashboard that the Home controller does not load: fiscal documents the
/// authority has not accepted (failed / rejected) and expenses still waiting for a manager's decision. Both are reads of endpoints the
/// app already uses elsewhere (Integrations → fiscal issues, Cash → expenses), managers / owners only, never while offline, and the
/// fiscal one only when the backend lists `fiscalIssues` (an older backend has no such route). Any failure leaves the count at 0:
/// these rows are an extra, never an error on Home.
class DashboardAlertsController extends GetxController {
  DashboardAlertsController({PosRepository? repository, Future<PosAccess> Function()? access, Future<String?> Function()? storeId})
      : _repo = repository ?? PosRepository(),
        _access = access ?? PosAccess.current,
        _storeId = storeId ?? AppPreferences.getStoreId;

  final PosRepository _repo;
  final Future<PosAccess> Function() _access;
  final Future<String?> Function() _storeId;

  final RxInt fiscalProblems = 0.obs;
  final RxInt expensesToReview = 0.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    try {
      final online = !Get.isRegistered<NetworkStatusService>() || Get.find<NetworkStatusService>().isOnline.value;
      final a = await _access();
      final sid = await _storeId() ?? '';
      if (!online || !a.canManage || sid.isEmpty) return;
      await Future.wait([
        if (ServerCapabilities.has('fiscalIssues'))
          _repo.getFiscalIssues(sid).then((r) => fiscalProblems.value = r?.length ?? 0).catchError((_) => 0),
        _repo.getExpenses(sid, status: ExpenseStatus.recorded).then((r) => expensesToReview.value = r?.expenses.length ?? 0).catchError((_) => 0),
      ]);
    } catch (_) {/* an extra — Home never fails because of it */}
  }
}
