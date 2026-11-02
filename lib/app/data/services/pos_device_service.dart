import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/repositories/pos_device_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

enum DeviceSetupResult { ok, failed, otherStoreWithUnsyncedSales }

enum DeviceResetResult { done, blockedByUnsyncedSales }

/// This terminal's registration with the backend (5D): registering, losing its registration (revoked), and retiring it.
///
/// - Registering swaps the owner's session for the long-lived device token (the owner JWT/refresh token are discarded).
/// - A revoked device is sent back to setup but KEEPS its offline queue, caches and store binding; the unsynced sales are
///   uploaded once the owner registers it again — for the SAME store only (they belong to that store's books).
/// - A full sign-out / reset wipes credentials and caches, and is refused while any sale is still unsynced.
class PosDeviceService extends GetxController {
  PosDeviceService({
    PosDeviceRepository? repository,
    Future<int> Function()? unresolvedSales,
    Future<void> Function()? onRegistered,
  })  : _repo = repository ?? PosDeviceRepository(),
        _unresolvedSales = unresolvedSales,
        _onRegistered = onRegistered;

  final PosDeviceRepository _repo;
  final Future<int> Function()? _unresolvedSales;

  /// Runs after a successful registration — the app uses it to start draining the offline queue straight away.
  final Future<void> Function()? _onRegistered;

  /// Shown on the login/setup screens after the device lost its registration.
  final RxnString revokedNotice = RxnString();

  Future<int> _unresolved() async => _unresolvedSales != null ? _unresolvedSales() : 0;

  /// May this device be (re-)registered for [storeId]? Not while it still holds unsynced sales of a DIFFERENT store.
  Future<bool> canBindTo(String storeId) async {
    final bound = (await AppPreferences.getDeviceRegistration()).storeId;
    if (bound == null || bound.isEmpty || bound == storeId) return true;
    return await _unresolved() == 0;
  }

  /// Registers this terminal for [storeId]/[registerId]. The owner's session is the one currently signed in; on success it
  /// is replaced by the device token.
  Future<DeviceSetupResult> register({required String storeId, required String registerId, required String name, String? platform}) async {
    if (!await canBindTo(storeId)) return DeviceSetupResult.otherStoreWithUnsyncedSales;
    final reg = await _repo.register(storeId: storeId, registerId: registerId, name: name, platform: platform);
    if (reg == null) return DeviceSetupResult.failed;
    await AppPreferences.saveDeviceRegistration(
      deviceToken: reg.deviceToken, deviceId: reg.deviceId, name: name, storeId: storeId, registerId: registerId,
    );
    OwnerSession.end();
    revokedNotice.value = null;
    await _onRegistered?.call();
    return DeviceSetupResult.ok;
  }

  /// The backend said this device's token is no longer valid. Credentials and the signed-in employee are dropped; the
  /// queue, caches and store binding stay.
  Future<void> handleRevoked(String code) async {
    await AppPreferences.clearDeviceCredentials();
    OwnerSession.end();
    revokedNotice.value = code == 'POS_DEVICE_REVOKED'
        ? 'The store owner removed this device. Sign in as the owner to set it up again — your unsynced sales are kept and will upload once it is set up for the same store.'
        : 'This device needs to be set up again. Sign in as the owner. Your unsynced sales are kept.';
    debugPrint('🔒 device credentials cleared ($code)');
  }

  /// Full sign-out / device reset: tokens, caches and the store binding go — but never while sales are unsynced (the queue
  /// is the only copy of that money).
  Future<DeviceResetResult> reset() async {
    if (await _unresolved() > 0) return DeviceResetResult.blockedByUnsyncedSales;
    if (AppPreferences.cachedDeviceMode) await _repo.signOutSelf();
    OwnerSession.end();
    await AppPreferences.clearPreference(wipeQueueKey: true);
    revokedNotice.value = null;
    return DeviceResetResult.done;
  }
}
