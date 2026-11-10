import 'package:intl/intl.dart';

/// G3.6 team: attendance (clock in / out / breaks), corrections, anomalies, the roster and the attendance report. No money anywhere. Times are the
/// server's ISO times parsed to local time; durations are whole minutes (shown as h:mm).
int? _int(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

DateTime? _date(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal();
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};
List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
List<String> _strings(dynamic v) => v is List ? [for (final e in v) '$e'] : const [];

/// Minutes as `h:mm` (95 -> `1:35`, 600 -> `10:00`, 5 -> `0:05`). A negative or missing value is `0:00`.
String formatHm(int? minutes) {
  final m = (minutes ?? 0) < 0 ? 0 : (minutes ?? 0);
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

String teamTime(DateTime? d) => d == null ? '--:--' : DateFormat('HH:mm').format(d.toLocal());
String teamDay(DateTime? d) => d == null ? '' : DateFormat('EEE d MMM').format(d.toLocal());
String teamDayTime(DateTime? d) => d == null ? '' : DateFormat('EEE d MMM, HH:mm').format(d.toLocal());

/// The four things a person can do at the clock.
abstract final class ClockAction {
  static const clockIn = 'clock_in', clockOut = 'clock_out', breakStart = 'break_start', breakEnd = 'break_end';
  static String label(String a) => switch (a) {
    clockIn => 'Clock in',
    clockOut => 'Clock out',
    breakStart => 'Start break',
    breakEnd => 'End break',
    _ => a,
  };
  static String pastLabel(String a) => switch (a) {
    clockIn => 'Clocked in',
    clockOut => 'Clocked out',
    breakStart => 'Break started',
    breakEnd => 'Break ended',
    _ => a,
  };
}

/// Is the person clocked in / on a break, since when. (`recordId` is the open attendance record.)
class ClockState {
  const ClockState({this.clockedIn = false, this.onBreak = false, this.since, this.recordId, this.breakAt});
  final bool clockedIn, onBreak;

  /// when the person clocked in (the server's `since`)
  final DateTime? since;
  final String? recordId;

  /// when the current break started (known only for a break made on this till; the server does not send it)
  final DateTime? breakAt;

  /// What a clock [action] would do to this state (used to follow the local queue while offline).
  ClockState after(String action, DateTime at) => switch (action) {
    ClockAction.clockIn => clockedIn ? this : ClockState(clockedIn: true, since: at),
    ClockAction.clockOut => const ClockState(),
    ClockAction.breakStart => clockedIn && !onBreak ? ClockState(clockedIn: true, onBreak: true, since: since, recordId: recordId, breakAt: at) : this,
    ClockAction.breakEnd => clockedIn && onBreak ? ClockState(clockedIn: true, since: since, recordId: recordId) : this,
    _ => this,
  };

  /// Would the server accept [action] from this state when the event is live? (The server stays the authority; this only keeps the buttons sensible.)
  bool allows(String action) => switch (action) {
    ClockAction.clockIn => !clockedIn,
    ClockAction.clockOut => clockedIn,
    ClockAction.breakStart => clockedIn && !onBreak,
    ClockAction.breakEnd => clockedIn && onBreak,
    _ => false,
  };

  factory ClockState.fromJson(Map<String, dynamic> j) => ClockState(clockedIn: j['clockedIn'] == true, onBreak: j['onBreak'] == true, since: _date(j['since']), recordId: _str(j['recordId']));
  Map<String, dynamic> toJson() => {'clockedIn': clockedIn, 'onBreak': onBreak, 'since': since?.toUtc().toIso8601String(), 'recordId': recordId};
}

class RosterShift {
  const RosterShift({
    required this.id,
    required this.employeeId,
    required this.startAt,
    required this.endAt,
    this.employeeName,
    this.locationId,
    this.note,
    this.status = 'active',
    this.warnings = const [],
  });
  final String id, employeeId, status;
  final String? employeeName, locationId, note;
  final DateTime startAt, endAt;

  /// non-blocking notices from the server on a save (e.g. OVER_60_HOURS_WEEK)
  final List<String> warnings;

  int get minutes => endAt.difference(startAt).inMinutes;
  String get range => '${teamTime(startAt)} - ${teamTime(endAt)}';

  factory RosterShift.fromJson(Map<String, dynamic> j) => RosterShift(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    employeeId: '${j['employeeId'] ?? ''}',
    employeeName: _str(j['employeeName']),
    locationId: _str(j['locationId']),
    startAt: _date(j['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    endAt: _date(j['endAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    note: _str(j['note']),
    status: j['status'] as String? ?? 'active',
    warnings: _strings(j['warnings']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'employeeId': employeeId,
    'employeeName': employeeName,
    'locationId': locationId,
    'startAt': startAt.toUtc().toIso8601String(),
    'endAt': endAt.toUtc().toIso8601String(),
    'note': note,
    'status': status,
  };
}

/// "Me": am I clocked in, my next shifts, and the server's clock (so the till can tell how far its own is off).
class TeamMe {
  const TeamMe({required this.employeeId, required this.state, this.nextShifts = const [], this.serverTime, this.asOf});
  final String employeeId;
  final ClockState state;
  final List<RosterShift> nextShifts;
  final DateTime? serverTime;

  /// set when this came from the on-device copy
  final DateTime? asOf;

  factory TeamMe.fromJson(Map<String, dynamic> j) => TeamMe(
    employeeId: '${j['employeeId'] ?? ''}',
    state: ClockState.fromJson(_map(j['state'])),
    nextShifts: [for (final s in _maps(j['nextShifts'])) RosterShift.fromJson(s)],
    serverTime: _date(j['serverTime']),
  );

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'state': state.toJson(),
    'nextShifts': [for (final s in nextShifts) s.toJson()],
    'serverTime': serverTime?.toUtc().toIso8601String(),
  };

  TeamMe withAsOf(DateTime t) => TeamMe(employeeId: employeeId, state: state, nextShifts: nextShifts, serverTime: serverTime, asOf: t);
}

class ClockResult {
  const ClockResult({required this.action, required this.state, this.duplicate = false, this.flags = const [], this.at});
  final String action;
  final ClockState state;
  final bool duplicate;
  final List<String> flags;
  final DateTime? at;
  factory ClockResult.fromJson(Map<String, dynamic> j) {
    final e = _map(j['event']);
    return ClockResult(action: e['type'] as String? ?? '', state: ClockState.fromJson(_map(j['state'])), duplicate: j['duplicate'] == true, flags: _strings(e['flags']), at: _date(e['at']));
  }
}

class AttBreak {
  const AttBreak({required this.startAt, this.endAt, this.minutes = 0});
  final DateTime startAt;
  final DateTime? endAt;
  final int minutes;
  factory AttBreak.fromJson(Map<String, dynamic> j) => AttBreak(startAt: _date(j['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0), endAt: _date(j['endAt']), minutes: _int(j['minutes']) ?? 0);
}

abstract final class AttStatus {
  static const open = 'open', closed = 'closed', voided = 'voided';
  static String label(String s) => switch (s) {
    open => 'Open',
    closed => 'Closed',
    voided => 'Voided',
    _ => s,
  };
}

/// One attendance record (a clock-in to its clock-out). A manager's correction is a new row on top of it: [corrected] says one applies.
class AttendanceRecord {
  const AttendanceRecord({
    required this.recordId,
    required this.employeeId,
    required this.clockInAt,
    required this.status,
    this.employeeName,
    this.clockOutAt,
    this.workedMinutes = 0,
    this.breakMinutes = 0,
    this.breaks = const [],
    this.corrected = false,
    this.flags = const [],
  });
  final String recordId, employeeId, status;
  final String? employeeName;
  final DateTime clockInAt;
  final DateTime? clockOutAt;
  final int workedMinutes, breakMinutes;
  final List<AttBreak> breaks;
  final bool corrected;
  final List<String> flags;

  bool get isOpen => status == AttStatus.open;
  bool get isVoided => status == AttStatus.voided;

  factory AttendanceRecord.fromJson(Map<String, dynamic> j) => AttendanceRecord(
    recordId: '${j['recordId'] ?? ''}',
    employeeId: '${j['employeeId'] ?? ''}',
    employeeName: _str(j['employeeName']),
    clockInAt: _date(j['clockInAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    clockOutAt: _date(j['clockOutAt']),
    status: j['status'] as String? ?? AttStatus.closed,
    workedMinutes: _int(j['workedMinutes']) ?? 0,
    breakMinutes: _int(j['breakMinutes']) ?? 0,
    breaks: [for (final b in _maps(j['breaks'])) AttBreak.fromJson(b)],
    corrected: j['corrected'] == true,
    flags: _strings(j['flags']),
  );
}

String attFlagLabel(String f) => switch (f) {
  'missing_clock_out' => 'Missing clock-out',
  'overlap' => 'Overlaps another record',
  'device_clock_ahead' => 'Device clock was ahead',
  'late_sync' => 'Synced late',
  _ => f.isEmpty ? '' : '${f[0].toUpperCase()}${f.substring(1).replaceAll('_', ' ')}',
};

/// Something a manager should look at (a missing clock-out, a double clock-in, an overlap, a device clock that was ahead, a late sync ...).
class AttendanceAnomaly {
  const AttendanceAnomaly({required this.employeeId, required this.kind, required this.detail, this.employeeName, this.recordId, this.eventId, this.at});
  final String employeeId, kind, detail;
  final String? employeeName, recordId, eventId;
  final DateTime? at;

  String get title => switch (kind) {
    'missing_clock_out' => 'Missing clock-out',
    'double_clock_in' => 'Clocked in twice',
    'overlap' => 'Overlapping records',
    'clock_out_without_clock_in' => 'Clock-out without a clock-in',
    'break_without_clock_in' => 'Break while not clocked in',
    'double_break_start' => 'Break started twice',
    'break_end_without_start' => 'Break end without a start',
    'out_before_in' => 'Clock-out before clock-in',
    'device_clock_ahead' => 'Device clock was ahead',
    'late_sync' => 'Recorded late (offline)',
    _ => attFlagLabel(kind),
  };

  /// a record exists to fix (so "Fix" is offered)
  bool get fixable => (recordId ?? '').isNotEmpty;
  bool get ackable => (eventId ?? '').isNotEmpty;

  factory AttendanceAnomaly.fromJson(Map<String, dynamic> j) => AttendanceAnomaly(
    employeeId: '${j['employeeId'] ?? ''}',
    employeeName: _str(j['employeeName']),
    kind: '${j['kind'] ?? ''}',
    recordId: _str(j['recordId']),
    eventId: _str(j['eventId']),
    at: _date(j['at']),
    detail: j['detail'] as String? ?? '',
  );
}

class ReportPerson {
  const ReportPerson({
    required this.employeeId,
    this.employeeName,
    this.daysWorked = 0,
    this.records = 0,
    this.workedMinutes = 0,
    this.breakMinutes = 0,
    this.lateCount = 0,
    this.lateMinutes = 0,
    this.missingClockOuts = 0,
    this.corrections = 0,
    this.rosteredMinutes = 0,
  });
  final String employeeId;
  final String? employeeName;
  final int daysWorked, records, workedMinutes, breakMinutes, lateCount, lateMinutes, missingClockOuts, corrections, rosteredMinutes;

  factory ReportPerson.fromJson(Map<String, dynamic> j) => ReportPerson(
    employeeId: '${j['employeeId'] ?? ''}',
    employeeName: _str(j['employeeName']),
    daysWorked: _int(j['daysWorked']) ?? 0,
    records: _int(j['records']) ?? 0,
    workedMinutes: _int(j['workedMinutes']) ?? 0,
    breakMinutes: _int(j['breakMinutes']) ?? 0,
    lateCount: _int(j['lateCount']) ?? 0,
    lateMinutes: _int(j['lateMinutes']) ?? 0,
    missingClockOuts: _int(j['missingClockOuts']) ?? 0,
    corrections: _int(j['corrections']) ?? 0,
    rosteredMinutes: _int(j['rosteredMinutes']) ?? 0,
  );
}

class TeamReport {
  const TeamReport({required this.people, this.from, this.to, this.lateGraceMinutes = 10, this.totalWorkedMinutes = 0, this.totalLateCount = 0, this.totalMissingClockOuts = 0});
  final List<ReportPerson> people;
  final DateTime? from, to;
  final int lateGraceMinutes, totalWorkedMinutes, totalLateCount, totalMissingClockOuts;

  factory TeamReport.fromJson(Map<String, dynamic> j) {
    final t = _map(j['totals']);
    return TeamReport(
      people: [for (final p in _maps(j['people'])) ReportPerson.fromJson(p)],
      from: _date(j['from']),
      to: _date(j['to']),
      lateGraceMinutes: _int(j['lateGraceMinutes']) ?? 10,
      totalWorkedMinutes: _int(t['workedMinutes']) ?? 0,
      totalLateCount: _int(t['lateCount']) ?? 0,
      totalMissingClockOuts: _int(t['missingClockOuts']) ?? 0,
    );
  }
}

/// Server error codes of the team endpoints in plain English (the server enforces; this only explains). [extra] is the rest of the error body
/// (a roster overlap names the shift it clashes with).
String teamErrorMessage(String? code, {String? fallback, Map<String, dynamic>? extra}) => switch (code) {
  'ALREADY_CLOCKED_IN' => 'You are already clocked in.',
  'NOT_CLOCKED_IN' => 'You are not clocked in.',
  'ALREADY_ON_BREAK' => 'You are already on a break.',
  'NOT_ON_BREAK' => 'You are not on a break.',
  'EMPLOYEE_REQUIRED' => 'Sign in with your PIN first. Attendance belongs to a team member, not to the owner account.',
  'INVALID_ACTION' => 'That is not something the clock can do.',
  'REQUEST_ID_REQUIRED' => 'Something went wrong with this request. Try again.',
  'REASON_REQUIRED' => 'Say why the attendance is being corrected.',
  'INVALID_CORRECTION' => 'Change at least one thing: a time, or void the record.',
  'INVALID_DATE' => 'That date or time is not valid (a corrected time cannot be in the future, and the clock-out must be after the clock-in).',
  'INVALID_RANGE' => 'The shift must end after it starts.',
  'RECORD_NOT_FOUND' => 'That attendance record was not found.',
  'ROSTER_OVERLAP' => _overlap(extra),
  'SHIFT_TOO_LONG' => 'A shift can be at most 16 hours.',
  'SHIFT_NOT_FOUND' => 'That shift was not found. It may have been cancelled.',
  'EMPLOYEE_NOT_FOUND' => 'That team member was not found.',
  'LOCATION_NOT_FOUND' => 'That location was not found.',
  'RANGE_REQUIRED' => 'Choose a period of at most 93 days.',
  'INVALID_ACK' => 'That problem cannot be acknowledged.',
  'POS_ACTION_FORBIDDEN' => 'Your role is not allowed to do this.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};

String _overlap(Map<String, dynamic>? extra) {
  final a = _date(extra?['conflictStartAt']);
  final b = _date(extra?['conflictEndAt']);
  if (a == null || b == null) return 'This person already has a shift at that time.';
  return 'This person already has a shift from ${teamTime(a)} to ${teamTime(b)} on ${teamDay(a)}.';
}

/// What a roster warning means.
String teamWarningMessage(String w) => switch (w) {
  'OVER_60_HOURS_WEEK' => 'Saved, but this person is now rostered for more than 60 hours this week.',
  _ => 'Saved with a notice: $w',
};
