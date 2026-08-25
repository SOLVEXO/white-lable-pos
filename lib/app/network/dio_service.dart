import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class DioService {
  /// Invoked on a genuine session-expiry (401 on a `requiresAuth` request) so
  /// each app can drop back to its own post-logout destination (buyer:
  /// guest-mode home; POS: its PIN/login screen) — set once at app startup.
  static void Function()? onForceLogout;

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
            final token = await AppPreferences.getAccessTokenAsync();
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
          final requiresAuth = e.requestOptions.extra['requiresAuth'] ?? false;
          if (e.response?.statusCode == 401 && requiresAuth) {
            // Session expired or token invalid — clear local data and let
            // the host app route to its own post-logout destination.
            await AppPreferences.clearPreference();
            onForceLogout?.call();
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
