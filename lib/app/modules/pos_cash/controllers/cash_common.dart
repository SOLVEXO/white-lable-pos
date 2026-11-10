import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_cash_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Shared helpers of the G3.5 cash controllers. Connectivity, the role guess and the approval type are the same ones the supply (G3.4) screens use.
Future<String> cashStoreId(String? override) => invStoreId(override);
RxBool cashOnlineRx() => supplyOnlineRx();
bool cashOnline() => supplyOnline();
Future<bool> cashGuessCanManage() => supplyGuessCanManage();

typedef CashApprovalRequester = SupplyApprovalRequester;

/// The offline queue of cash requests, when the app registered one (tests and tills without it simply have none).
PendingCashSyncService? cashQueue() => Get.isRegistered<PendingCashSyncService>() ? Get.find<PendingCashSyncService>() : null;

/// The open shift's session id, the same source the G3.4 pay sheet and the rest of the till use.
Future<String?> cashOpenSessionId() => AppPreferences.getPosSessionId();

/// The PIN-session token of the signed-in employee (kept with a queued request so it replays as them).
Future<String?> cashEmployeeToken() => AppPreferences.getPosEmployeeToken();

/// The categories / currency from the server, else the last remembered answer (null when neither exists).
Future<CashConfig?> loadCashConfig(PosRepository repo, CashConfigCache cache, String storeId) async {
  CashConfig? c;
  if (cashOnline()) {
    c = await repo.getCashConfig(storeId);
    if (c != null) await cache.save(storeId, c);
  }
  return c ?? await cache.load(storeId);
}
