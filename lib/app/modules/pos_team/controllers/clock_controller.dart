import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/local/pos_team_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

enum ClockOutcome { done, queued }

/// The clock: who is clocked in, on a break, since when; Clock in / Start break / End break / Clock out; today's punches and my next shifts.
/// Shared by the clock screen, the Home card and the hub badge, so it is registered PERMANENT by the app (and read with `Get.find`).
///
///  * The signed-in PIN session identifies the person; the server decides ("EMPLOYEE_REQUIRED" with no PIN). There is no quick re-authentication
///    in the app's PIN login (it replaces the whole session), so the clock always acts for whoever is signed in; the screen says who.
///  * **Offline a clock event is always accepted**: it is queued with its request id and the time the person tapped (`deviceAt`), shown as "Waiting
///    to sync", and sent in order exactly once later. The state shown is DERIVED: the last server state with the queued events applied, so the
///    buttons make sense offline. Obvious double taps are refused locally; the server stays the authority (it records a late event as it happened
///    and flags anything odd for a manager instead of refusing it).
class TeamClockController extends GetxController {
  TeamClockController({
    PosRepository? repository,
    TeamCache? cache,
    PendingTeamSyncService? queue,
    String? storeId,
    Future<String?> Function()? employeeIdProvider,
    Future<String?> Function()? employeeNameProvider,
    Future<String?> Function()? employeeTokenProvider,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  }) : _repo = repository ?? PosRepository(),
       _cache = cache ?? TeamCache.instance,
       _queueOverride = queue,
       _storeIdOverride = storeId,
       _employeeId = employeeIdProvider ?? teamEmployeeId,
       _employeeName = employeeNameProvider ?? teamEmployeeName,
       _employeeToken = employeeTokenProvider ?? teamEmployeeToken,
       _newId = requestIdFactory ?? newTeamRequestId,
       _clock = clock ?? DateTime.now;

  final PosRepository _repo;
  final TeamCache _cache;
  final PendingTeamSyncService? _queueOverride;
  final String? _storeIdOverride;
  final Future<String?> Function() _employeeId, _employeeName, _employeeToken;
  final String Function() _newId;
  final DateTime Function() _clock;
  PendingTeamSyncService? get _queue => _queueOverride ?? teamQueue();

  final Rxn<TeamMe> me = Rxn<TeamMe>();
  final Rx<ClockState> serverState = const ClockState().obs;
  final RxString employeeId = ''.obs;
  final RxString employeeName = ''.obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxnString actionError = RxnString();
  final RxnString notice = RxnString();

  /// true when there is no PIN-signed-in person (an owner session): the screen asks for a PIN login
  final RxBool needsPin = false.obs;
  final RxList<AttendanceRecord> today = <AttendanceRecord>[].obs;
  final RxInt anomalyCount = 0.obs;
  final RxBool canManageHint = false.obs;
  final RxInt version = 0.obs; // bumped whenever the derived state may have changed (the queue is a plain list)
  Worker? _online, _tick, _items;

  bool get isOffline => !teamOnline();

  /// The queued events of this person that have not reached the server yet, oldest first.
  List<PendingClockRecord> get waiting {
    version.value;
    final q = _queue;
    return q == null || employeeId.value.isEmpty ? const [] : q.pendingFor(employeeId.value);
  }

  /// The state to show and to enable buttons from: the last server state with the waiting events applied in order.
  ClockState get state {
    version.value;
    var s = serverState.value;
    for (final e in waiting) {
      s = s.after(e.action, e.deviceAt);
    }
    return s;
  }

  bool canDo(String action) => !busy.value && employeeId.value.isNotEmpty && state.allows(action);

