import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Shared helpers of the G3.6 team controllers. Connectivity and the role guess are the ones the supply and cash screens use.
Future<String> teamStoreId(String? override) => invStoreId(override);
RxBool teamOnlineRx() => supplyOnlineRx();
bool teamOnline() => supplyOnline();
Future<bool> teamGuessCanManage() => supplyGuessCanManage();

/// The offline queue of clock events, when the app registered one.
PendingTeamSyncService? teamQueue() => Get.isRegistered<PendingTeamSyncService>() ? Get.find<PendingTeamSyncService>() : null;

/// The signed-in team member (the PIN session). Attendance belongs to them; an owner session without a PIN has none.
Future<String?> teamEmployeeId() => AppPreferences.getPosEmployeeId();
Future<String?> teamEmployeeName() => AppPreferences.getPosEmployeeName();
Future<String?> teamEmployeeToken() => AppPreferences.getPosEmployeeToken();

String newTeamRequestId() => newSupplyRequestId();

/// Monday 00:00 (local) of the week that contains [d].
DateTime teamWeekStart(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// `2026-11-09`, the key of a roster week in the on-device copy.
String teamWeekKey(DateTime weekStart) => '${weekStart.year.toString().padLeft(4, '0')}-${weekStart.month.toString().padLeft(2, '0')}-${weekStart.day.toString().padLeft(2, '0')}';
