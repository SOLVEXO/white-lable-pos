import 'package:flutter/material.dart' show TimeOfDay;
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

/// Add or edit a shift (managers). Person, date, start and end time (an end at or before the start means the next day), an optional location and note.
/// The server refuses an overlap (the message names the clashing time) and a shift longer than 16 hours, and WARNS about a 60-hour week: a warning is
/// shown as a notice after the shift is saved, never as a block. Online only.
class ShiftController extends GetxController {
  ShiftController({this.existing, this.presetDay, PosRepository? repository, String? storeId, List<PosEmployeeModel>? people, Map<String, String>? locations})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _presetPeople = people,
      locations = (locations ?? const <String, String>{}).obs {
    final s = existing;
    if (s != null) {
      employeeId.value = s.employeeId;
      date.value = DateTime(s.startAt.year, s.startAt.month, s.startAt.day);
      start.value = TimeOfDay(hour: s.startAt.hour, minute: s.startAt.minute);
      end.value = TimeOfDay(hour: s.endAt.hour, minute: s.endAt.minute);
      locationId.value = s.locationId;
      note.value = s.note ?? '';
    } else {
      date.value = presetDay;
    }
  }
  final RosterShift? existing;
  final DateTime? presetDay;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final List<PosEmployeeModel>? _presetPeople;

  final RxList<PosEmployeeModel> people = <PosEmployeeModel>[].obs;
  final RxMap<String, String> locations;
  final RxnString employeeId = RxnString();
  final Rxn<DateTime> date = Rxn<DateTime>();
  final Rxn<TimeOfDay> start = Rxn<TimeOfDay>();
  final Rxn<TimeOfDay> end = Rxn<TimeOfDay>();
  final RxnString locationId = RxnString();
  final RxString note = ''.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();
  final RxList<String> warnings = <String>[].obs;

  bool get isEdit => existing != null;

  DateTime? get startAt {
    final d = date.value, t = start.value;
    return d == null || t == null ? null : DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  DateTime? get endAt {
    final d = date.value, t = end.value, s = startAt;
    if (d == null || t == null || s == null) return null;
    var e = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (!e.isAfter(s)) e = e.add(const Duration(days: 1)); // an overnight shift
    return e;
  }

  bool get canSubmit => employeeId.value != null && startAt != null && endAt != null && !busy.value;

  @override
  void onInit() {
    super.onInit();
    if (_presetPeople != null) {
      people.assignAll(_presetPeople);
    } else {
      _loadPeople();
    }
  }

  Future<void> _loadPeople() async {
    try {
      people.assignAll(await _repo.getEmployees(await teamStoreId(_storeIdOverride)));
    } catch (_) {}
  }

  Future<RosterShift?> submit() async {
    if (busy.value) return null;
    error.value = null;
    warnings.clear();
    final s = startAt, e = endAt, who = employeeId.value;
    if (who == null) {
      error.value = teamErrorMessage('EMPLOYEE_NOT_FOUND', fallback: 'Choose the team member.');
      return null;
    }
    if (s == null || e == null) {
      error.value = 'Choose the day and the start and end times.';
      return null;
    }
    if (!teamOnline()) {
      error.value = 'Needs internet. The roster can only be changed while the till is online.';
      return null;
    }
    busy.value = true;
    try {
      final sid = await teamStoreId(_storeIdOverride);
      final r = isEdit
          ? await _repo.updateRosterShift(sid, existing!.id, employeeId: who, startAt: s, endAt: e, locationId: locationId.value, note: note.value)
          : await _repo.createRosterShift(sid, employeeId: who, startAt: s, endAt: e, locationId: locationId.value, note: note.value);
      if (!r.success || r.shift == null) {
        error.value = teamErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message, extra: r.extra);
        return null;
      }
      warnings.assignAll(r.shift!.warnings);
      return r.shift;
    } finally {
      busy.value = false;
    }
  }
}
