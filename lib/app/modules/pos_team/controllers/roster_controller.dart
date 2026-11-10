import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_team_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

/// The weekly roster (Monday to Sunday). Everyone may read it; the person's own shifts are highlighted. Managers add / edit / cancel shifts (online
/// only; the server refuses overlaps and a shift over 16 hours and warns about a 60-hour week). Offline the last week the till saw is shown READ ONLY
/// with "Last synced <time>".
class RosterController extends GetxController {
  RosterController({
    PosRepository? repository,
    TeamCache? cache,
    String? storeId,
    Future<String?> Function()? employeeIdProvider,
    DateTime Function()? clock,
    Future<Map<String, String>> Function()? locationNames,
  }) : _repo = repository ?? PosRepository(),
       _cache = cache ?? TeamCache.instance,
       _storeIdOverride = storeId,
       _employeeId = employeeIdProvider ?? teamEmployeeId,
       _clock = clock ?? DateTime.now,
       _locationNames = locationNames;
  final PosRepository _repo;
  final TeamCache _cache;
  final String? _storeIdOverride;
  final Future<String?> Function() _employeeId;
  final DateTime Function() _clock;
  final Future<Map<String, String>> Function()? _locationNames;

  final RxList<RosterShift> shifts = <RosterShift>[].obs;
  final Rx<DateTime> weekStart = DateTime.now().obs;
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxnString myId = RxnString();
  final RxBool canManageHint = false.obs;
  final RxMap<String, String> locations = <String, String>{}.obs;

  /// set when the week on screen is the remembered copy (read only)
  final Rxn<DateTime> asOf = Rxn<DateTime>();
  final RxBool needsInternet = false.obs;
  final RxnString notice = RxnString();
  final RxnString actionError = RxnString();
  Worker? _online;

  bool get readOnly => asOf.value != null;
  bool get canEdit => canManageHint.value && !readOnly && teamOnline();
  DateTime get weekEnd => weekStart.value.add(const Duration(days: 7));

  /// the seven days of the week on screen, Monday first
  List<DateTime> get days => [for (var i = 0; i < 7; i++) DateTime(weekStart.value.year, weekStart.value.month, weekStart.value.day + i)];

  List<RosterShift> shiftsOn(DateTime day) => [
    for (final s in shifts)
      if (s.startAt.year == day.year && s.startAt.month == day.month && s.startAt.day == day.day) s,
  ]..sort((a, b) => a.startAt.compareTo(b.startAt));

  bool isMine(RosterShift s) => myId.value != null && s.employeeId == myId.value;

  @override
  void onInit() {
    super.onInit();
    weekStart.value = teamWeekStart(_clock());
    teamGuessCanManage().then((v) => canManageHint.value = v);
    _employeeId().then((v) => myId.value = v);
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

  void previousWeek() => _goto(weekStart.value.subtract(const Duration(days: 7)));
  void nextWeek() => _goto(weekStart.value.add(const Duration(days: 7)));
  void thisWeek() => _goto(teamWeekStart(_clock()));
  void _goto(DateTime d) {
    weekStart.value = DateTime(d.year, d.month, d.day);
    load();
  }

  Future<void> load() async {
    error.value = null;
    needsInternet.value = false;
    loading.value = true;
    final sid = await teamStoreId(_storeIdOverride);
    final key = teamWeekKey(weekStart.value);
    if (_locationNames != null && locations.isEmpty) {
      try {
        locations.assignAll(await _locationNames());
      } catch (_) {}
    }
    final List<RosterShift>? r = teamOnline() ? await _repo.getRoster(sid, from: weekStart.value, to: weekEnd) : null;
    if (r != null) {
      shifts.assignAll(r);
      asOf.value = null;
      await _cache.saveRoster(sid, key, r);
    } else if (!teamOnline() || _repo.lastErrorCode == null) {
      final c = await _cache.loadRoster(sid, key);
      if (c != null) {
        shifts.assignAll(c.shifts);
        asOf.value = c.asOf;
      } else {
        shifts.clear();
        asOf.value = null;
        needsInternet.value = true;
      }
    } else {
      shifts.clear();
      asOf.value = null;
      error.value = teamErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the roster. Try again.');
    }
    loading.value = false;
  }

  /// A shift was saved: show it at once (replacing the one it edits) and say what the server warned about.
  void applySaved(RosterShift s) {
    shifts.removeWhere((x) => x.id == s.id);
    if (s.startAt.isBefore(weekEnd) && !s.startAt.isBefore(weekStart.value)) shifts.add(s);
    notice.value = s.warnings.isEmpty ? null : s.warnings.map(teamWarningMessage).join(' ');
  }

  Future<bool> cancel(RosterShift s) async {
    actionError.value = null;
    if (!teamOnline()) {
      actionError.value = 'Needs internet.';
      return false;
    }
    final r = await _repo.cancelRosterShift(await teamStoreId(_storeIdOverride), s.id);
    if (!r.success) {
      actionError.value = teamErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
      return false;
    }
    shifts.removeWhere((x) => x.id == s.id);
    return true;
  }
}
