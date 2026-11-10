import 'package:cryptography/cryptography.dart';
import 'package:solvexo_pos/app/data/local/pos_team_cache.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';

/// A LOCAL wall-clock time on 2026-11-09 as the ISO-UTC string the server sends — so the screens show the same hh:mm in every time zone (CI runs in UTC).
String _t(int h, int m, [int sec = 0]) => DateTime(2026, 11, 9, h, m, sec).toUtc().toIso8601String();

/// A team cache with a fixed key (no secure storage needed in tests).
TeamCache testTeamCache({DateTime Function()? clock}) => TeamCache(
  sealed: SealedText(cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 11)))),
  clock: clock,
);

RosterShift shift({String id = 'sh1', String employeeId = 'e1', String? name = 'Sam', DateTime? start, DateTime? end, String? location, String? note, List<String> warnings = const []}) => RosterShift(
  id: id,
  employeeId: employeeId,
  employeeName: name,
  startAt: start ?? DateTime(2026, 11, 9, 9),
  endAt: end ?? DateTime(2026, 11, 9, 17),
  locationId: location,
  note: note,
  warnings: warnings,
);

TeamMe me({bool clockedIn = false, bool onBreak = false, DateTime? since, List<RosterShift>? shifts, String employeeId = 'e1'}) => TeamMe(
  employeeId: employeeId,
  state: ClockState(clockedIn: clockedIn, onBreak: onBreak, since: since ?? (clockedIn ? DateTime(2026, 11, 9, 9, 2) : null), recordId: clockedIn ? 'rec1' : null),
  nextShifts: shifts ?? [shift()],
  serverTime: DateTime(2026, 11, 9, 9, 5),
);

AttendanceRecord record({
  String id = 'rec1',
  String employeeId = 'e1',
  String name = 'Sam',
  DateTime? clockIn,
  DateTime? clockOut,
  String status = 'closed',
  int worked = 465,
  int breaks = 30,
  bool corrected = false,
  List<String> flags = const [],
  bool noOut = false,
}) => AttendanceRecord(
  recordId: id,
  employeeId: employeeId,
  employeeName: name,
  clockInAt: clockIn ?? DateTime(2026, 11, 9, 9, 2),
  clockOutAt: noOut ? null : (clockOut ?? DateTime(2026, 11, 9, 17, 0)),
  status: noOut ? 'open' : status,
  workedMinutes: noOut ? 0 : worked,
  breakMinutes: breaks,
  breaks: [AttBreak(startAt: DateTime(2026, 11, 9, 12), endAt: DateTime(2026, 11, 9, 12, 30), minutes: 30)],
  corrected: corrected,
  flags: flags,
);

AttendanceAnomaly anomaly({String kind = 'missing_clock_out', String employeeId = 'e2', String name = 'Ali', String? recordId = 'rec9', String eventId = 'ev9', DateTime? at}) => AttendanceAnomaly(
  employeeId: employeeId,
  employeeName: name,
  kind: kind,
  recordId: recordId,
  eventId: eventId,
  at: at ?? DateTime(2026, 11, 8, 9),
  detail: kind == 'missing_clock_out' ? 'Clocked in more than 14 hours ago and never clocked out.' : 'Something happened.',
);

TeamReport report({bool withLate = true}) => TeamReport(
  from: DateTime(2026, 11, 3),
  to: DateTime(2026, 11, 10),
  lateGraceMinutes: 10,
  people: [
    ReportPerson(
      employeeId: 'e1',
      employeeName: 'Sam',
      daysWorked: 5,
      records: 5,
      workedMinutes: 2415,
      breakMinutes: 150,
      lateCount: withLate ? 2 : 0,
      lateMinutes: withLate ? 35 : 0,
      missingClockOuts: 0,
      corrections: 1,
      rosteredMinutes: 2400,
    ),
    const ReportPerson(
      employeeId: 'e2',
      employeeName: 'Ali',
      daysWorked: 3,
      records: 3,
      workedMinutes: 1445,
      breakMinutes: 90,
      lateCount: 0,
      lateMinutes: 0,
      missingClockOuts: 1,
      corrections: 0,
      rosteredMinutes: 1440,
    ),
  ],
  totalWorkedMinutes: 3860,
  totalLateCount: withLate ? 2 : 0,
  totalMissingClockOuts: 1,
);

