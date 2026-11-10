import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

enum AttendancePeriod {
  today('Today'),
  week('7 days'),
  month('30 days');

  const AttendancePeriod(this.label);
  final String label;

  /// [from] inclusive, [to] exclusive, local midnights.
  (DateTime, DateTime) range(DateTime now) {
    final start = DateTime(now.year, now.month, now.day);
    final to = start.add(const Duration(days: 1));
    return switch (this) {
      AttendancePeriod.today => (start, to),
      AttendancePeriod.week => (start.subtract(const Duration(days: 6)), to),
      AttendancePeriod.month => (start.subtract(const Duration(days: 29)), to),
    };
  }
}

/// The filters of the attendance list (applied on the till to what the server returned).
const attendanceFilters = <(String, String)>[('all', 'All'), ('open', 'Open'), ('closed', 'Closed'), ('voided', 'Voided'), ('corrected', 'Corrected'), ('flagged', 'Flagged')];

/// Attendance history. A cashier gets only their own (the server enforces); a manager sees everyone and may pick a person. Hours are the server's.
/// Online only (the server derives the records from the punches).
class AttendanceController extends GetxController {
  AttendanceController({PosRepository? repository, String? storeId, DateTime Function()? clock}) : _repo = repository ?? PosRepository(), _storeIdOverride = storeId, _clock = clock ?? DateTime.now;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;

  final RxList<AttendanceRecord> records = <AttendanceRecord>[].obs;
  final RxList<PosEmployeeModel> people = <PosEmployeeModel>[].obs;
  final RxnString personId = RxnString();
  final Rx<AttendancePeriod> period = AttendancePeriod.week.obs;
  final RxString filter = 'all'.obs;
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool canManageHint = false.obs;
  Worker? _online;

  bool get canManage => canManageHint.value || records.any((r) => r.employeeName != null && personId.value == null && records.map((e) => e.employeeId).toSet().length > 1);

  List<AttendanceRecord> get visible => records.where((r) {
    return switch (filter.value) {
      'open' => r.status == AttStatus.open,
      'closed' => r.status == AttStatus.closed,
      'voided' => r.isVoided,
      'corrected' => r.corrected,
      'flagged' => r.flags.isNotEmpty,
      _ => true,
    };
  }).toList();

  int get workedMinutes => records.where((r) => !r.isVoided).fold(0, (a, r) => a + r.workedMinutes);
  int get breakMinutes => records.where((r) => !r.isVoided).fold(0, (a, r) => a + r.breakMinutes);

  @override
  void onInit() {
    super.onInit();
    teamGuessCanManage().then((v) {
      canManageHint.value = v;
      if (v) _loadPeople();
    });
    load();
    _online = ever<bool>(teamOnlineRx(), (on) {
      if (on) load();
    });
  }

  @override
  void onClose() {
    _online?.dispose();
    super.onClose();
  }

  Future<void> _loadPeople() async {
    try {
      final l = await _repo.getEmployees(await teamStoreId(_storeIdOverride));
      people.assignAll(l);
    } catch (_) {
      /* the person filter is a convenience */
    }
  }

  void setPeriod(AttendancePeriod p) {
    if (period.value == p) return;
    period.value = p;
    load();
  }

  void setPerson(String? id) {
    personId.value = id;
    load();
  }

  void setFilter(String f) => filter.value = f;

  Future<void> load() async {
    error.value = null;
    if (!teamOnline()) {
      loading.value = false;
      return;
    }
    loading.value = true;
    final (from, to) = period.value.range(_clock());
    final r = await _repo.getAttendanceRecords(await teamStoreId(_storeIdOverride), from: from, to: to, employeeId: personId.value);
    if (r == null) {
      records.clear();
      error.value = teamErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the attendance. Try again.');
    } else {
      records.assignAll(r);
    }
    loading.value = false;
  }

  /// A correction succeeded: show the corrected record at once.
  void applyCorrected(AttendanceRecord r) {
    final i = records.indexWhere((x) => x.recordId == r.recordId);
    if (i >= 0) records[i] = r;
  }
}
