import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/config/app_env.dart';

/// An error whose text has been scrubbed — what is actually sent to Crashlytics instead of the original exception
/// (exception messages from HTTP/DB layers can embed request bodies, emails, phone numbers or tokens).
class SanitizedError implements Exception {
  SanitizedError(this.type, this.message);
  final String type;
  final String message;
  @override
  String toString() => '$type: $message';
}

/// Crash + non-fatal reporting with NO personal data: only scrubbed messages, stack traces, the build environment and the
/// screen name go out. Never a user id, customer name, phone, email, token, PIN, receipt or request/response body.
/// Collection is on in release builds only; debug builds log locally.
class Telemetry {
  const Telemetry._();

  static bool _enabled = false;

  static Future<void> init() async {
    _enabled = kReleaseMode;
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(_enabled);
    if (!_enabled) return;
    await FirebaseCrashlytics.instance.setCustomKey('env', AppEnv.name);
  }

  static void installHandlers() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      record(details.exception, details.stack, fatal: true, reason: details.library);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, fatal: true);
      return true;
    };
  }

  /// Safe to call anywhere; a no-op unless collection is enabled. [context] values are scrubbed too.
  static void record(Object error, StackTrace? stack, {bool fatal = false, String? reason, Map<String, String> context = const {}}) {
    if (!_enabled) return;
    try {
      final c = FirebaseCrashlytics.instance;
      for (final e in context.entries) {
        c.setCustomKey(e.key, scrub(e.value));
      }
      c.recordError(SanitizedError(error.runtimeType.toString(), scrub(error.toString())), stack, fatal: fatal, reason: reason == null ? null : scrub(reason));
    } catch (_) {/* reporting must never throw */}
  }

  /// A failed API call, reduced to `METHOD /path/with/:id → status` (no query string, body or headers).
  static void recordHttp(String method, String path, int? status) {
    record(SanitizedError('HttpError', '$method ${scrubPath(path)} -> ${status ?? 'no response'}'), StackTrace.current);
  }

  static String scrubPath(String path) {
    var p = path;
    final q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    final i = p.indexOf('/api/');
    if (i >= 0) p = p.substring(i);
    return p.replaceAll(RegExp(r'[a-fA-F0-9]{24}'), ':id').replaceAll(RegExp(r'\d{4,}'), ':n');
  }

  /// Removes anything that looks personal or secret from free text.
  static String scrub(String input) {
    var s = input;
    s = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*'), '[token]'); // JWT
    s = s.replaceAll(RegExp(r'bearer\s+[A-Za-z0-9._\-]+', caseSensitive: false), 'Bearer [token]');
    s = s.replaceAll(RegExp(r'[\w.+\-]+@[\w\-]+(\.[\w\-]+)+'), '[email]');
    s = s.replaceAll(RegExp(r'\+?\d[\d\s().\-]{6,}\d'), '[number]'); // phone / card-like digit runs
    s = s.replaceAll(RegExp(r'("?(pin|password|passcode|token|secret|authorization)"?\s*[:=]\s*)"?[^",}\s]+"?', caseSensitive: false), r'$1[redacted]');
    s = s.replaceAll(RegExp(r'[A-Za-z0-9_\-]{32,}'), '[id]'); // long opaque strings
    return s.length > 600 ? '${s.substring(0, 600)}…' : s;
  }
}
