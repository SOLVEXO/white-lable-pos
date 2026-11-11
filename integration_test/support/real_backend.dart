// Helpers for the REAL-backend integration tests (no repository fakes, no mocked HTTP): they drive the app's real
// repositories / services / Dio stack against the local dev API (solvexo-api/dev) and read state back through the real API.
// Run via tool/run_real_e2e.sh — it starts the control sidecar (tool/e2e_control_server.mjs) these helpers call.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Seeded by `npm run dev:seed` in solvexo-api (see dev/README.md).
const ownerEmail = 'owner@solvexo.dev';
const ownerPassword = 'DevPass#12345';
const managerEmail = 'manager@solvexo.dev', managerPin = '1111';
const cashierEmail = 'cashier@solvexo.dev', cashierPin = '2222';

/// A plain Dio for things the app itself never does (control sidecar, independent state checks).
final Dio _plain = Dio(BaseOptions(validateStatus: (_) => true, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(minutes: 3)));

/// The test-control sidecar (tool/e2e_control_server.mjs).
class Control {
  static const base = 'http://127.0.0.1:3199';
  static Future<Map<String, dynamic>> call(String path, {Map<String, String>? query}) async {
    final r = await _plain.get('$base$path', queryParameters: query);
    if (r.statusCode != 200) throw StateError('control $path failed: ${r.statusCode} ${r.data}');
    return (r.data is Map ? r.data : jsonDecode(r.data as String)) as Map<String, dynamic>;
  }

  static Future<void> expirePlan() => call('/expire-plan');
  static Future<void> restorePlan() => call('/restore-plan');

  /// G4.8: change one record of the latest sealed day in Mongo (the integrity check must flag it) / put it back exactly.
  static Future<Map<String, dynamic>> tamperSeal() => call('/tamper-seal');
  static Future<Map<String, dynamic>> untamperSeal() => call('/untamper-seal');
  static Future<void> stopApi() => call('/api/stop');
  static Future<void> startApi() => call('/api/start');
  static Future<Map<String, dynamic>> throwawayOwner() => call('/throwaway-owner');
}

/// Independent reads/writes straight against the API with an owner JWT (not through the app's classes).
class Api {
  Api(this.ownerToken);
  final String ownerToken;

  static Future<Api> ownerLogin(String email, String password) async {
    final r = await _plain.post('${AppEnv.apiBaseUrl}/api/auth/login', data: {'email': email, 'password': password, 'role': 'seller'});
    expect(r.statusCode, anyOf(200, 201), reason: 'owner login: ${r.data}');
    return Api(r.data['data']['token']['accessToken'] as String);
  }

  Options get _o => Options(headers: {'Authorization': 'Bearer $ownerToken'});
  Future<Response> get(String p) => _plain.get('${AppEnv.apiBaseUrl}$p', options: _o);
  Future<Response> post(String p, [Object? body]) => _plain.post('${AppEnv.apiBaseUrl}$p', data: body ?? {}, options: _o);

  /// {storeId, registerId} of the seeded "Dev Coffee" store (or the owner's only store).
  Future<({String storeId, String registerId})> mainStore([String name = 'Dev Coffee']) async {
    final r = await get('/api/store/my-stores');
    final stores = (r.data['data'] as List).cast<Map>();
    final s = stores.firstWhere((e) => (e['name'] ?? e['storeName']) == name, orElse: () => stores.first);
    final regs = (s['registers'] as List).cast<Map>();
    return (storeId: s['_id'] as String, registerId: regs.first['_id'] as String);
  }

  Future<Response> patch(String p, Object body, {Map<String, String>? headers}) =>
      _plain.patch('${AppEnv.apiBaseUrl}$p', data: body, options: Options(headers: {'Authorization': 'Bearer $ownerToken', ...?headers}));

  /// Tops a variant up to at least [target] (dev data drifts as tests sell it) via the real inventory adjust route.
  Future<void> topUp(String storeId, String variantId, int current, int target) async {
    if (current >= target) return;
    final r = await patch('/api/inventory/$storeId/variant/$variantId/adjust', {'delta': target - current, 'reason': 'correction'}, headers: {'Idempotency-Key': 'e2e-topup-$variantId-${DateTime.now().microsecondsSinceEpoch}'});
    expect(r.statusCode, anyOf(200, 201), reason: 'top up: ${r.data}');
  }

  /// Revokes every active device of the store through the real API (the backend caps a store at 50 active devices, so tests
  /// that register one per flow must tidy up after themselves).
  Future<void> revokeAllDevices(String storeId) async {
    for (final d in await devices(storeId)) {
      if (d['status'] == 'active') await post('/api/pos/devices/$storeId/${d['_id']}/revoke');
    }
  }

  Future<List<Map>> devices(String storeId) async => ((await get('/api/pos/devices/$storeId')).data['data'] as List).cast<Map>();
}