PosEmployeeModel employee(String id, String name, {String role = 'cashier'}) =>
    PosEmployeeModel(id: id, storeId: 'st1', sellerId: 's', name: name, email: '$id@x.com', role: role, shiftIds: const [], status: 'active', createdAt: DateTime(2026));

Map<String, dynamic> meJson({bool clockedIn = true}) => {
  'employeeId': 'e1',
  'state': {'clockedIn': clockedIn, 'onBreak': false, 'since': _t(9, 2), 'recordId': 'rec1'},
  'nextShifts': [
    {'id': 'sh1', 'employeeId': 'e1', 'employeeName': 'Sam', 'locationId': null, 'startAt': _t(9, 0), 'endAt': _t(17, 0), 'note': null, 'status': 'active'},
  ],
  'serverTime': _t(9, 5),
};

Map<String, dynamic> clockResultJson({String type = 'clock_in', bool duplicate = false, bool clockedIn = true, bool onBreak = false}) => {
  'duplicate': duplicate,
  'event': {'id': 'ev1', 'type': type, 'at': _t(9, 2), 'deviceAt': _t(9, 2), 'serverAt': _t(9, 2, 1), 'flags': <String>[]},
  'state': {'clockedIn': clockedIn, 'onBreak': onBreak, 'since': _t(9, 2), 'recordId': 'rec1'},
};

ClockResult clockResult({String type = 'clock_in', bool clockedIn = true, bool onBreak = false, bool duplicate = false}) =>
    ClockResult.fromJson(clockResultJson(type: type, clockedIn: clockedIn, onBreak: onBreak, duplicate: duplicate));

/// A record's detail as the server sends it: a late-synced clock-out (device time 17:00, server time next morning) and one correction by a manager.
Map<String, dynamic> recordDetailJson({bool withCorrection = true}) => {
  'record': {
    'recordId': 'rec1',
    'employeeId': 'e1',
    'employeeName': 'Sam',
    'clockInAt': _t(9, 2),
    'clockOutAt': _t(17, 0),
    'status': 'closed',
    'workedMinutes': 465,
    'breakMinutes': 30,
    'breaks': <Map<String, dynamic>>[],
    'corrected': withCorrection,
    'flags': <String>[],
  },
  'punches': [
    {'id': 'p1', 'type': 'clock_in', 'at': _t(9, 2), 'deviceAt': _t(9, 2), 'serverAt': _t(9, 2, 1), 'flags': <String>[], 'deviceId': 'd1'},
    {'id': 'p2', 'type': 'break_start', 'at': _t(12, 0), 'deviceAt': _t(12, 0), 'serverAt': _t(12, 0), 'flags': <String>[], 'deviceId': 'd1'},
    {
      'id': 'p3',
      'type': 'clock_out',
      'at': _t(17, 0),
      'deviceAt': _t(17, 0),
      'serverAt': DateTime(2026, 11, 10, 8, 30).toUtc().toIso8601String(),
      'flags': ['late_sync'],
      'deviceId': null,
    },
  ],
  'corrections': withCorrection
      ? [
          {'id': 'c1', 'at': _t(18, 30), 'reason': 'forgot to clock out', 'byId': 'm1', 'byName': 'Mia Manager', 'clockInAt': null, 'clockOutAt': _t(17, 0), 'voided': false},
          {'id': 'c2', 'at': _t(18, 40), 'reason': null, 'byId': 'm1', 'byName': null, 'clockInAt': null, 'clockOutAt': null, 'voided': true},
        ]
      : <Map<String, dynamic>>[],
};

AttendanceRecordDetail recordDetail({bool withCorrection = true}) => AttendanceRecordDetail.fromJson(recordDetailJson(withCorrection: withCorrection));
