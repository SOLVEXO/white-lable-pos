import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:solvexo_pos/app/data/local/secure_storage_options.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

class AppPreferences {
  // Auth tokens live in Keychain/Keystore-backed secure storage (Phase 4
  // security pass), not plain SharedPreferences — everything else in this
  // class is device-local, non-sensitive app state and stays where it was.
  static const FlutterSecureStorage _secureStorage = kPosSecureStorage;

  static const String _accessTokenKey = 'token';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userRoleKey = 'user_role';
  static const String _userEmailKey = 'user_email';
  static const String _userProfileImageKey = 'user_profile_image';
  static const String _storeIdKey = 'store_id';
  static const String _storeNameKey = 'store_name';
  static const String _hasSeenOnboardingKey = 'has_seen_onboarding';

  // ── POS employee / session context ────────────────────────────────────────────
  static const String _posEmployeeIdKey = 'pos_employee_id';
  static const String _posEmployeeNameKey = 'pos_employee_name';
  static const String _posEmployeeRoleKey = 'pos_employee_role';
  static const String _posEmployeeTokenKey = 'pos_employee_token';
  static const String _posSessionIdKey = 'pos_session_id';
  static const String _posRegisterIdKey = 'pos_register_id';
  static const String _posShiftIdKey = 'pos_shift_id';
  static const String _posEmployeeEmailKey = 'pos_employee_email';

  // ── POS device registration (5D) ───────────────────────────────────────────────
  // Once the owner registers this terminal, the long-lived DEVICE token replaces the owner's session in the access-token
  // slot (the owner's JWT and refresh token are discarded). The binding below survives a revocation so the unsynced
  // queue can only be re-registered against the SAME store.
  static const String _deviceModeKey = 'pos_device_mode';
  static const String _deviceIdKey = 'pos_device_id';
  static const String _deviceNameKey = 'pos_device_name';
  static const String _deviceStoreKey = 'pos_device_store_id';
  static const String _deviceRegisterKey = 'pos_device_register_id';

  // ── POS device-local preferences (not backend-tracked) ─────────────────────
  static const String _posSoundEffectsKey = 'pos_sound_effects';
  static const String _posAutoLockMinutesKey = 'pos_auto_lock_minutes';
  static const String _posLockOnBackgroundKey = 'pos_lock_on_background';
  static const String _posPrinterAddressKey = 'pos_printer_address';
  static const String _posPrinterNameKey = 'pos_printer_name';

  // ── Synchronous in-memory cache ─────────────────────────────────────────────
  // `PosAccessMiddleware.onPageCalled` must redirect *before* returning the
  // page — GetX gives it no way to await. `getAccessTokenAsync()`/
  // `getUserRole()`/`hasPosSession()` can't do that (they round-trip through
  // the SharedPreferences channel), which used to let a guarded screen render
  // for a frame before the async check redirected it away. This cache is
  // warmed once at boot (after the `SharedPreferences.getInstance()` call in
  // main.dart) and kept in sync on every write below, so the middleware can
  // check it synchronously instead.
  static String? _cachedToken;
  static String? _cachedRole;
  static bool _cachedHasPosSession = false;
  static bool _cachedDeviceMode = false;

  static String? get cachedToken => _cachedToken;
  static String? get cachedRole => _cachedRole;
  static bool get cachedHasPosSession => _cachedHasPosSession;
  static bool get cachedDeviceMode => _cachedDeviceMode;

