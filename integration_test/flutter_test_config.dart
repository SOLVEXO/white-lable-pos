// Integration tests run on a simulator / device with REAL networking (no test-binding HTTP mock), so they must only ever talk to a local API:
// the dev stack (config/env/local.json → :3102) or nothing at all (config/env/dev.json → :3000, for the mocked-repository screenshot tests).
// Without a --dart-define-from-file the app's API falls back to PRODUCTION (ApiConstants.baseUrl), so this refuses to start such a run.
import 'dart:async';

import 'package:solvexo_pos/app/network/api_constaints.dart';

/// Hosts an integration test may send app traffic to: this machine (and the Android emulator's alias for it).
bool isLocalApiHost(String host) => host == 'localhost' || host == '::1' || host.startsWith('127.') || host == '10.0.2.2';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final host = Uri.parse(ApiConstants.baseUrl).host;
  if (!isLocalApiHost(host)) {
    throw StateError(
      'Integration tests must target a LOCAL API, but API_BASE_URL is ${ApiConstants.baseUrl}. '
      'Run with --dart-define-from-file=config/env/local.json (real dev stack) or config/env/dev.json (mocked repositories).',
    );
  }
  await testMain();
}
