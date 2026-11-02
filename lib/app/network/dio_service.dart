import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/config/telemetry.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class DioService {
  /// Invoked on a genuine session-expiry (401 on a `requiresAuth` request) so
  /// each app can drop back to its own post-logout destination (buyer:
  /// guest-mode home; POS: its PIN/login screen) — set once at app startup.
  static void Function()? onForceLogout;

  /// Invoked when the backend says this DEVICE's token is no longer good (`POS_DEVICE_REVOKED` / `POS_DEVICE_INVALID`).
  /// Deliberately separate from [onForceLogout]: a revoked device keeps its offline queue, caches and store binding
  /// (see AppPreferences.clearDeviceCredentials) and is sent back to setup, instead of wiping everything.
  static void Function(String code)? onDeviceRevoked;

  /// The backend has switched off legacy (owner-JWT) POS access (`POS_LEGACY_AUTH_DISABLED`, a 403): this install must be
  /// registered as a device. The host app pushes the setup screen; the cart snapshot and the offline queue are untouched.
  static void Function()? onLegacyAuthDisabled;

  /// Which credential a request carries: an owner-only route uses the (short-lived, in-memory) owner session when there
  /// is one, everything else the stored access token — the device token once the terminal is registered.
  static String? tokenFor(String method, String path, String? storedToken, {bool deviceMode = false}) {
    if (deviceMode && OwnerRoutes.requiresOwner(method, path)) return OwnerSession.token ?? storedToken;
    return storedToken;
  }

  static Future<Dio> getDio({Map<String, dynamic>? headers}) async {
    final dio = Dio();

    dio.options.connectTimeout = const Duration(seconds: 30);
    dio.options.receiveTimeout = const Duration(seconds: 30);

    // ✅ DO NOT set Content-Type here — Dio sets it automatically based on
    // the request body type (FormData → multipart/form-data, Map → application/json).
    // Hardcoding it here breaks multipart file uploads.
    dio.options.headers = {
      'Accept': 'application/json',
      'Platform': Util.deviceType(),
      if (headers != null) ...headers,
    };

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final requiresAuth = options.extra['requiresAuth'] ?? false;

          if (requiresAuth) {
            final token = tokenFor(
              options.method,
              options.path,
              await AppPreferences.getAccessTokenAsync(),
              deviceMode: AppPreferences.cachedDeviceMode,
            );
            if (token != null && token.isNotEmpty) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          // ✅ Let Dio manage Content-Type — only log, never override here.
          debugPrint("➡️ ${options.method} ${options.path}");
          debugPrint("   Content-Type: ${options.headers['Content-Type']}");
          debugPrint("   Auth Required: $requiresAuth");

          handler.next(options);
        },
        onError: (e, handler) async {
          debugPrint("❌ Dio Error: ${e.response?.statusCode}");
          debugPrint("❌ Response: ${e.response?.data}");

          // Only an expired/invalid *session token* should force a logout —
          // that's a 401 on a request that actually sent one
          // (`requiresAuth: true`). A 401 from an unauthenticated request
          // like login/register just means "wrong credentials" and must be
          // returned to the caller normally, not treated as a session drop.
          final status = e.response?.statusCode;
          if (status == null || status >= 500) Telemetry.recordHttp(e.requestOptions.method, e.requestOptions.path, status);
          final requiresAuth = e.requestOptions.extra['requiresAuth'] ?? false;
          final body = e.response?.data;
          if (e.response?.statusCode == 403 && body is Map && body['code'] == 'POS_LEGACY_AUTH_DISABLED') {
            onLegacyAuthDisabled?.call();
          }
          // (Only a request that actually carried a credential can mean "your credential is bad".)
          final sentCredential = e.requestOptions.headers['Authorization'] != null;
          if (e.response?.statusCode == 401 && requiresAuth && sentCredential) {
            final data = e.response?.data;
            final code = data is Map ? data['code'] as String? : null;
            if (code == 'POS_DEVICE_REVOKED' || code == 'POS_DEVICE_INVALID') {
              // The owner removed this terminal (or its token died): back to setup, but the unsynced queue stays.
              await AppPreferences.clearDeviceCredentials();
              OwnerSession.end();
              onDeviceRevoked?.call(code!);
            } else if (AppPreferences.cachedDeviceMode) {
              // A 401 from the owner's short-lived session (expired) — not a reason to sign the whole device out.
              OwnerSession.end();
            } else {
              // Session expired or token invalid — clear local data and let
              // the host app route to its own post-logout destination.
              await AppPreferences.clearPreference();
              onForceLogout?.call();
            }
          }

          // Always hand the error back down the chain — swallowing it here
          // (via a bare `return`) leaves the original request's Future
          // pending forever, so the calling screen's `finally` block never
          // runs and `isLoading` gets stuck true across navigations.
          handler.next(e);
        },
      ),
    );

    return dio;
  }
}
