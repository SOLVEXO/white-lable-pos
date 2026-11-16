import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:solvexo_pos/app/data/services/server_capabilities.dart';

import 'support/no_network.dart';

/// Runs before every test file. Gives `flutter_secure_storage` an in-memory backend, because the stores that encrypt their data
/// (cart snapshot, checkout intents, settings cache, the offline queue) read a key from the platform keychain — with no handler
/// registered that call never completes and the whole test file hangs. A test that needs specific behaviour (a lost key, an
/// inspected keychain class, a failing write) installs its own handler, which replaces this one.
///
/// It also installs the no-network guard (support/no_network.dart): a test that tries to reach any real host — production, staging, a LAN
/// printer — fails, naming the URL, instead of silently getting the binding's fake 400.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  installNoNetworkGuard(); // after the binding, which installs its own (silent) HttpClient mock
  // The G6.2 capabilities probe runs whenever the sale screen starts; in unit tests it answers "inconclusive" (nothing known) instead of
  // making an HTTP call. Tests about the probe itself install their own (test/g62_capabilities_test.dart).
  setUp(() => ServerCapabilities.probe = () async => const CapabilityProbe.inconclusive());
  tearDown(() {
    if (blockedNetworkAttempts.isEmpty) return;
    final tried = List.of(blockedNetworkAttempts);
    blockedNetworkAttempts.clear();
    fail('This test tried to reach the network (blocked): ${tried.toSet().join(', ')}. Inject a fake repository / HttpClient instead.');
  });
  // A late background call (started by a test, finished after it) is still refused, but would land after that test's tearDown: fail the file.
  tearDownAll(() {
    if (blockedNetworkAttempts.isEmpty) return;
    final tried = List.of(blockedNetworkAttempts);
    blockedNetworkAttempts.clear();
    fail('A test in this file started a network call that finished after it ended (blocked): ${tried.toSet().join(', ')}. Inject a fake.');
  });
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
