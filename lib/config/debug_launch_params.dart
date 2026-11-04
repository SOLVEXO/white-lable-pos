import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Debug-only launch parameters, used to drive simulator screenshots/flows
/// without UI automation. Pass `--dart-define=DBG_PARAMS_FILE=/path/params.txt`
/// and put `key=value` lines in it; the file is re-read on every hot restart.
///
/// RELEASE SAFETY: every entry point below begins with `if (!kDebugMode) return …;`. `kDebugMode` is a compile-time
/// constant, so in profile/release builds the rest of each body is dead code and is tree-shaken away (see
/// test/debug_launch_params_test.dart, which also checks the guards stay in place). The parameters file is never an
/// asset: it is an external path handed in with `--dart-define=DBG_PARAMS_FILE=…`, and is only ever opened here.
abstract final class DebugLaunchParams {
  static const String _file = String.fromEnvironment('DBG_PARAMS_FILE');

  static String? get(String key) {
    if (!kDebugMode) return null;
    if (_file.isEmpty) return null;
    try {
      for (final line in File(_file).readAsLinesSync()) {
        final i = line.indexOf('=');
        if (i > 0 && line.substring(0, i).trim() == key) {
          return line.substring(i + 1).trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Debug builds only, and only when a `SEED=` line is present: puts the app in a known launch state so
  /// the splash routing branches can be exercised on a simulator without a backend. Runs before
  /// `AppPreferences.warmCache()`. States: `fresh` (a clean install), `owner` (owner session),
  /// `device` (registered till, no shift), `device_session` (registered till with a running shift).
  /// `AUTOLOCK_MIN=<n>` also sets the idle-lock minutes.
  static Future<void> seed() async {
    if (!kDebugMode) return;
    final state = get('SEED');
    if (state == null || state.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await AppPreferences.clearTokens();
    if (state == 'fresh') return;
    await AppPreferences.setTokens(
      accessToken: 'debug-seed-token',
      refreshToken: 'debug-seed-refresh',
    );
    await AppPreferences.setUserRole('seller');
    await AppPreferences.saveStoreId('debug-store');
    await AppPreferences.saveStoreName('Corner Bakery');
    await AppPreferences.setHasSeenOnboarding(true);
    await AppPreferences.setPosSoundEffects(false);
    await prefs.setString(
      'user_email',
      'owner@cornerbakery.com',
    ); // shown on the owner gate
    if (state == 'device' || state == 'device_session') {
      await AppPreferences.saveDeviceRegistration(
        deviceToken: 'debug-device-token',
        deviceId: 'debug-device',
        name: 'Front iPad',
        storeId: 'debug-store',
        registerId: 'debug-register',
      );
    }
    if (state == 'device_session') {
      await AppPreferences.savePosEmployee(
        id: 'debug-emp',
        name: 'Cal',
        role: get('ROLE') == 'manager' ? 'manager' : 'cashier', // debug only: ROLE=manager previews the manager view
      );
      await AppPreferences.setPosEmployeeEmail('cal@example.com');
      await AppPreferences.savePosSession(
        sessionId: 'debug-session',
        registerId: 'debug-register',
        shiftId: 'debug-shift',
      );
    }
    final minutes = int.tryParse(get('AUTOLOCK_MIN') ?? '');
    if (minutes != null) await AppPreferences.setPosAutoLockMinutes(minutes);
  }

  /// `THEME=dark` previews the dark theme on screens that are already migrated (the app itself ships light-only for now).
  static ThemeMode get themeMode {
    if (!kDebugMode) return ThemeMode.light;
    return get('THEME') == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  /// `ORIENTATION=landscape` (debug only): lays the whole app out landscape on a portrait-locked simulator
  /// (an iPad simulator can't be rotated without UI automation). The picture comes out turned 90 degrees
  /// clockwise; rotate the screenshot back. The shipped app never locks or forces orientation.
  static Widget wrapLandscape(BuildContext context, Widget child) {
    if (!kDebugMode) return child;
    if (get('ORIENTATION') != 'landscape') return child;
    final mq = MediaQuery.of(context);
    return RotatedBox(
      quarterTurns: 1,
      child: MediaQuery(
        data: mq.copyWith(
          size: Size(mq.size.height, mq.size.width),
          padding: EdgeInsets.zero,
          viewPadding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
        ),
        child: child,
      ),
    );
  }
}
