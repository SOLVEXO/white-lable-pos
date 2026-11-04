import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs before every test file. Gives `flutter_secure_storage` an in-memory backend, because the stores that encrypt their data
/// (cart snapshot, checkout intents, settings cache, the offline queue) read a key from the platform keychain — with no handler
/// registered that call never completes and the whole test file hangs. A test that needs specific behaviour (a lost key, an
/// inspected keychain class, a failing write) installs its own handler, which replaces this one.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mem = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
    final a = (call.arguments as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
    switch (call.method) {
      case 'write':
        mem[a['key'] as String] = a['value'] as String;
        return null;
      case 'read':
        return mem[a['key'] as String];
      case 'delete':
        mem.remove(a['key'] as String);
        return null;
      case 'deleteAll':
        mem.clear();
        return null;
      case 'containsKey':
        return mem.containsKey(a['key'] as String);
      case 'readAll':
        return Map<String, String>.from(mem);
      default:
        return null;
    }
  });
  await testMain();
}
