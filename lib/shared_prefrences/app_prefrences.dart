import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppPreferences {
  static const String _accessTokenKey = 'token';
  static const String _refreshTokenKey = 'refreshToken';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userRoleKey = 'user_role';
  static const String _userEmailKey = 'user_email';
  static const String _userProfileImageKey = 'user_profile_image';
  static const String _storeIdKey = 'store_id';
  static const String _storeNameKey = 'store_name';
  static const String _brandingConfigKey = 'branding_config_json';

  // ── POS employee / session context ────────────────────────────────────────────
  static const String _posEmployeeIdKey = 'pos_employee_id';
  static const String _posEmployeeNameKey = 'pos_employee_name';
  static const String _posEmployeeRoleKey = 'pos_employee_role';
  static const String _posSessionIdKey = 'pos_session_id';
  static const String _posRegisterIdKey = 'pos_register_id';
  static const String _posShiftIdKey = 'pos_shift_id';

  // ── POS device-local preferences (not backend-tracked) ─────────────────────
  static const String _posSoundEffectsKey = 'pos_sound_effects';
  static const String _posAutoLockMinutesKey = 'pos_auto_lock_minutes';

  // Save access token
  static Future<void> setAccessToken(
    String accessToken,
    String refreshToken,
  ) async {
    await setTokens(accessToken: accessToken, refreshToken: refreshToken);
  }

  // Get access token
  static Future<String?> getAccessTokenAsync() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  // Save refresh token
  static Future<void> setRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  // Get refresh token
  static Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  // Save both tokens at once
  static Future<void> setTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessTokenKey, accessToken);
      await prefs.setString(_refreshTokenKey, refreshToken);
    } catch (e) {
      debugPrint('❌ Error saving tokens: $e');
      rethrow;
    }
  }

  // Clear access token
  static Future<void> clearAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
  }

  // Clear refresh token
  static Future<void> clearRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }

  // Clear both tokens
  static Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
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

  /// Sets the locally-cached role only (doesn't touch the server). Used to
  /// flip a freshly-signed-up seller to 'seller' right after their first
  /// store is created — see SellerOnboardingController.complete(). The POS
  /// access middleware only ever reads this local value, never re-checks
  /// the server, so this is what actually unlocks the terminal for them.
  static Future<void> setUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRoleKey, role);
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

  // Clear all preferences
  static Future<void> clearPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // Check if user is logged in
  static Future<bool> isLoggedIn() async {
    final token = await getAccessTokenAsync();
    return token != null && token.isNotEmpty;
  }

  // ── Store ID ──────────────────────────────────────────────────────────────────
  static Future<void> saveStoreId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storeIdKey, id);
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

  static Future<void> clearPosEmployee() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_posEmployeeIdKey);
    await prefs.remove(_posEmployeeNameKey);
    await prefs.remove(_posEmployeeRoleKey);
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

  // ── White-label branding cache (last successfully fetched config, so a
  // cold start can paint the right brand instantly instead of flashing
  // defaults first — see BrandingService) ──────────────────────────────────
  static Future<void> saveBrandingConfigJson(String json) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_brandingConfigKey, json);
  }

  static Future<String?> getBrandingConfigJson() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_brandingConfigKey);
  }
}