/// A fully real till: the app's own AuthRepository → PosDeviceService.register → pinLogin, with the same services main.dart
/// puts into GetX (real SQLite queue, real secure storage, real Dio interceptors).
class Till {
  Till._(this.storeId, this.registerId);
  final String storeId, registerId;
  late PosRepository repo;
  late PendingSaleSyncService sync;
  late PosDeviceService devices;
  late PosEntitlementService entitlement;
  PosEmployeeModel? employee;
  String? deviceName;

  static Future<Till> boot({required String storeId, required String registerId, String email = ownerEmail, String password = ownerPassword, bool clearQueue = true}) async {
    Get.reset();
    OwnerSession.end();
    await AppPreferences.clearPreference(); // keeps the queue key, like a real sign-out
    await AppPreferences.warmCache();
    await AppPreferences.setPosSoundEffects(false);
    if (clearQueue) {
      final s = PendingSaleLocalStore();
      for (final r in await s.getAll()) {
        await s.remove(r.id);
      }
    }
    final t = Till._(storeId, registerId);
    await Get.put(NetworkStatusService(), permanent: true).init();
    t.sync = await Get.put(PendingSaleSyncService(hasCredentials: () => (AppPreferences.cachedToken ?? '').isNotEmpty, persistLastSync: false), permanent: true).init().then((_) => Get.find<PendingSaleSyncService>());
    t.entitlement = Get.put(PosEntitlementService(), permanent: true);
    t.devices = Get.put(PosDeviceService(unresolvedSales: () async => Get.find<PendingSaleSyncService>().unresolvedCount.value, onRegistered: () => Get.find<PendingSaleSyncService>().syncNow(ignoreBackoff: true)), permanent: true);
    // what main.dart wires, so a revoked token / forced logout behaves like the shipped app
    DioService.onDeviceRevoked = (code) async => Get.find<PosDeviceService>().handleRevoked(code);
    DioService.onForceLogout = () {};
    t.repo = PosRepository();
    return t;
  }

  /// Owner signs in (real login) and registers this device — the owner JWT is then replaced by the device token.
  Future<DeviceSetupResult> setUpDevice({String email = ownerEmail, String password = ownerPassword, String name = 'E2E iPhone'}) async {
    final auth = await AuthRepository().login(email: email, password: password);
    expect(auth, isNotNull, reason: 'owner login through the app code');
    deviceName = name;
    return devices.register(storeId: storeId, registerId: registerId, name: name, platform: 'ios');
  }

  /// PIN login exactly as PosPinLoginController persists it.
  Future<PosEmployeeModel> pinLogin(String email, String pin) async {
    final r = await repo.pinLogin(storeId: storeId, email: email, pin: pin);
    expect(r.success, isTrue, reason: 'pin login $email: ${r.message}');
    employee = r.employee;
    await AppPreferences.savePosEmployee(id: r.employee!.id, name: r.employee!.name, role: r.employee!.role);
    await AppPreferences.setPosEmployeeEmail(email);
    await AppPreferences.setPosEmployeeToken(r.employeeToken!);
    return r.employee!;
  }

  /// Closes whatever shift is still open on this register (cash counted = expected), so a test starts clean.
  Future<void> closeAnyOpenShift() async {
    final s = await repo.getActiveSession(storeId: storeId, registerId: registerId);
    if (s != null && s.isOpen) {
      final c = await repo.closeSession(sessionId: s.id, closingCash: s.expectedCash);
      expect(c.success, isTrue, reason: 'cleanup close: ${c.message}');
    }
  }

  Future<PosSessionModel> openShift({double openingCash = 100}) async {
    await closeAnyOpenShift();
    final r = await repo.openSession(storeId: storeId, registerId: registerId, employeeId: employee!.id, openingCash: openingCash);
    expect(r.success, isTrue, reason: 'open shift: ${r.message}');
    await AppPreferences.savePosSession(sessionId: r.session!.id, registerId: registerId, shiftId: '');
    return r.session!;
  }

  Future<Map<String, PosProductVariant>> variantsBySku() async {
    final page = await repo.getProducts(storeId, limit: 50);
    final m = <String, PosProductVariant>{};
    for (final p in page.items) {
      for (final v in p.variants) {
        m[v.sku] = v;
      }
    }
    return m;
  }

  Future<Map<String, String>> productIdBySku() async {
    final page = await repo.getProducts(storeId, limit: 50);
    return {for (final p in page.items) for (final v in p.variants) v.sku: p.productId};
  }

  Future<int> stockOf(String sku) async => (await variantsBySku())[sku]!.stock;

  Future<Map<String, dynamic>> line(String sku, int qty) async {
    final v = (await variantsBySku())[sku]!;
    final pid = (await productIdBySku())[sku]!;
    return {'productId': pid, 'variantId': v.variantId, 'qty': qty};
  }

  Future<void> dispose() async {
    OwnerSession.end();
    Get.reset();
  }
}

/// Polls [cond] (real time) — the iOS test binding gives no fake clock for real I/O.
Future<void> eventually(Future<bool> Function() cond, {Duration timeout = const Duration(seconds: 30), String? reason}) async {
  final end = DateTime.now().add(timeout);
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('timed out: ${reason ?? 'condition'}');
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

bool get isSimulatorHost => Platform.isIOS;