  /// Populates the sync cache from disk. Call once at app boot, after
  /// `SharedPreferences.getInstance()` has resolved.
  static Future<void> warmCache() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = await _secureStorage.read(key: _accessTokenKey);
    _cachedRole = prefs.getString(_userRoleKey);
    final sessionId = prefs.getString(_posSessionIdKey);
    _cachedHasPosSession = sessionId != null && sessionId.isNotEmpty;
    _cachedDeviceMode = prefs.getBool(_deviceModeKey) ?? false;
  }

  // Save access token
  static Future<void> setAccessToken(
    String accessToken,
    String refreshToken,
  ) async {
    await setTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  // Get access token
  static Future<String?> getAccessTokenAsync() async {
    return _secureStorage.read(key: _accessTokenKey);
  }

  // Save refresh token
  static Future<void> setRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  // Get refresh token
  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  // Save both tokens at once
  static Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      await _secureStorage.write(key: _accessTokenKey, value: accessToken);
      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);
      _cachedToken = accessToken;
    } catch (e) {
      debugPrint('❌ Error saving tokens: $e');
      rethrow;
    }
  }

  // Clear access token
  static Future<void> clearAccessToken() async {
    await _secureStorage.delete(key: _accessTokenKey);
    _cachedToken = null;
  }

  // Clear refresh token
  static Future<void> clearRefreshToken() async {
    await _secureStorage.delete(key: _refreshTokenKey);
  }

  // Clear both tokens
  static Future<void> clearTokens() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    _cachedToken = null;
  }

  // Save user data
  static Future<void> saveUserData({
    required String userId,
    required String name,
    required String email,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_userEmailKey, email);
    await prefs.setString(_userRoleKey, role);
  }

  // Get user ID
  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  // Get user name
  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  // Get user email
  static Future<String?> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userEmailKey);
  }

  // Get user role
  static Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey);
  }

  /// Sets the locally-cached role only (doesn't touch the server on its
  /// own). Used to flip a freshly-signed-up seller to 'seller' right after
  /// their first store is created — see SellerOnboardingController.complete()
  /// — and to write back a freshly-fetched role from AuthRepository.getProfile()
  /// at boot (main.dart, Phase 4). PosAccessMiddleware reads this local
  /// value synchronously on every navigation and only gets a fresh one at
  /// the next cold start's background getProfile() call — it does not
  /// re-verify against the server on every navigation, so this is still a
  /// client-writable value between boots, not a real security boundary on
  /// its own; every actual POS API call still requires a valid JWT
  /// regardless of what's cached here.
  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRoleKey, role);
    _cachedRole = role;
  }

  // ── Profile image (from the signed-in Google account) ───────────────────────
  static Future<void> saveProfileImage(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userProfileImageKey, url);
  }

  static Future<String?> getProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userProfileImageKey);
  }

  // Clear all user data
  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userProfileImageKey);
  }

  /// Clears everything. The offline queue's encryption key is KEPT unless [wipeQueueKey] — wiping it would turn every
  /// unsynced sale on the device into unreadable ciphertext. Only a device reset with an EMPTY queue passes true.
  static Future<void> clearPreference({bool wipeQueueKey = false}) {
    // G5.1: one clear at a time — several requests answered 401 at once each trigger a forced logout, and two interleaved clears raced on the
    // keychain (both wrote the queue key back: "already exists", -25299, thrown out of sign-out). Found by the simulator flows.
    final run = _clearing.then((_) => _clearPreference(wipeQueueKey: wipeQueueKey));
    _clearing = run.catchError((_) {});
    return run;
  }

  static Future<void> _clearing = Future<void>.value();

  static Future<void> _clearPreference({bool wipeQueueKey = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final queueKey = wipeQueueKey ? null : await _secureStorage.read(key: AesGcmQueueCipher.storageKey);
    await prefs.clear();
    await _secureStorage.deleteAll();
    // G5.1: on iOS `deleteAll` can leave an item behind (found on the simulator: the write-back then failed with "already exists", -25299, and
    // threw out of sign-out). Put the queue key back only if it is not already there, and replace a leftover instead of failing.
    if (queueKey != null) {
      final left = await _secureStorage.read(key: AesGcmQueueCipher.storageKey);
      if (left != queueKey) {
        if (left != null) await _secureStorage.delete(key: AesGcmQueueCipher.storageKey);
        await _secureStorage.write(key: AesGcmQueueCipher.storageKey, value: queueKey);
      }
    }
    _cachedToken = null;
    _cachedRole = null;
    _cachedHasPosSession = false;
    _cachedDeviceMode = false;
  }

  // ── POS device registration ───────────────────────────────────────────────────
  /// Swaps the owner's session for the device token. The owner's refresh token is dropped on purpose.
  static Future<void> saveDeviceRegistration({
    required String deviceToken,
    required String deviceId,
    required String name,
    required String storeId,
    required String registerId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _accessTokenKey, value: deviceToken);
    await _secureStorage.delete(key: _refreshTokenKey);
    await prefs.setBool(_deviceModeKey, true);
    await prefs.setString(_deviceIdKey, deviceId);
    await prefs.setString(_deviceNameKey, name);
    await prefs.setString(_deviceStoreKey, storeId);
    await prefs.setString(_deviceRegisterKey, registerId);
    await prefs.setString(_storeIdKey, storeId);
    await prefs.setString(_posRegisterIdKey, registerId);
    await prefs.setString(_userRoleKey, 'seller'); // the device acts as its store's seller for the existing role gates
    _cachedToken = deviceToken;
    _cachedRole = 'seller';
    _cachedDeviceMode = true;
  }

  static Future<({String? deviceId, String? name, String? storeId, String? registerId})> getDeviceRegistration() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      deviceId: prefs.getString(_deviceIdKey),
      name: prefs.getString(_deviceNameKey),
      storeId: prefs.getString(_deviceStoreKey),
      registerId: prefs.getString(_deviceRegisterKey),
    );
  }

  /// The device was revoked (or its token is dead): drop every credential and the signed-in employee/session context, but
  /// KEEP the store binding, the caches and — above all — the offline queue and its key, so the unsynced sales can still
  /// be uploaded once the owner registers this device again for the same store.
  static Future<void> clearDeviceCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    await _secureStorage.delete(key: _posEmployeeTokenKey);
    await prefs.setBool(_deviceModeKey, false);
    await prefs.remove(_deviceIdKey);
    for (final k in [_posEmployeeIdKey, _posEmployeeNameKey, _posEmployeeRoleKey, _posEmployeeEmailKey, _posSessionIdKey, _posShiftIdKey]) {
      await prefs.remove(k);
    }
    _cachedToken = null;
    _cachedHasPosSession = false;
    _cachedDeviceMode = false;
  }

  static Future<String?> getPosEmployeeEmail() async => (await SharedPreferences.getInstance()).getString(_posEmployeeEmailKey);
  static Future<void> setPosEmployeeEmail(String email) async => (await SharedPreferences.getInstance()).setString(_posEmployeeEmailKey, email);

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAccessTokenAsync();
    return token != null && token.isNotEmpty;
  }

  // ── Small generic key/value helpers (caches, timestamps) ───────────────────────
  static Future<String?> getString(String key) async => (await SharedPreferences.getInstance()).getString(key);
  static Future<void> setString(String key, String value) async => (await SharedPreferences.getInstance()).setString(key, value);
  static Future<void> removeKey(String key) async => (await SharedPreferences.getInstance()).remove(key);

  // ── Store currency (so money renders correctly before settings have loaded) ────
  static Future<void> saveStoreCurrency(String code, int exponent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('store_currency', code);
    await prefs.setInt('store_currency_exponent', exponent);
  }

  static Future<({String? code, int? exponent})> getStoreCurrency() async {
    final prefs = await SharedPreferences.getInstance();
    return (code: prefs.getString('store_currency'), exponent: prefs.getInt('store_currency_exponent'));
  }

  // ── Store ID ──────────────────────────────────────────────────────────────────
  /// G6.2: called after the store changes (set at start to re-check the backend's capabilities); never throws into the caller
  static void Function()? onStoreChanged;

  static Future<void> saveStoreId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final changed = prefs.getString(_storeIdKey) != id;
    await prefs.setString(_storeIdKey, id);
    if (changed) {
      try {
        onStoreChanged?.call();
      } catch (_) {}
    }
  }

  static Future<String?> getStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storeIdKey);
  }

  static Future<void> clearStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storeIdKey);
  }

  // ── Store Name ────────────────────────────────────────────────────────────────
  static Future<void> saveStoreName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeNameKey, name);
  }

  static Future<String?> getStoreName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storeNameKey);
  }

  static Future<void> clearStoreName() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storeNameKey);
  }

  // ── POS employee context ──────────────────────────────────────────────────────
  static Future<void> savePosEmployee({
    required String id,
    required String name,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_posEmployeeIdKey, id);
    await prefs.setString(_posEmployeeNameKey, name);
    await prefs.setString(_posEmployeeRoleKey, role);
  }

  static Future<String?> getPosEmployeeId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posEmployeeIdKey);
  }

  static Future<String?> getPosEmployeeName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posEmployeeNameKey);
  }

  static Future<String?> getPosEmployeeRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posEmployeeRoleKey);
  }

  /// The signed JWT `pinLogin` returns for the currently PIN-logged-in
  /// employee (`type: 'pos_employee'`, embeds employeeId/role/storeId,
  /// 12h expiry). Sent as the `x-pos-employee-token` header on every
  /// privileged POS action (refund, void, cash in/out, discounts) — the
  /// backend verifies its signature and role claim instead of trusting a
  /// client-supplied id string, which used to be spoofable by anyone
  /// holding the seller's own JWT (employee ids/roles are visible via
  /// GET /pos/employees/:storeId). Stored in secure storage alongside the
  /// seller auth tokens — it's the same category of bearer credential.
  static Future<void> setPosEmployeeToken(String token) async {
    await _secureStorage.write(key: _posEmployeeTokenKey, value: token);
  }

  static Future<String?> getPosEmployeeToken() async {
    return _secureStorage.read(key: _posEmployeeTokenKey);
  }

  static Future<void> clearPosEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posEmployeeIdKey);
    await prefs.remove(_posEmployeeNameKey);
    await prefs.remove(_posEmployeeRoleKey);
    await prefs.remove(_posEmployeeEmailKey);
    await _secureStorage.delete(key: _posEmployeeTokenKey);
  }

  // ── POS active session context ────────────────────────────────────────────────
  static Future<void> savePosSession({
    required String sessionId,
    required String registerId,
    required String shiftId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_posSessionIdKey, sessionId);
    await prefs.setString(_posRegisterIdKey, registerId);
    await prefs.setString(_posShiftIdKey, shiftId);
    _cachedHasPosSession = sessionId.isNotEmpty;
  }

  static Future<String?> getPosSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posSessionIdKey);
  }

  static Future<String?> getPosRegisterId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posRegisterIdKey);
  }

  static Future<String?> getPosShiftId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posShiftIdKey);
  }

  static Future<void> clearPosSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posSessionIdKey);
    await prefs.remove(_posRegisterIdKey);
    await prefs.remove(_posShiftIdKey);
    _cachedHasPosSession = false;
  }

  static Future<bool> hasPosSession() async {
    final id = await getPosSessionId();
    return id != null && id.isNotEmpty;
  }

  // ── POS device-local preferences ──────────────────────────────────────────
  static Future<void> setPosSoundEffects(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_posSoundEffectsKey, enabled);
  }

  static Future<bool> getPosSoundEffects() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_posSoundEffectsKey) ?? true;
  }

  static Future<void> setPosAutoLockMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_posAutoLockMinutesKey, minutes);
  }

  static Future<int> getPosAutoLockMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_posAutoLockMinutesKey) ?? 5;
  }

  /// G4.4: lock the till as soon as the app leaves the screen (the owner's store setting, cached for offline).
  static Future<void> setPosLockOnBackground(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_posLockOnBackgroundKey, on);
  }

  static Future<bool> getPosLockOnBackground() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_posLockOnBackgroundKey) ?? false;
  }

  // ── First-launch onboarding flag ─────────────────────────────────────────
  static Future<void> setHasSeenOnboarding(bool seen) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenOnboardingKey, seen);
  }

  static Future<bool> getHasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenOnboardingKey) ?? false;
  }

  // ── Paired thermal receipt printer (Phase 3) — remembered so the cashier
  // only has to pair it once, not on every print; see ThermalPrinterService.
  static Future<void> setPosPrinter({required String address, required String name}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_posPrinterAddressKey, address);
    await prefs.setString(_posPrinterNameKey, name);
  }

  static Future<void> clearPosPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posPrinterAddressKey);
    await prefs.remove(_posPrinterNameKey);
  }

  static Future<String?> getPosPrinterAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posPrinterAddressKey);
  }

  static Future<String?> getPosPrinterName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_posPrinterNameKey);
  }
}
