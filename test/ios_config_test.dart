// 5F.1 — static guards on the iOS project so a capability / build phase can't silently disappear.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();

  test('Sign in with Apple entitlement exists and is wired into Debug, Release and Profile of the Runner target', () {
    expect(File('ios/Runner/Runner.entitlements').readAsStringSync(), contains('com.apple.developer.applesignin'));
    expect('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'.allMatches(pbx).length, 3);
  });

  test('Crashlytics dSYM upload phase is part of the Runner target and comes after the embed/thin phases', () {
    expect(pbx, contains('Crashlytics dSYM Upload'));
    expect(pbx, contains(r'"${PODS_ROOT}/FirebaseCrashlytics/run'));
    final phases = pbx.substring(pbx.indexOf('97C146ED1CF9000F007C117D /* Runner */ = {'));
    expect(phases.indexOf('Crashlytics dSYM Upload'), greaterThan(phases.indexOf('[CP] Copy Pods Resources')));
    expect(pbx, contains('DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"')); // release builds produce dSYMs
  });
}
