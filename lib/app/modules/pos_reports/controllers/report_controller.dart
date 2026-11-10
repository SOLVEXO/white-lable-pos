import 'dart:typed_data';

import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/report_export.dart';

/// One of the eight G4.1 reports: the date strip (store days), "compare with the previous period" where the server offers it, the register and
/// cashier filters for managers, and the CSV / PDF export. Online only; the server decides who may see what (a cashier only gets "My sales").
class ReportController extends GetxController {
  ReportController({
    required this.kind,
    PosRepository? repository,
    String? storeId,
    DateTime Function()? clock,
    Future<void> Function(ShareParams)? share,
    Future<String?> Function()? storeName,
    String? employeeId,
    ReportRange initialRange = ReportRange.last7,
    bool? canManage,
  }) : _repo = repository ?? PosRepository(),
       _storeIdOverride = storeId,
       _clock = clock ?? DateTime.now,
       _share = share ?? ((p) async => SharePlus.instance.share(p)),
       _storeName = storeName ?? AppPreferences.getStoreName,
       _canManageOverride = canManage {
    range.value = initialRange;
    this.employeeId.value = employeeId;
  }

  final ReportKind kind;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;
  final Future<void> Function(ShareParams) _share;
  final Future<String?> Function() _storeName;
  final bool? _canManageOverride;

  final Rxn<BizReport> report = Rxn<BizReport>();
  final Rx<ReportRange> range = ReportRange.last7.obs;
  final Rxn<DateTime> customFrom = Rxn<DateTime>();
  final Rxn<DateTime> customTo = Rxn<DateTime>();
  final RxBool compare = false.obs;
  final RxnString registerId = RxnString();
  final RxnString employeeId = RxnString();

  /// products only: net | qty | margin (the server sorts)
  final RxString sort = 'net'.obs;

  /// sales with "compare": the previous period's days (the dashed line), sent by the server with the report
  final RxList<DayPoint> previousByDay = <DayPoint>[].obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString exportError = RxnString();
  final RxBool canManage = false.obs;
  final RxList<PosEmployeeModel> people = <PosEmployeeModel>[].obs;
  final RxList<StoreRegister> registers = <StoreRegister>[].obs;

  /// the store's today, `YYYY-MM-DD` (from the time-zone endpoint)
  final RxnString today = RxnString();
  Worker? _online;
  int _ticket = 0;

  /// the server returns a previous-period block for these
  bool get supportsCompare => kind == ReportKind.sales || kind == ReportKind.profit;

  /// first / last store day of the current selection
  (DateTime, DateTime) get days => range.value.days(parseDayKey(today.value) ?? _clock(), customFrom: customFrom.value, customTo: customTo.value);

  ReportQuery get query {
    final (a, b) = days;
    return ReportQuery(from: dayKey(a), to: dayKey(b), compare: supportsCompare && compare.value, registerId: registerId.value, employeeId: employeeId.value);
  }

  @override
  void onInit() {
    super.onInit();
    _init();
    _online = ever<bool>(reportsOnlineRx(), (on) {
      if (on && report.value == null) load();
    });
  }

  Future<void> _init() async {
    canManage.value = _canManageOverride ?? await reportsGuessCanManage();
    await load();
    if (canManage.value) _loadFilters();
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> _loadFilters() async {
    try {
      final sid = await reportsStoreId(_storeIdOverride);
      people.assignAll(await _repo.getEmployees(sid));
      registers.assignAll(await _repo.listRegisters(sid));
    } catch (_) {
      /* the filters are a convenience */
    }
  }

  void setRange(ReportRange r) {
    range.value = r;
    load();
  }

  void setCustom(DateTime from, DateTime to) {
    customFrom.value = DateTime(from.year, from.month, from.day);
    customTo.value = DateTime(to.year, to.month, to.day);
    range.value = ReportRange.custom;
    load();
  }

  void setCompare(bool v) {
    compare.value = v;
    load();
  }

  void setRegister(String? id) {
    registerId.value = id;
    load();
  }

  void setEmployee(String? id) {
    employeeId.value = id;
    load();
  }

  void setSort(String s) {
    if (sort.value == s) return;
    sort.value = s;
    load();
  }

  Future<void> load() async {
    final ticket = ++_ticket;
    error.value = null;
    if (!reportsOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final sid = await reportsStoreId(_storeIdOverride);
    today.value ??= await StoreDay.today(_repo, sid, _clock());
    final r = await _repo.getBizReport(sid, kind, query, sort: kind == ReportKind.products ? sort.value : null, limit: kind == ReportKind.products ? 100 : null);
    if (ticket != _ticket) return; // a newer selection was asked for meanwhile
    if (r == null) {
      report.value = null;
      error.value = reportErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the report. Try again.');
    } else {
      report.value = r;
    }
    loading.value = false;
    previousByDay.assignAll(r is SalesReport ? r.previousByDay : const <DayPoint>[]);
  }

  String get _fileBase {
    final r = report.value!;
    return '${kind.path}-${r.head.from}${r.head.to == r.head.from ? '' : '-to-${r.head.to}'}';
  }

  Future<void> shareCsv() => _export('csv', 'text/csv', (r) async => ReportCsv.bytes(reportTable(r), exponent: r.head.cur?.exponent ?? 2));

  Future<void> sharePdf() => _export('pdf', 'application/pdf', (r) async => ReportPdf.build(reportTable(r), r.head, storeName: await _storeName(), printedAt: _clock()));

  Future<void> _export(String ext, String mime, Future<Uint8List> Function(BizReport) make) async {
    final r = report.value;
    if (r == null || busy.value) return;
    busy.value = true;
    exportError.value = null;
    try {
      final name = '$_fileBase.$ext';
      await _share(
        ShareParams(
          files: [XFile.fromData(await make(r), name: name, mimeType: mime)],
          fileNameOverrides: [name],
          subject: '${kind.label} report ${r.head.from} to ${r.head.to}',
        ),
      );
    } catch (_) {
      exportError.value = 'Could not export the report.';
    } finally {
      busy.value = false;
    }
  }
}
