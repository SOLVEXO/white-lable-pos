import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart' show dayKey, parseDayKey, reportErrorMessage;
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/utils/report_export.dart';

/// What the activity log can be narrowed to (the server filters by `targetType`).
const auditTypes = <String, String>{
  'sale': 'Sales & refunds',
  'session': 'Shifts',
  'cash': 'Cash',
  'employee': 'Team',
  'permission': 'Permissions',
  'settings': 'Settings',
  'inventory': 'Stock',
  'variant': 'Prices & products',
  'catalog': 'Catalog',
  'customer': 'Customers',
  'supply': 'Purchasing',
  'device': 'Devices',
  'audit': 'Integrity checks',
};

/// G4.3 activity log: store-day range, type and person filters, CSV export of what is shown, and the Integrity panel (the nightly seals recomputed
/// by the server: every sealed day either still matches, or names the parts that changed, or the chain is broken). Online only; the server enforces
/// who may read it.
class PosAuditLogController extends GetxController {
  PosAuditLogController({PosRepository? posRepository, String? storeId, DateTime Function()? clock, Future<void> Function(ShareParams)? share})
    : _repo = posRepository ?? PosRepository(),
      _storeIdOverride = storeId,
      _clock = clock ?? DateTime.now,
      _share = share ?? ((p) async => SharePlus.instance.share(p));

  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;
  final Future<void> Function(ShareParams) _share;

  final RxList<PosAuditLogModel> logs = <PosAuditLogModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isLoadingMore = false.obs;
  final RxnString error = RxnString();
  final RxInt total = 0.obs;

  final Rx<ReportRange> range = ReportRange.last7.obs;
  final Rxn<DateTime> customFrom = Rxn<DateTime>();
  final Rxn<DateTime> customTo = Rxn<DateTime>();
  final RxString today = ''.obs;
  final RxnString type = RxnString();
  final RxnString employeeId = RxnString();

  /// id → name, for the rows and the person filter
  final RxMap<String, String> people = <String, String>{}.obs;

  final Rxn<AuditVerify> integrity = Rxn<AuditVerify>();
  final RxBool checking = false.obs;
  final RxnString integrityError = RxnString();
  final RxBool exporting = false.obs;

  int _page = 1;
  bool _hasMore = false;
  bool get hasMore => _hasMore;
  int _ticket = 0;
  Worker? _online;

  (DateTime, DateTime) get days => range.value.days(parseDayKey(today.value) ?? _clock(), customFrom: customFrom.value, customTo: customTo.value);

  @override
  void onInit() {
    super.onInit();
    _start();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && logs.isEmpty) loadLogs();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> _start() async {
    final sid = await reportsStoreId(_storeIdOverride);
    today.value = await StoreDay.today(_repo, sid, _clock());
    await loadLogs();
    try {
      final team = await _repo.getEmployees(sid);
      people.assignAll({for (final e in team) e.id: e.name});
    } catch (_) {
      /* names are a nicety: ids stay */
    }
  }

  String nameOf(String? id) => id == null || id.isEmpty ? 'Owner / system' : (people[id] ?? 'Team member');

  Future<void> loadLogs() async {
    error.value = null;
    if (!reportsOnline()) {
      isLoading.value = false;
      return;
    }
    final ticket = ++_ticket;
    isLoading.value = true;
    final (a, b) = days;
    final r = await _repo.getAuditLogsFiltered(await reportsStoreId(_storeIdOverride), from: dayKey(a), to: dayKey(b), targetType: type.value, employeeId: employeeId.value);
    if (ticket != _ticket) return;
    if (r == null) {
      error.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the activity log. Try again.');
    } else {
      logs.assignAll(r.items);
      total.value = r.total;
      _page = 1;
      _hasMore = r.hasMore;
    }
    isLoading.value = false;
  }

  Future<void> loadMore() async {
    if (isLoadingMore.value || !_hasMore) return;
    isLoadingMore.value = true;
    final ticket = _ticket;
    final (a, b) = days;
    final r = await _repo.getAuditLogsFiltered(await reportsStoreId(_storeIdOverride), page: _page + 1, from: dayKey(a), to: dayKey(b), targetType: type.value, employeeId: employeeId.value);
    if (ticket == _ticket && r != null) {
      logs.addAll(r.items);
      _page++;
      _hasMore = r.hasMore;
    }
    isLoadingMore.value = false;
  }

  Future<void> refreshData() => loadLogs();

  void setRange(ReportRange r) {
    range.value = r;
    loadLogs();
  }

  void setCustom(DateTime from, DateTime to) {
    customFrom.value = from;
    customTo.value = to;
    range.value = ReportRange.custom;
    loadLogs();
  }

  void setType(String? t) {
    type.value = t;
    loadLogs();
  }

  void setEmployee(String? id) {
    employeeId.value = id;
    loadLogs();
  }

  /// Recompute the seals of the shown period on the server.
  Future<void> checkIntegrity() async {
    if (checking.value) return;
    integrityError.value = null;
    if (!reportsOnline()) {
      integrityError.value = 'The integrity check needs an internet connection.';
      return;
    }
    checking.value = true;
    try {
      final (a, b) = days;
      final r = await _repo.verifyAuditSeals(await reportsStoreId(_storeIdOverride), from: dayKey(a), to: dayKey(b));
      if (r == null) {
        integrityError.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not run the integrity check. Try again.');
      } else {
        integrity.value = r;
      }
    } finally {
      checking.value = false;
    }
  }

  ReportTable get table => ReportTable(
    title: 'Activity log',
    headers: const ['When', 'Who', 'What', 'Type', 'Target'],
    rows: [
      for (final l in logs)
        [RText(l.createdAt.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')), RText(nameOf(l.employeeId)), RText(l.actionLabel), RText(auditTypes[l.targetType] ?? (l.targetType ?? '')), RText(l.targetId ?? '')],
    ],
  );

  /// The rows on screen as a CSV through the share sheet (load more first for a longer file).
  Future<void> exportCsv() async {
    if (exporting.value || logs.isEmpty) return;
    exporting.value = true;
    try {
      final (a, b) = days;
      final Uint8List bytes = ReportCsv.bytes(table, exponent: 0);
      final name = 'activity-log_${dayKey(a)}_${dayKey(b)}.csv';
      await _share(ShareParams(files: [XFile.fromData(bytes, name: name, mimeType: 'text/csv')], fileNameOverrides: [name], subject: 'Activity log'));
    } finally {
      exporting.value = false;
    }
  }
}