  /// "9:00 - 17:00 today" / "tomorrow": the next rostered shift that starts today or tomorrow (for the Home card), else null.
  RosterShift? get nextShiftSoon {
    final now = _clock();
    final today0 = DateTime(now.year, now.month, now.day);
    final limit = today0.add(const Duration(days: 2));
    for (final s in me.value?.nextShifts ?? const <RosterShift>[]) {
      if (s.endAt.isAfter(now) && s.startAt.isBefore(limit)) return s;
    }
    return null;
  }

  String dayWord(DateTime d) {
    final now = _clock();
    final t = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    return day == t ? 'today' : (day == t.add(const Duration(days: 1)) ? 'tomorrow' : teamDay(d));
  }

  @override
  void onInit() {
    super.onInit();
    teamGuessCanManage().then((v) => canManageHint.value = v);
    load();
    _online = ever<bool>(teamOnlineRx(), (on) {
      if (on) load();
    });
    final q = _queue;
    if (q != null) {
      _tick = ever<int>(q.syncedTick, (_) => load());
      _items = ever<List<PendingClockRecord>>(q.items, (_) => version.value++);
    }
  }

  @override
  void onClose() {
    _online?.dispose();
    _tick?.dispose();
    _items?.dispose();
    super.onClose();
  }

  /// Loads from the server, or (offline) from what the till remembers.
  Future<void> load() async {
    error.value = null;
    needsPin.value = false;
    final id = await _employeeId() ?? '';
    employeeId.value = id;
    employeeName.value = await _employeeName() ?? '';
    final sid = await teamStoreId(_storeIdOverride);
    if (id.isEmpty) {
      needsPin.value = true;
      me.value = null;
      loading.value = false;
      return;
    }
    if (teamOnline()) {
      final m = await _repo.getTeamMe(sid);
      if (m != null) {
        me.value = m;
        serverState.value = m.state;
        await _cache.saveMe(sid, m);
        await _loadToday(sid, id);
        _refreshAnomalies(sid);
      } else if (_repo.lastErrorCode == 'EMPLOYEE_REQUIRED') {
        needsPin.value = true;
      } else if (_repo.lastErrorCode == null) {
        await _fromCache(sid, id); // no answer at all: use what is remembered
      } else {
        error.value = teamErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the clock. Try again.');
      }
    } else {
      await _fromCache(sid, id);
    }
    version.value++;
    loading.value = false;
  }

  Future<void> _fromCache(String sid, String id) async {
    final c = await _cache.loadMe(sid, id);
    if (c != null) {
      me.value = c;
      serverState.value = c.state;
    }
  }

  Future<void> _loadToday(String sid, String id) async {
    final n = _clock();
    final from = DateTime(n.year, n.month, n.day);
    final r = await _repo.getAttendanceRecords(sid, from: from, to: from.add(const Duration(days: 1)), employeeId: id);
    if (r != null) today.assignAll(r.where((x) => !x.isVoided));
  }

  Future<void> _refreshAnomalies(String sid) async {
    if (!canManageHint.value) return;
    try {
      final a = await _repo.getAttendanceAnomalies(sid);
      if (a != null) anomalyCount.value = a.length;
    } catch (_) {
      /* a count is a convenience */
    }
  }

