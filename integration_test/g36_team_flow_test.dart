// REAL end-to-end for G3.6 Team on the iOS simulator against the dev stack (real repositories, real API):
//   cashier clocks in → a second clock-in is refused (ALREADY_CLOCKED_IN) → the same request replayed is one event → break → clock out
//   events that reach the server late (the offline queue) keep their own times; a late double clock-in is RECORDED and shows up as an anomaly for the manager;
//   the manager acknowledges it, and corrects a record (reason required, a new record — nothing overwritten)
//   roster: manager plans a shift, an overlap is refused (ROSTER_OVERLAP), a cashier cannot edit it but sees it on Home (me.nextShifts)
//   report: hours worked for the person
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g36_team_flow_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    SoundUtil.enabled = false;
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'g36 team probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  String rid(String p) => '$p-${DateTime.now().microsecondsSinceEpoch}';
  DateTime ago(int minutes) => DateTime.now().subtract(Duration(minutes: minutes));

  testWidgets('G3.6 team: clocking (live + late/offline), anomalies, corrections, roster, report', (tester) async {
    var t = await till(cashierEmail, cashierPin);
    final me = t.employee!.id;

    // start clean: close anything a previous run left open
    var st = (await t.repo.getTeamMe(storeId))!;
    if (st.state.clockedIn) {
      if (st.state.onBreak) await t.repo.teamClock(storeId, action: 'break_end', requestId: rid('cl0'), deviceAt: DateTime.now());
      await t.repo.teamClock(storeId, action: 'clock_out', requestId: rid('cl1'), deviceAt: DateTime.now());
    }

    final startedAt = DateTime.now().subtract(const Duration(seconds: 5)); // (a previous aborted run may have left a record in the last minutes)
    // ── a · live clocking, strict ────────────────────────────────────────────────────────────────────────────────────────────
    expect((await t.repo.teamClock(storeId, action: 'clock_out', requestId: rid('x'), deviceAt: DateTime.now())).code, 'NOT_CLOCKED_IN');
    final inId = rid('in');
    final a = await t.repo.teamClock(storeId, action: 'clock_in', requestId: inId, deviceAt: DateTime.now());
    expect(a.success, isTrue, reason: 'clock in: ${a.message}');
    expect(a.result!.state.clockedIn, isTrue);
    expect((await t.repo.teamClock(storeId, action: 'clock_in', requestId: rid('in2'), deviceAt: DateTime.now())).code, 'ALREADY_CLOCKED_IN');
    final replay = await t.repo.teamClock(storeId, action: 'clock_in', requestId: inId, deviceAt: DateTime.now());
    expect(replay.success, isTrue, reason: 'a replay is answered (the same Idempotency-Key returns the original answer), never an error or a second event');
    expect((await t.repo.teamClock(storeId, action: 'break_start', requestId: rid('bs'), deviceAt: DateTime.now())).result!.state.onBreak, isTrue);
    expect((await t.repo.teamClock(storeId, action: 'break_end', requestId: rid('be'), deviceAt: DateTime.now())).result!.state.onBreak, isFalse);
    final out = await t.repo.teamClock(storeId, action: 'clock_out', requestId: rid('out'), deviceAt: DateTime.now());
    expect(out.result!.state.clockedIn, isFalse);
    final today = (await t.repo.getAttendanceRecords(storeId, from: ago(30), to: DateTime.now().add(const Duration(minutes: 5))))!.where((r) => r.employeeId == me && r.clockInAt.isAfter(startedAt)).toList();
    expect(today, hasLength(1), reason: 'in → replay → break → out is ONE record');
    print('a ok: live clocking is strict, replay is one event');

    // a device clock that is AHEAD of the server is flagged and the server time is used
    final ahead = await t.repo.teamClock(storeId, action: 'clock_in', requestId: rid('ahead'), deviceAt: DateTime.now().add(const Duration(minutes: 40)));
    expect(ahead.result!.flags, contains('device_clock_ahead'));
    await t.repo.teamClock(storeId, action: 'clock_out', requestId: rid('ahead-out'), deviceAt: DateTime.now());
    print('a2 ok: device clock ahead → flagged');

    // ── b · events that reach the server late (what the offline queue sends) ─────────────────────────────────────────────────
    final lateIn = await t.repo.teamClock(storeId, action: 'clock_in', requestId: rid('li'), deviceAt: ago(600));
    expect(lateIn.success, isTrue);
    final lateIn2 = await t.repo.teamClock(storeId, action: 'clock_in', requestId: rid('li2'), deviceAt: ago(540)); // a second tablet replays it
    expect(lateIn2.success, isTrue, reason: 'a late event is recorded, not refused: ${lateIn2.message}');
    final lateOut = await t.repo.teamClock(storeId, action: 'clock_out', requestId: rid('lo'), deviceAt: ago(120));
    expect(lateOut.success, isTrue);
    final mine = (await t.repo.getAttendanceRecords(storeId, from: ago(2 * 24 * 60), to: DateTime.now().add(const Duration(days: 1))))!;
    expect(mine.where((r) => r.employeeId == me), isNotEmpty);
    final longOne = mine.firstWhere((r) => r.workedMinutes >= 470 && r.workedMinutes <= 490, orElse: () => throw TestFailure('a ~8 h record (10 h ago → 2 h ago) must exist: ${mine.map((r) => r.workedMinutes)}'));
    print('b ok: the late events kept their own times (${longOne.workedMinutes} min)');
    await t.dispose();

    // ── c · the manager sees the anomaly, acknowledges it, and corrects a record ────────────────────────────────────────────────
    t = await till(managerEmail, managerPin);
    final anomalies = (await t.repo.getAttendanceAnomalies(storeId))!;
    final dbl = anomalies.where((x) => x.employeeId == me && x.kind == 'double_clock_in').toList();
    expect(dbl, isNotEmpty, reason: 'the double clock-in is flagged for a manager');
    final ack = await t.repo.ackAttendanceAnomaly(storeId, employeeId: me, eventId: dbl.first.eventId!, kind: 'double_clock_in', note: 'checked');
    expect(ack.success, isTrue, reason: 'ack: ${ack.message}');
    final after = (await t.repo.getAttendanceAnomalies(storeId))!;
    expect(after.where((x) => x.eventId == dbl.first.eventId && x.kind == 'double_clock_in'), isEmpty);
    expect((await t.repo.correctAttendance(storeId, employeeId: me, recordId: longOne.recordId, reason: '', clockInAt: ago(560))).success, isFalse, reason: 'a reason is required');
    final fixed = await t.repo.correctAttendance(storeId, employeeId: me, recordId: longOne.recordId, reason: 'arrived later', clockInAt: ago(560));
    expect(fixed.success, isTrue, reason: 'correct: ${fixed.message}');
    expect(fixed.record!.corrected, isTrue);
    expect(fixed.record!.workedMinutes, lessThan(longOne.workedMinutes));
    print('c ok: anomaly acknowledged; record corrected (${longOne.workedMinutes} → ${fixed.record!.workedMinutes} min)');

    // ── d · roster ───────────────────────────────────────────────────────────────────────────────────────────────────────────
    final day = DateTime.now().toUtc().add(const Duration(days: 5));
    final start = DateTime.utc(day.year, day.month, day.day, 9);
    final end = DateTime.utc(day.year, day.month, day.day, 17);
    final made = await t.repo.createRosterShift(storeId, employeeId: me, startAt: start, endAt: end, note: 'opening');
    expect(made.success || made.code == 'ROSTER_OVERLAP', isTrue, reason: 'shift: ${made.message}');
    final clash = await t.repo.createRosterShift(storeId, employeeId: me, startAt: start.add(const Duration(hours: 2)), endAt: end.add(const Duration(hours: 1)));
    expect(clash.code, 'ROSTER_OVERLAP');
    expect((await t.repo.createRosterShift(storeId, employeeId: me, startAt: start, endAt: start.add(const Duration(hours: 20)))).code, anyOf('SHIFT_TOO_LONG', 'ROSTER_OVERLAP'));
    print('d ok: roster created, overlap refused');
    await t.dispose();

    // ── e · the cashier sees their shift (Home), cannot edit the roster, sees only own report ────────────────────────────────
    t = await till(cashierEmail, cashierPin);
    final home = (await t.repo.getTeamMe(storeId))!;
    expect(home.nextShifts.any((s) => s.employeeId == me), isTrue, reason: 'the shift shows on Home for that person');
    final denied = await t.repo.createRosterShift(storeId, employeeId: me, startAt: start.add(const Duration(days: 1)), endAt: end.add(const Duration(days: 1)));
    expect(denied.code, 'POS_ACTION_FORBIDDEN');
    final rep = (await t.repo.getTeamReport(storeId, from: ago(3 * 24 * 60), to: DateTime.now().add(const Duration(days: 1))))!;
    expect(rep.people.map((p) => p.employeeId), [me], reason: 'a cashier sees only themself');
    expect(rep.people.single.workedMinutes, greaterThan(0));
    print('e ok: cashier read-only roster + own report (${rep.people.single.workedMinutes} min worked)');
    await t.dispose();
  });
}
