// 5D — shared-device security: device registration/revocation (queue preserved), owner-only gating, auto-lock, sign-out rules.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_device_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_device_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/owner_gate.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/owner_gate_view.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/pos_devices_view.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/pos_lock_overlay.dart';
import 'package:solvexo_pos/app/network/dio_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class MockDeviceRepo extends Mock implements PosDeviceRepository {}

class MockPosRepo extends Mock implements PosRepository {}

class MockAuthRepo extends Mock implements AuthRepository {}

final _secure = <String, String>{};

void _mockSecureStorage() {
  _secure.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
    final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
    switch (call.method) {
      case 'write':
        _secure[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return _secure[args['key'] as String];
      case 'delete':
        _secure.remove(args['key'] as String);
        return null;
      case 'deleteAll':
        _secure.clear();
        return null;
      case 'readAll':
        return Map<String, String>.from(_secure);
      case 'containsKey':
        return _secure.containsKey(args['key'] as String);
      default:
        return null;
    }
  });
}

QueueCipher _testCipher() => AesGcmQueueCipher(fixedKey: SecretKey(List<int>.generate(32, (i) => i)));

PosEmployeeModel _employee(String id) => PosEmployeeModel.fromJson({'_id': id, 'name': 'Cal', 'email': 'c@x.com', 'role': 'cashier'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    Get.reset();
    SharedPreferences.setMockInitialValues({});
    _mockSecureStorage();
    await AppPreferences.warmCache();
    OwnerSession.clock = DateTime.now;
    OwnerSession.end();
  });

  group('which routes need the owner, and which credential a request carries', () {
    test('owner-only routes', () {
      for (final r in const [
        ('GET', '/api/pos/employees/s1'),
        ('POST', '/api/pos/employees'),
        ('PATCH', '/api/pos/employees/s1/e1'),
        ('POST', '/api/pos/employees/s1/e1/reset-pin'),
        ('GET', '/api/pos/locations/s1'),
        ('POST', '/api/pos/registers/s1'),
        ('PATCH', '/api/pos/settings/s1'),
        ('POST', '/api/pos/shifts/s1'),
        ('GET', '/api/pos/devices/s1'),
        ('POST', '/api/pos/devices'),
        ('POST', '/api/pos/devices/s1/d1/revoke'),
        ('POST', '/api/pos/sessions/abc/force-close'),
        ('POST', '/api/inventory/s1/variant/v1/adjust'),
        ('GET', '/api/products/p1/variants'),
        ('GET', '/api/activity-log/s1'),
        ('GET', '/api/store/s1/customers?page=1'),
      ]) {
        expect(OwnerRoutes.requiresOwner(r.$1, r.$2), isTrue, reason: '${r.$1} ${r.$2}');
      }
    });

    test('operational routes stay open to the device token', () {
      for (final r in const [
        ('POST', '/api/pos/pin-login'),
        ('POST', '/api/pos/pin-logout'),
        ('POST', '/api/pos/sales'),
        ('POST', '/api/pos/sales/quote'),
        ('POST', '/api/pos/sales/s1/refund'),
        ('GET', '/api/pos/sales/held'),
        ('POST', '/api/pos/sessions/open'),
        ('POST', '/api/pos/sessions/close'),
        ('GET', '/api/pos/registers/s1'),
        ('GET', '/api/pos/settings/s1'),
        ('GET', '/api/pos/products/s1'),
        ('GET', '/api/pos/inventory/s1'),
        ('GET', '/api/pos/inventory/s1/low-stock'),
        ('GET', '/api/pos/subscription/s1'),
        ('GET', '/api/pos/devices/me'),
        ('POST', '/api/pos/devices/me/sign-out'),
        ('GET', '/api/pos/reports/daily'),
      ]) {
        expect(OwnerRoutes.requiresOwner(r.$1, r.$2), isFalse, reason: '${r.$1} ${r.$2}');
      }
    });

    test('a registered device uses the owner session for owner routes (only while it is live) and the device token otherwise', () {
      expect(DioService.tokenFor('PATCH', '/api/pos/settings/s1', 'DEVICE', deviceMode: true), 'DEVICE'); // no owner session → device token (server says no)
      OwnerSession.start('OWNER');
      expect(DioService.tokenFor('PATCH', '/api/pos/settings/s1', 'DEVICE', deviceMode: true), 'OWNER');
      expect(DioService.tokenFor('POST', '/api/pos/sales', 'DEVICE', deviceMode: true), 'DEVICE'); // operational calls NEVER carry the owner token
      expect(DioService.tokenFor('PATCH', '/api/pos/settings/s1', 'OWNER-LEGACY', deviceMode: false), 'OWNER-LEGACY'); // not registered yet: unchanged
    });
  });

  group('owner session', () {
    test('expires after the window, slides on use, and ends explicitly', () {
      var now = DateTime(2026, 1, 1, 9);
      OwnerSession.clock = () => now;
      OwnerSession.start('T');
      expect(OwnerSession.token, 'T');
      now = now.add(const Duration(minutes: 9));
      OwnerSession.touch(); // using an owner screen extends it
      now = now.add(const Duration(minutes: 9));
      expect(OwnerSession.isActive, isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(OwnerSession.isActive, isFalse);
      expect(OwnerSession.token, isNull);
      OwnerSession.start('U');
      OwnerSession.end();
      expect(OwnerSession.token, isNull);
    });

    test('OwnerGate: nothing to gate before registration; a live owner session passes without asking', () async {
      expect(OwnerGate.required, isFalse);
      expect(await OwnerGate.ensure(), isTrue);
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'n', storeId: 's1', registerId: 'r1');
      expect(OwnerGate.required, isTrue);
      OwnerSession.start('OWNER');
      expect(OwnerGate.required, isFalse);
      expect(await OwnerGate.ensure(), isTrue);
    });

    testWidgets('gate screen: wrong password is refused; the right one starts the owner session', (tester) async {
      await AppPreferences.setTokens(accessToken: 'x', refreshToken: 'y');
      SharedPreferences.setMockInitialValues({'user_email': 'owner@x.com'});
      final auth = MockAuthRepo();
      when(() => auth.verifyOwnerPassword(email: 'owner@x.com', password: 'bad')).thenAnswer((_) async => null);
      when(() => auth.verifyOwnerPassword(email: 'owner@x.com', password: 'good')).thenAnswer((_) async => 'OWNER-JWT');
      await tester.pumpWidget(GetMaterialApp(home: OwnerGateView(authRepository: auth)));
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byKey(const Key('ownerGatePassword')), 'bad');
      await tester.tap(find.byKey(const Key('ownerGateContinue')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('That password did not work.'), findsOneWidget);
      expect(OwnerSession.isActive, isFalse);

      await tester.enterText(find.byKey(const Key('ownerGatePassword')), 'good');
      await tester.tap(find.byKey(const Key('ownerGateContinue')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(OwnerSession.token, 'OWNER-JWT');
      // the owner's JWT lives in memory only — never in the stored credential slot
      expect(await AppPreferences.getAccessTokenAsync(), 'x');
    });
  });

  group('device registration', () {
    test('registering swaps the owner session for the device token and discards the owner refresh token', () async {
      await AppPreferences.setTokens(accessToken: 'OWNER-JWT', refreshToken: 'OWNER-REFRESH');
      final repo = MockDeviceRepo();
      when(() => repo.register(storeId: 's1', registerId: 'r1', name: 'Front', platform: 'ios')).thenAnswer((_) async => const PosDeviceRegistration(deviceId: 'd1', deviceToken: 'DEVICE-TOKEN'));
      var synced = 0;
      final svc = PosDeviceService(repository: repo, unresolvedSales: () async => 0, onRegistered: () async => synced++);

      expect(await svc.register(storeId: 's1', registerId: 'r1', name: 'Front', platform: 'ios'), DeviceSetupResult.ok);
      expect(await AppPreferences.getAccessTokenAsync(), 'DEVICE-TOKEN');
      expect(await AppPreferences.getRefreshToken(), isNull);
      expect(AppPreferences.cachedDeviceMode, isTrue);
      expect(AppPreferences.cachedToken, 'DEVICE-TOKEN');
      expect((await AppPreferences.getDeviceRegistration()).registerId, 'r1');
      expect(synced, 1); // the offline queue starts draining
    });

    test('a failed registration changes nothing', () async {
      await AppPreferences.setTokens(accessToken: 'OWNER-JWT', refreshToken: 'R');
      final repo = MockDeviceRepo();
      when(() => repo.register(storeId: any(named: 'storeId'), registerId: any(named: 'registerId'), name: any(named: 'name'), platform: any(named: 'platform'))).thenAnswer((_) async => null);
      final svc = PosDeviceService(repository: repo, unresolvedSales: () async => 0);
      expect(await svc.register(storeId: 's1', registerId: 'r1', name: 'x'), DeviceSetupResult.failed);
      expect(await AppPreferences.getAccessTokenAsync(), 'OWNER-JWT');
      expect(AppPreferences.cachedDeviceMode, isFalse);
    });
  });

  group('revoked device: back to setup, unsynced sales preserved, re-register for the SAME store only', () {
    late Directory tmp;
    late PendingSaleLocalStore store;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('rev_');
      store = PendingSaleLocalStore(dbPath: '${tmp.path}/q.db', cipher: _testCipher());
    });
    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    test('revocation clears credentials + employee/session but keeps the queue, its key, caches and the store binding', () async {
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'Front', storeId: 's1', registerId: 'r1');
      await AppPreferences.setPosEmployeeToken('EMP');
      await AppPreferences.savePosEmployee(id: 'e1', name: 'Cal', role: 'cashier');
      await AppPreferences.savePosSession(sessionId: 'sess', registerId: 'r1', shiftId: 'sh');
      await AppPreferences.setString('cache_catalog', '{"x":1}');
      _secure[AesGcmQueueCipher.storageKey] = 'queue-key-material';
      await store.enqueue('k1', {'storeId': 's1', 'sessionId': 'sess', 'employeeId': 'e1', 'items': <dynamic>[]});

      await PosDeviceService(unresolvedSales: () async => 1).handleRevoked('POS_DEVICE_REVOKED');

      expect(await AppPreferences.getAccessTokenAsync(), isNull);
      expect(AppPreferences.cachedToken, isNull);
      expect(AppPreferences.cachedDeviceMode, isFalse);
      expect(await AppPreferences.getPosEmployeeToken(), isNull);
      expect(await AppPreferences.getPosSessionId(), isNull);
      expect(await AppPreferences.getString('cache_catalog'), '{"x":1}'); // caches kept
      expect((await AppPreferences.getDeviceRegistration()).storeId, 's1'); // binding kept
      expect(_secure[AesGcmQueueCipher.storageKey], 'queue-key-material'); // the queue stays decryptable
      expect((await store.getAll()).single.id, 'k1');
      expect((await store.getAll()).single.unreadable, isFalse);
    });

    test('the Dio layer turns a POS_DEVICE_REVOKED 401 into exactly that — and NOT a wipe-everything logout', () async {
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'Front', storeId: 's1', registerId: 'r1');
      _secure[AesGcmQueueCipher.storageKey] = 'queue-key-material';
      String? seen;
      var forced = 0;
      DioService.onDeviceRevoked = (c) => seen = c;
      DioService.onForceLogout = () => forced++;
      final dio = await DioService.getDio();
      dio.httpClientAdapter = _FakeAdapter(401, {'statusCode': 401, 'code': 'POS_DEVICE_REVOKED', 'message': 'removed'});
      await expectLater(dio.get('https://x.test/api/pos/sales', options: Options(extra: {'requiresAuth': true})), throwsA(isA<DioException>()));
      expect(seen, 'POS_DEVICE_REVOKED');
      expect(forced, 0);
      expect(await AppPreferences.getAccessTokenAsync(), isNull);
      expect(_secure[AesGcmQueueCipher.storageKey], 'queue-key-material');
      expect((await AppPreferences.getDeviceRegistration()).storeId, 's1');
    });

    test('POS_LEGACY_AUTH_DISABLED (403) asks the app for device setup and wipes nothing', () async {
      await AppPreferences.setTokens(accessToken: 'OWNER-JWT', refreshToken: 'R');
      await AppPreferences.savePosSession(sessionId: 'sess', registerId: 'r', shiftId: 'sh');
      _secure[AesGcmQueueCipher.storageKey] = 'k';
      var asked = 0, forced = 0;
      DioService.onLegacyAuthDisabled = () => asked++;
      DioService.onForceLogout = () => forced++;
      final dio = await DioService.getDio();
      dio.httpClientAdapter = _FakeAdapter(403, {'statusCode': 403, 'code': 'POS_LEGACY_AUTH_DISABLED', 'message': 'x'});
      await expectLater(dio.get('https://x.test/api/pos/sales', options: Options(extra: {'requiresAuth': true})), throwsA(isA<DioException>()));
      expect(asked, 1);
      expect(forced, 0);
      expect(await AppPreferences.getAccessTokenAsync(), 'OWNER-JWT'); // the owner session is needed to register
      expect(await AppPreferences.getPosSessionId(), 'sess');
      expect(_secure[AesGcmQueueCipher.storageKey], 'k');
    });

    test('an expired OWNER session (401 on an owner route) only ends that session — the device stays registered', () async {
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'Front', storeId: 's1', registerId: 'r1');
      OwnerSession.start('OLD-OWNER');
      var revoked = 0, forced = 0;
      DioService.onDeviceRevoked = (_) => revoked++;
      DioService.onForceLogout = () => forced++;
      final dio = await DioService.getDio();
      dio.httpClientAdapter = _FakeAdapter(401, {'statusCode': 401, 'message': 'Unauthorized'});
      await expectLater(dio.patch('https://x.test/api/pos/settings/s1', options: Options(extra: {'requiresAuth': true})), throwsA(isA<DioException>()));
      expect(OwnerSession.isActive, isFalse);
      expect(revoked + forced, 0);
      expect(AppPreferences.cachedDeviceMode, isTrue);
      expect(await AppPreferences.getAccessTokenAsync(), 'D');
    });

    test('re-registering for the same store is fine; a different store is refused while sales are unsynced (and allowed when none)', () async {
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'Front', storeId: 's1', registerId: 'r1');
      var unresolved = 2;
      final repo = MockDeviceRepo();
      when(() => repo.register(storeId: any(named: 'storeId'), registerId: any(named: 'registerId'), name: any(named: 'name'), platform: any(named: 'platform')))
          .thenAnswer((_) async => const PosDeviceRegistration(deviceId: 'd2', deviceToken: 'D2'));
      final svc = PosDeviceService(repository: repo, unresolvedSales: () async => unresolved);
      await svc.handleRevoked('POS_DEVICE_REVOKED');
      expect(await svc.register(storeId: 's2', registerId: 'r9', name: 'x'), DeviceSetupResult.otherStoreWithUnsyncedSales);
      verifyNever(() => repo.register(storeId: 's2', registerId: any(named: 'registerId'), name: any(named: 'name'), platform: any(named: 'platform')));
      expect(await svc.register(storeId: 's1', registerId: 'r1', name: 'x'), DeviceSetupResult.ok);

      await svc.handleRevoked('POS_DEVICE_REVOKED');
      unresolved = 0;
      expect(await svc.register(storeId: 's2', registerId: 'r9', name: 'x'), DeviceSetupResult.ok); // nothing left to protect
    });

    test('the sync queue waits while the device has no credential, and drains once it is registered again', () async {
      final repo = MockPosRepo();
      var hasCred = false;
      final sent = <String>[];
      when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((i) async {
        sent.add((i.positionalArguments.first as Map)['idempotencyKey'] as String? ?? '?');
        return (success: true, connectivityError: false, retryable: false, message: null, code: null);
      });
      final svc = PendingSaleSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's1', persistLastSync: false, hasCredentials: () => hasCred);
      await store.enqueue('k1', {'storeId': 's1', 'sessionId': 'A', 'idempotencyKey': 'k1', 'items': <dynamic>[]});
      await svc.syncNow();
      expect(sent, isEmpty);
      expect((await store.getAll()), hasLength(1)); // nothing dropped
      hasCred = true; // owner registers the device again
      await svc.syncNow();
      expect(sent, ['k1']);
    });
  });

  group('sign-out / device reset', () {
    test('blocked while any sale is unsynced; otherwise clears credentials and caches (and the queue key, as the queue is empty)', () async {
      await AppPreferences.saveDeviceRegistration(deviceToken: 'D', deviceId: 'd1', name: 'Front', storeId: 's1', registerId: 'r1');
      await AppPreferences.setString('cache_catalog', 'x');
      _secure[AesGcmQueueCipher.storageKey] = 'k';
      final repo = MockDeviceRepo();
      when(() => repo.signOutSelf()).thenAnswer((_) async {});
      var unresolved = 3;
      final svc = PosDeviceService(repository: repo, unresolvedSales: () async => unresolved);

      expect(await svc.reset(), DeviceResetResult.blockedByUnsyncedSales);
      expect(await AppPreferences.getAccessTokenAsync(), 'D');
      expect(_secure[AesGcmQueueCipher.storageKey], 'k');
      verifyNever(() => repo.signOutSelf());

      unresolved = 0;
      expect(await svc.reset(), DeviceResetResult.done);
      verify(() => repo.signOutSelf()).called(1); // the token is retired server-side too
      expect(await AppPreferences.getAccessTokenAsync(), isNull);
      expect(await AppPreferences.getString('cache_catalog'), isNull);
      expect(AppPreferences.cachedDeviceMode, isFalse);
      expect(_secure.containsKey(AesGcmQueueCipher.storageKey), isFalse);
    });

    test('an ordinary clearPreference (e.g. a legacy forced logout) never destroys the queue key', () async {
      _secure[AesGcmQueueCipher.storageKey] = 'k';
      _secure['token'] = 't';
      await AppPreferences.clearPreference();
      expect(_secure, {AesGcmQueueCipher.storageKey: 'k'});
      await AppPreferences.clearPreference(wipeQueueKey: true);
      expect(_secure, isEmpty);
    });
  });

  group('auto-lock', () {
    late DateTime now;
    late bool signedIn;
    late MockPosRepo repo;
    late IdleLockService lock;

    setUp(() async {
      now = DateTime(2026, 1, 1, 9);
      signedIn = true;
      repo = MockPosRepo();
      SharedPreferences.setMockInitialValues({'pos_sound_effects': false, 'pos_auto_lock_minutes': 5, 'store_id': 's1', 'pos_employee_id': 'e1', 'pos_employee_name': 'Cal', 'pos_employee_email': 'c@x.com'});
      lock = IdleLockService(posRepository: repo, clock: () => now, employeeSignedIn: () => signedIn, checkEvery: const Duration(days: 1));
      lock.onInit();
      await Future<void>.delayed(const Duration(milliseconds: 20)); // minutes load
    });
    tearDown(() => lock.onClose());

    test('locks after the owner-set idle time — not before', () {
      now = now.add(const Duration(minutes: 4, seconds: 59));
      lock.checkIdle();
      expect(lock.locked.value, isFalse);
      now = now.add(const Duration(seconds: 2));
      lock.checkIdle();
      expect(lock.locked.value, isTrue);
    });

    test('any touch resets the idle clock', () {
      now = now.add(const Duration(minutes: 4));
      lock.onActivity();
      now = now.add(const Duration(minutes: 4));
      lock.checkIdle();
      expect(lock.locked.value, isFalse);
      now = now.add(const Duration(minutes: 2));
      lock.checkIdle();
      expect(lock.locked.value, isTrue);
    });

    test('follows the minutes the owner set (1–240) and never locks an app nobody is signed in to', () async {
      await lock.setMinutes(1);
      now = now.add(const Duration(seconds: 61));
      signedIn = false;
      lock.checkIdle();
      expect(lock.locked.value, isFalse);
      signedIn = true;
      lock.checkIdle();
      expect(lock.locked.value, isTrue);
    });

    test('locking ends the owner\'s elevated session, but touches nothing else (session, employee context stay)', () async {
      await AppPreferences.savePosSession(sessionId: 'sess', registerId: 'r', shiftId: 'sh');
      OwnerSession.start('OWNER');
      await lock.lock();
      expect(OwnerSession.isActive, isFalse);
      expect(await AppPreferences.getPosSessionId(), 'sess');
      expect(await AppPreferences.getPosEmployeeId(), 'e1');
    });

    test('while locked, activity does not unlock; the right PIN of the SAME employee does and swaps the token (old one retired)', () async {
      await AppPreferences.setPosEmployeeToken('OLD-TOKEN');
      await lock.lock();
      lock.onActivity();
      expect(lock.locked.value, isTrue);

      when(() => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '1234')).thenAnswer((_) async => (success: true, employee: _employee('e1'), activeSession: null, employeeToken: 'NEW-TOKEN', message: null));
      when(() => repo.pinLogoutWith('s1', 'OLD-TOKEN')).thenAnswer((_) async {});
      expect(await lock.unlock('1234'), UnlockResult.ok);
      expect(lock.locked.value, isFalse);
      expect(await AppPreferences.getPosEmployeeToken(), 'NEW-TOKEN');
      verify(() => repo.pinLogoutWith('s1', 'OLD-TOKEN')).called(1);
    });

    test('a wrong PIN, or another employee\'s PIN, stays locked', () async {
      await AppPreferences.setPosEmployeeToken('OLD-TOKEN');
      await lock.lock();
      when(() => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '0000')).thenAnswer((_) async => (success: false, employee: null, activeSession: null, employeeToken: null, message: 'Invalid credentials'));
      expect(await lock.unlock('0000'), UnlockResult.wrongPin);
      when(() => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '5555')).thenAnswer((_) async => (success: true, employee: _employee('someone-else'), activeSession: null, employeeToken: 'T2', message: null));
      expect(await lock.unlock('5555'), UnlockResult.differentEmployee);
      expect(lock.locked.value, isTrue);
      expect(await AppPreferences.getPosEmployeeToken(), 'OLD-TOKEN'); // the other person's token was never adopted
    });

    testWidgets('the overlay covers the screen WITHOUT discarding what is underneath (cart state survives lock + unlock)', (tester) async {
      Get.put<IdleLockService>(lock);
      final counter = ValueNotifier<int>(0);
      await tester.pumpWidget(GetMaterialApp(home: PosLockOverlay(child: Scaffold(body: ValueListenableBuilder<int>(valueListenable: counter, builder: (_, v, __) => Text('cart items: $v', key: const Key('cart'))))))); 
      counter.value = 3; // "the cashier has 3 items in the cart"
      await tester.pump();
      await tester.runAsync(() => lock.lock());
      await tester.pump();
      expect(find.text('Locked'), findsOneWidget);
      expect(find.byKey(const Key('cart')), findsOneWidget); // still mounted underneath, state intact

      when(() => repo.pinLogin(storeId: 's1', email: 'c@x.com', pin: '1234')).thenAnswer((_) async => (success: true, employee: _employee('e1'), activeSession: null, employeeToken: 'N', message: null));
      await tester.enterText(find.byKey(const Key('lockPin')), '1234');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(find.text('Locked'), findsNothing);
      expect(find.text('cart items: 3'), findsOneWidget);
      lock.onClose(); // stop the idle timer before the test ends
    });
  });

  group('owner devices screen', () {
    testWidgets('lists devices and revokes one after confirmation', (tester) async {
      SharedPreferences.setMockInitialValues({'pos_sound_effects': false, 'store_id': 's1', 'pos_device_id': 'd1'});
      final repo = MockDeviceRepo();
      final devices = [
        PosDeviceModel(id: 'd1', name: 'Front iPad', registerId: 'r1', revoked: false, lastSeenAt: DateTime(2026, 1, 1)),
        PosDeviceModel(id: 'd2', name: 'Back counter', registerId: 'r2', revoked: false, lastSeenAt: DateTime(2026, 1, 1)),
      ];
      when(() => repo.list('s1')).thenAnswer((_) async => devices);
      when(() => repo.revoke('s1', 'd2')).thenAnswer((_) async => true);
      await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(home: PosDevicesView(repository: repo))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(find.textContaining('Front iPad'), findsOneWidget);
      expect(find.textContaining('(this device)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('revoke-d2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revoke').last);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(seconds: 4));
      verify(() => repo.revoke('s1', 'd2')).called(1);
    });
  });
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});

  @override
  void close({bool force = false}) {}
}
