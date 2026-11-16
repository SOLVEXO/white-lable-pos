import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The device's appearance choice (G6.4). A DEVICE preference, not a store setting: every role may change it, it is saved locally only,
/// and it survives sign-out (AppPreferences.clearPreference keeps [prefsKey]).
enum AppearanceChoice {
  system('System', 'Follow the device setting'),
  light('Light', 'Always light'),
  dark('Dark', 'Always dark');

  const AppearanceChoice(this.label, this.description);
  final String label;
  final String description;

  ThemeMode get themeMode => switch (this) { system => ThemeMode.system, light => ThemeMode.light, dark => ThemeMode.dark };

  static AppearanceChoice parse(String? s) => AppearanceChoice.values.firstWhere((c) => c.name == s, orElse: () => system);
}

/// Holds the choice the app root (`MyApp`) observes: changing it re-themes every open screen at once, no restart.
/// Default = [AppearanceChoice.system]. The splash and the native launch screen keep their fixed ink; printed output, PDFs and QR codes
/// use fixed colours and are not affected.
class ThemePreference extends GetxService {
  ThemePreference({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;

  static const prefsKey = 'device_appearance';

  final Future<SharedPreferences> Function() _prefs;
  final Rx<AppearanceChoice> choice = AppearanceChoice.system.obs;

  ThemeMode get themeMode => choice.value.themeMode;

  /// Reads the saved choice (call once before the first frame).
  Future<ThemePreference> init() async {
    try {
      choice.value = AppearanceChoice.parse((await _prefs()).getString(prefsKey));
    } catch (_) {
      choice.value = AppearanceChoice.system;
    }
    return this;
  }

  /// Applies at once (observers rebuild) and saves for the next start.
  Future<void> set(AppearanceChoice c) async {
    choice.value = c;
    try {
      await (await _prefs()).setString(prefsKey, c.name);
    } catch (_) {/* the choice still applies for this run */}
  }

  /// The mode the app uses when no service is registered (tests, early boot).
  static ThemeMode get current => Get.isRegistered<ThemePreference>() ? Get.find<ThemePreference>().themeMode : ThemeMode.system;
}
