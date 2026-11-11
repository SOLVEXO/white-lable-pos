import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/config/app_version.dart';

/// G5.1: the About screen's version must be the one the store builds ship with.
void main() {
  test('AppVersion matches pubspec.yaml (bump both together)', () {
    final m = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec.yaml has no "version: x.y.z+n" line');
    expect([AppVersion.version, AppVersion.build], [m!.group(1), m.group(2)]);
  });
}
