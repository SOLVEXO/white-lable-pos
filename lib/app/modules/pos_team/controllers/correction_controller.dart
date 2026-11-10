import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_team/controllers/team_common.dart';

/// A manager's correction of one attendance record: set the clock-in or clock-out time, add a missing clock-out, or void the record. A REASON is
/// required. It is saved as a NEW row on top (the raw punches stay), so the record then shows "Corrected". Online only; the server enforces who may.
class CorrectionController extends GetxController {
  CorrectionController({required this.record, PosRepository? repository, String? storeId, DateTime Function()? clock})
    : _repo = repository ?? PosRepository(),
      _storeIdOverride = storeId,
      _clock = clock ?? DateTime.now {
    clockInAt.value = record.clockInAt;
    clockOutAt.value = record.clockOutAt;
  }
  final AttendanceRecord record;
  final PosRepository _repo;
  final String? _storeIdOverride;
  final DateTime Function() _clock;

  final Rxn<DateTime> clockInAt = Rxn<DateTime>();
  final Rxn<DateTime> clockOutAt = Rxn<DateTime>();
  final RxBool voided = false.obs;
  final RxString reason = ''.obs;
  final RxBool busy = false.obs;
  final RxnString error = RxnString();

  bool _same(DateTime? a, DateTime? b) => a == null || b == null ? a == b : a.millisecondsSinceEpoch ~/ 60000 == b.millisecondsSinceEpoch ~/ 60000;

  bool get inChanged => !_same(clockInAt.value, record.clockInAt);
  bool get outChanged => clockOutAt.value != null && !_same(clockOutAt.value, record.clockOutAt);
  bool get changed => voided.value || inChanged || outChanged;
  bool get hasReason => reason.value.trim().isNotEmpty;

  /// the missing clock-out case: an open record being given its end
  bool get addsClockOut => record.clockOutAt == null && clockOutAt.value != null;

  bool get canSubmit => changed && hasReason && !busy.value;

  void setVoided(bool v) => voided.value = v;

  /// What goes to the server: only what changed (nothing but the reason and `voided` when voiding). Null when there is nothing valid to send.
  Map<String, dynamic>? get payload {
    if (!changed) return null;
    return {
      'employeeId': record.employeeId,
      'recordId': record.recordId,
      'reason': reason.value.trim(),
      if (voided.value) 'voided': true,
      if (!voided.value && inChanged) 'clockInAt': clockInAt.value,
      if (!voided.value && outChanged) 'clockOutAt': clockOutAt.value,
    };
  }

  Future<AttendanceRecord?> submit() async {
    if (busy.value) return null;
    error.value = null;
    if (!changed) {
      error.value = teamErrorMessage('INVALID_CORRECTION');
      return null;
    }
    if (!hasReason) {
      error.value = teamErrorMessage('REASON_REQUIRED');
      return null;
    }
    final now = _clock().add(const Duration(minutes: 5));
    final i = clockInAt.value, o = clockOutAt.value;
    if (!voided.value && ((i != null && i.isAfter(now)) || (o != null && o.isAfter(now)) || (o != null && i != null && !o.isAfter(i)))) {
      error.value = teamErrorMessage('INVALID_DATE');
      return null;
    }
    if (!teamOnline()) {
      error.value = 'Needs internet.';
      return null;
    }
    busy.value = true;
    try {
      final r = await _repo.correctAttendance(
        await teamStoreId(_storeIdOverride),
        employeeId: record.employeeId,
        recordId: record.recordId,
        reason: reason.value,
        clockInAt: voided.value || !inChanged ? null : clockInAt.value,
        clockOutAt: voided.value || !outChanged ? null : clockOutAt.value,
        voided: voided.value,
      );
      if (!r.success) {
        error.value = teamErrorMessage(r.code ?? _repo.lastErrorCode, fallback: r.message);
        return null;
      }
      return r.record ?? record;
    } finally {
      busy.value = false;
    }
  }
}
