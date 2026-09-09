import 'package:solvexo_pos/app/data/models/common_models/auth_response_model.dart';
import 'package:solvexo_pos/app/data/models/common_models/social_login_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Two ways in, both ending at the same place (tokens + user saved via
/// [AppPreferences], role forced to 'seller' since this app is seller-only):
///
/// - [socialLogin] — Google Sign-In, same endpoint the buyer app uses. A
///   first-time sign-in creates the account server-side (that's "signup").
/// - [login] — email/password. The buyer app dropped its UI for this
///   (Google Sign-In only, Phase 10), but the backend endpoint is still
///   live — verified directly against staging, not assumed from a comment.
///
/// This app has no buyer-only profile-editing/account-deletion endpoints,
/// so only what POS actually calls is kept.
class AuthRepository {
  final BaseClient _baseClient = BaseClient();

  Future<AuthResponseModel?> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _baseClient.post(
        ApiConstants.login,
        data: {'email': email, 'password': password, 'role': 'seller'},
        requiresAuth: false,
      );

      if (response.data['success'] == true) {
        final auth = AuthResponseModel.fromJson(response.data);
        await _persistAuth(auth);
        return auth;
      }

      return null;
    } on DioException catch (e) {
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ Login error: $e');
      return null;
    }
  }

  Future<AuthResponseModel?> socialLogin(SocialLoginModel dto) async {
    try {
      debugPrint('🔄 Social login: ${dto.authProvider} - ${dto.email}');

      final response = await _baseClient.post(
        ApiConstants.socialLogin,
        data: dto.toJson(),
      );

      if (response.data['success'] == true) {
        final auth = AuthResponseModel.fromJson(response.data);
        await _persistAuth(auth);
        if ((dto.image ?? '').isNotEmpty) {
          await AppPreferences.saveProfileImage(dto.image!);
        }

        debugPrint('✅ Social login successful');
        return auth;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Social login error: $e');
      rethrow;
    }
  }

  /// Re-verifies the current user's role against a fresh server call
  /// (`GET /api/auth/getprofile`, JWT-guarded) instead of trusting the
  /// locally-cached value indefinitely — see the Phase 4 plan's note on
  /// `AppPreferences.setUserRole`'s doc comment for what this narrows (not
  /// eliminates) about the app-level role-gate's client-trust weakness.
  /// Returns null on any failure (offline, expired token, etc.) — callers
  /// should keep whatever's already cached rather than treat this as fatal.
  Future<String?> getProfile() async {
    try {
      final response = await _baseClient.get(ApiConstants.getMe, requiresAuth: true);
      if (response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>?;
        return data?['role'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('❌ getProfile error: $e');
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _baseClient.post(ApiConstants.logout);
      await AppPreferences.clearAccessToken();
    } catch (e) {
      // Ignore API errors (401 is OK here)
      debugPrint('Logout API error (ignored): $e');
    } finally {
      await AppPreferences.clearPreference();
    }
  }

  /// Shared by [login] and [socialLogin] — this app is seller-only, so the
  /// role is always persisted as 'seller' locally regardless of what the
  /// server echoes back (the /login call above already sends role:
  /// 'seller' and gets it back verified; /social-login has no role
  /// parameter at all, so this is what makes that path consistent too).
  Future<void> _persistAuth(AuthResponseModel auth) async {
    await AppPreferences.setTokens(
      accessToken: auth.token.accessToken,
      refreshToken: auth.token.refreshToken,
    );
    await AppPreferences.saveUserData(
      userId: auth.user.id,
      name: auth.user.name,
      email: auth.user.email,
      role: 'seller',
    );
  }
}