  /// One tap on a clock button. Returns how it ended (null = not done: see [actionError]).
  // ── G5.4: clocking someone else ─────────────────────────────────────────────────────────────────────────────────────────────────────
  /// The team members this till may clock (everyone active but the signed-in person). Empty when the list cannot be loaded.
  Future<List<PosEmployeeModel>> teamMembers() async {
    final sid = await teamStoreId(_storeIdOverride);
    final all = await _repo.getTeamMembers(sid) ?? const <PosEmployeeModel>[];
    return all.where((e) => e.id != employeeId.value && e.status != 'inactive').toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Clock [member] in / out with [approverToken] (their own PIN session, or a manager's). ONLINE ONLY: offline nobody can check the PIN, so it is refused
  /// here and never queued. Returns null when done, otherwise the words to show.
  Future<String?> clockOnBehalf({required PosEmployeeModel member, required String action, required String approverToken}) async {
    if (isOffline) return 'Clocking someone else needs a connection — their PIN is checked by the server.';
    final sid = await teamStoreId(_storeIdOverride);
    busy.value = true;
    try {
      final r = await _repo.teamClock(sid, action: action, requestId: _newId(), deviceAt: _clock(), employeeToken: await _employeeToken(), onBehalfOf: member.id, approverToken: approverToken);
      if (r.success) {
        notice.value = '${member.name}: ${ClockAction.pastLabel(action).toLowerCase()}.';
        return null;
      }
      return switch (r.code) {
        'POS_APPROVAL_REQUIRED' => 'That PIN is not ${member.name}\'s or a manager\'s.',
        'ALREADY_CLOCKED_IN' => '${member.name} is already clocked in.',
        'NOT_CLOCKED_IN' => '${member.name} is not clocked in.',
        'EMPLOYEE_INACTIVE' => '${member.name} is deactivated.',
        _ => r.message ?? 'Could not clock ${member.name}.',
      };
    } finally {
      busy.value = false;
    }
  }

  Future<ClockOutcome?> perform(String action) async {
    if (busy.value) return null;
    actionError.value = null;
    notice.value = null;
    final id = employeeId.value;
    if (id.isEmpty) {
      actionError.value = teamErrorMessage('EMPLOYEE_REQUIRED');
      return null;
    }
    if (!state.allows(action)) {
      actionError.value = switch (action) {
        ClockAction.clockIn => teamErrorMessage('ALREADY_CLOCKED_IN'),
        ClockAction.breakStart => state.clockedIn ? teamErrorMessage('ALREADY_ON_BREAK') : teamErrorMessage('NOT_CLOCKED_IN'),
        ClockAction.breakEnd => state.clockedIn ? teamErrorMessage('NOT_ON_BREAK') : teamErrorMessage('NOT_CLOCKED_IN'),
        _ => teamErrorMessage('NOT_CLOCKED_IN'),
      };
      return null;
    }
    busy.value = true;
    try {
      final sid = await teamStoreId(_storeIdOverride);
      final requestId = _newId();
      final tappedAt = _clock();
      final token = await _employeeToken();
      if (teamOnline()) {
        final r = await _repo.teamClock(sid, action: action, requestId: requestId, deviceAt: tappedAt, employeeToken: null);
        if (r.success && r.result != null) {
          serverState.value = r.result!.state;
          version.value++;
          notice.value = '${ClockAction.pastLabel(action)} at ${teamTime(tappedAt)}.';
          unawaited(_afterClock(sid, id));
          return ClockOutcome.done;
        }
        if (!r.retryable) {
          actionError.value = teamErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
          if (const {'ALREADY_CLOCKED_IN', 'NOT_CLOCKED_IN', 'ALREADY_ON_BREAK', 'NOT_ON_BREAK'}.contains(r.code)) unawaited(load()); // the server disagrees: look again
          return null;
        }
        // no answer: the outcome is unknown, so queue it under the SAME request id (the server counts it once)
      }
      final q = _queue;
      if (q == null) {
        actionError.value = 'Needs internet.';
        return null;
      }
      await q.enqueue(storeId: sid, requestId: requestId, action: action, deviceAt: tappedAt, employeeId: id, employeeToken: token);
      version.value++;
      notice.value = '${ClockAction.pastLabel(action)} at ${teamTime(tappedAt)}. Saved on this device; it will sync when the till is online.';
      q.scheduleSync();
      return ClockOutcome.queued;
    } finally {
      busy.value = false;
    }
  }

  Future<void> _afterClock(String sid, String id) async {
    await _loadToday(sid, id);
    final m = me.value;
    if (m != null) await _cache.saveMe(sid, TeamMe(employeeId: m.employeeId, state: serverState.value, nextShifts: m.nextShifts, serverTime: m.serverTime));
  }
}
