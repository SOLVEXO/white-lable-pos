import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

enum UnlockResult { ok, wrongPin, differentEmployee, failed }

/// Locks the till to a PIN screen after the owner-set idle time (default 5 min).
///
/// Locking only COVERS the app (an overlay — see PosLockOverlay): every controller, the cart and the offline queue stay
/// exactly as they were, so nothing is lost and a sync in progress carries on. Unlocking re-runs PIN login for the SAME
/// employee; the new session token replaces the old one and the old one is revoked server-side. The owner's elevated
/// session ends the moment the till locks.
class IdleLockService extends GetxController {
  IdleLockService({
    PosRepository? posRepository,
    DateTime Function()? clock,
    bool Function()? employeeSignedIn,
    Duration checkEvery = const Duration(seconds: 10),
  })  : _repo = posRepository,
        _clock = clock ?? DateTime.now,
        _employeeSignedIn = employeeSignedIn ?? (() => AppPreferences.cachedHasPosSession),
        _checkEvery = checkEvery;

  PosRepository? _repo;
  PosRepository get _posRepo => _repo ??= PosRepository();
  final DateTime Function() _clock;
  final bool Function() _employeeSignedIn;
  final Duration _checkEvery;

  final RxBool locked = false.obs;
  final RxInt minutes = 5.obs;
  final RxnString employeeName = RxnString();

  DateTime _lastActivity = DateTime.now();
  Timer? _timer;

  @override
  void onInit() {
    super.onInit();
    _lastActivity = _clock();
    unawaited(_loadMinutes());
    _timer = Timer.periodic(_checkEvery, (_) => checkIdle());
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  Future<void> _loadMinutes() async => minutes.value = await AppPreferences.getPosAutoLockMinutes();

  /// The owner-set value, as last told by the backend (cached so it applies offline too).
  Future<void> setMinutes(int m) async {
    minutes.value = m < 1 ? 1 : m;
    await AppPreferences.setPosAutoLockMinutes(minutes.value);
  }

  /// Any touch on the screen.
  void onActivity() {
    if (!locked.value) _lastActivity = _clock();
  }

  /// Locks when someone is signed in and the idle time has elapsed. Public so a test (or a resume hook) can drive it.
  void checkIdle() {
    if (locked.value || !_employeeSignedIn()) return;
    if (_clock().difference(_lastActivity) >= Duration(minutes: minutes.value)) lock();
  }

  Future<void> lock() async {
    if (locked.value) return;
    OwnerSession.end(); // elevated access never survives a lock
    locked.value = true; // cover the screen first — there must be no window while anything is awaited
    employeeName.value = await AppPreferences.getPosEmployeeName();
  }

  /// Back in with the PIN of the employee who was signed in. A different employee's PIN does not unlock — "Switch user"
  /// is a proper PIN logout/login so attribution of the cart stays with whoever rang it.
  Future<UnlockResult> unlock(String pin) async {
    final storeId = await AppPreferences.getStoreId() ?? '';
    final email = await AppPreferences.getPosEmployeeEmail();
    final lockedId = await AppPreferences.getPosEmployeeId();
    if (storeId.isEmpty || email == null || email.isEmpty) return UnlockResult.failed;
    final res = await _posRepo.pinLogin(storeId: storeId, email: email, pin: pin);
    if (!res.success || res.employee == null) {
      // (the server counts the wrong guess toward the per-employee lock and the per-device limiter)
      return res.message != null && res.message!.toLowerCase().contains('invalid') ? UnlockResult.wrongPin : UnlockResult.failed;
    }
    if (res.employee!.id != lockedId) return UnlockResult.differentEmployee;
    final old = await AppPreferences.getPosEmployeeToken();
    if (res.employeeToken != null) await AppPreferences.setPosEmployeeToken(res.employeeToken!);
    if (old != null) unawaited(_posRepo.pinLogoutWith(storeId, old)); // the pre-lock token is now dead server-side
    _lastActivity = _clock();
    locked.value = false;
    return UnlockResult.ok;
  }

  /// Dismisses the overlay without a PIN — only for flows that already ended the employee's session (switch user / sign out).
  void releaseWithoutPin() {
    _lastActivity = _clock();
    locked.value = false;
  }
}
