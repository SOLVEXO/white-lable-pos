import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';

/// Shared helpers of the G4 report screens (connectivity and the role guess are the ones every other module uses; the server enforces every rule).
Future<String> reportsStoreId(String? override) => invStoreId(override);
RxBool reportsOnlineRx() => supplyOnlineRx();
bool reportsOnline() => supplyOnline();
Future<bool> reportsGuessCanManage() => supplyGuessCanManage();

/// The store's zone and today's STORE date, read from the server once and kept for 10 minutes (the device's own date can differ from the store's).
class StoreDay {
  static StoreTimeZone? _zone;
  static DateTime? _at;

  static StoreTimeZone? get cached => _zone;
  static void remember(StoreTimeZone z, DateTime now) {
    _zone = z;
    _at = now;
  }

  static void forget() {
    _zone = null;
    _at = null;
  }

  /// today's store date as `YYYY-MM-DD`; falls back to the device's date only when the server could not be asked
  static Future<String> today(PosRepository repo, String storeId, DateTime now) async {
    if (_zone != null && _at != null && now.difference(_at!).inMinutes.abs() < 10) return _zone!.today;
    final z = await repo.getStoreTimeZone(storeId);
    if (z != null) {
      remember(z, now);
      return z.today;
    }
    return dayKey(now);
  }
}

/// The date strip of every report.
enum ReportRange {
  today('Today'),
  yesterday('Yesterday'),
  thisWeek('This week'),
  last7('Last 7 days'),
  thisMonth('This month'),
  last30('Last 30 days'),
  custom('Custom');

  const ReportRange(this.label);
  final String label;

  /// first and last STORE day (inclusive) given the store's [today]
  (DateTime, DateTime) days(DateTime today, {DateTime? customFrom, DateTime? customTo}) {
    final t = DateTime(today.year, today.month, today.day);
    DateTime back(int n) => DateTime(t.year, t.month, t.day - n);
    return switch (this) {
      ReportRange.today => (t, t),
      ReportRange.yesterday => (back(1), back(1)),
      ReportRange.thisWeek => (back(t.weekday - DateTime.monday), t),
      ReportRange.last7 => (back(6), t),
      ReportRange.thisMonth => (DateTime(t.year, t.month, 1), t),
      ReportRange.last30 => (back(29), t),
      ReportRange.custom => (customFrom ?? t, customTo ?? customFrom ?? t),
    };
  }
}
