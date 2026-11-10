import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/team_report_pdf.dart';

enum ReportPeriod {
  week('7 days'),
  month('30 days'),
  thisMonth('This month'),
  custom('Pick dates');

  const ReportPeriod(this.label);
  final String label;
}

/// The attendance report: per person and period, hours worked (h:mm), days, breaks, late arrivals against the roster (with the server's grace), missing
/// clock-outs, corrections and rostered vs worked. A cashier gets only themself. Shares an A4 PDF. Online only.
class TeamReportController extends GetxController {
  TeamReportController({
    PosRepository? repository,
    String? storeId,
    DateTime Function()? clock,
    int Function()? tzOffsetMinutes,
    Future<void> Function(ShareParams)? share,
    Future<String?> Function()? storeName,
  }) : _repo = repository ?? PosRepository(),
       _storeIdOverride = storeId,
       _clock = clock ?? DateTime.now,
       _tz = tzOffsetMinutes ?? (() => -DateTime.now().timeZoneOffset.inMinutes),
       _share = share ?? ((p) async => SharePlus.instance.share(p)),
       _storeName = storeName ?? AppPreferences.getStoreName;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;
  final int Function() _tz;
  final Future<void> Function(ShareParams) _share;
  final Future<String?> Function() _storeName;

  final Rxn<TeamReport> report = Rxn<TeamReport>();
  final Rx<ReportPeriod> period = ReportPeriod.week.obs;
  final Rxn<DateTime> customFrom = Rxn<DateTime>();
  final Rxn<DateTime> customTo = Rxn<DateTime>(); // inclusive day
  final RxnString personId = RxnString();
  final RxList<PosEmployeeModel> people = <PosEmployeeModel>[].obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxBool canManageHint = false.obs;
  Worker? _online;

  /// [from] inclusive, [to] exclusive (local midnights)
  (DateTime, DateTime) get range {
    final n = _clock();
    final today = DateTime(n.year, n.month, n.day);
    final tomorrow = today.add(const Duration(days: 1));
    return switch (period.value) {
      ReportPeriod.week => (today.subtract(const Duration(days: 6)), tomorrow),
      ReportPeriod.month => (today.subtract(const Duration(days: 29)), tomorrow),
      ReportPeriod.thisMonth => (DateTime(n.year, n.month, 1), tomorrow),
      ReportPeriod.custom => (customFrom.value ?? today, (customTo.value ?? today).add(const Duration(days: 1))),
    };
  }

  /// the tz offset sent to the server (minutes BEHIND UTC, the JavaScript convention: UTC+5 is -300)
  int get tzOffsetMinutes => _tz();

  @override
  void onInit() {
    super.onInit();
    teamGuessCanManage().then((v) {
      canManageHint.value = v;
      if (v) _loadPeople();
    });
    load();
    _online = ever<bool>(teamOnlineRx(), (on) {
      if (on && report.value == null) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> _loadPeople() async {
    try {
      people.assignAll(await _repo.getEmployees(await teamStoreId(_storeIdOverride)));
    } catch (_) {}
  }

  void setPeriod(ReportPeriod p) {
    period.value = p;
    if (p != ReportPeriod.custom) load();
  }

  void setCustom(DateTime from, DateTime to) {
    customFrom.value = DateTime(from.year, from.month, from.day);
    customTo.value = DateTime(to.year, to.month, to.day);
    period.value = ReportPeriod.custom;
    load();
  }

  void setPerson(String? id) {
    personId.value = id;
    load();
  }

  Future<void> load() async {
    error.value = null;
    if (!teamOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final (from, to) = range;
    final r = await _repo.getTeamReport(await teamStoreId(_storeIdOverride), from: from, to: to, employeeId: personId.value, tzOffsetMinutes: tzOffsetMinutes);
    if (r == null) {
      report.value = null;
      error.value = teamErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the report. Try again.');
    } else {
      report.value = r;
    }
    loading.value = false;
  }

  Future<void> sharePdf() async {
    final r = report.value;
    if (r == null || busy.value) return;
    busy.value = true;
    error.value = null;
    try {
      final (from, to) = range;
      final bytes = await TeamReportPdf.build(r, from: from, to: to.subtract(const Duration(days: 1)), storeName: await _storeName(), printedAt: _clock());
      String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      await _share(
        ShareParams(
          files: [XFile.fromData(bytes, name: 'attendance-${d(from)}-to-${d(to.subtract(const Duration(days: 1)))}.pdf', mimeType: 'application/pdf')],
          subject: 'Attendance report ${d(from)} to ${d(to.subtract(const Duration(days: 1)))}',
        ),
      );
    } catch (_) {
      error.value = 'Could not share the report.';
    } finally {
      busy.value = false;
    }
  }
}
