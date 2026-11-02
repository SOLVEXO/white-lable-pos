// The offline queue's lifecycle against a real SQLite (in-memory via sqflite_common_ffi) and a mocked repository:
// FIFO per session, one in flight, exponential backoff, a definite server "no" is KEPT (never dropped), retry,
// manager discard that stays on the device until it is in the audit log, store scoping, persistence across a
// restart, and the v1 → v2 database migration.

import 'package:cryptography/cryptography.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';

class MockPosRepository extends Mock implements PosRepository {}

typedef RawResult = ({bool success, bool connectivityError, bool retryable, String? message, String? code});
const RawResult ok = (success: true, connectivityError: false, retryable: false, message: null, code: null);
const RawResult offline = (success: false, connectivityError: true, retryable: true, message: null, code: null);
const RawResult serverDown = (success: false, connectivityError: false, retryable: true, message: 'boom', code: null);
RawResult rejected(String code, String message) => (success: false, connectivityError: false, retryable: false, message: message, code: code);

Map<String, dynamic> payload(String session, {String store = 's1', double total = 10}) => {
      'storeId': store, 'sessionId': session, 'items': [{'variantId': 'v', 'qty': 2}], 'clientTotal': total,
      'clientCreatedAt': '2026-11-02T10:00:00.000Z', 'settingsVersion': 3, 'offline': true,
    };

AesGcmQueueCipher testCipher([int seed = 7]) => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, seed)));

void main() {
  late Directory tmp;
  late String dbFile;
  late MockPosRepository repo;
  late DateTime now;
  late PendingSaleLocalStore store;
  late PendingSaleSyncService svc;
  var currentStore = 's1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Get.testMode = true;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pos_queue_');
    dbFile = '${tmp.path}/q.db';
    repo = MockPosRepository();
    now = DateTime(2026, 11, 2, 12);
    currentStore = 's1';
    store = PendingSaleLocalStore(dbPath: dbFile, cipher: testCipher());
    svc = PendingSaleSyncService(posRepository: repo, localStore: store, currentStoreId: () async => currentStore, clock: () => now, persistLastSync: false);
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  void stubSubmit(Future<RawResult> Function(Map<String, dynamic>) f) {
    when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((i) => f(i.positionalArguments.first as Map<String, dynamic>));
  }

  group('queue storage', () {
    test('enqueue keeps the idempotency key as the id and is idempotent — the same intent queued twice does not reset it', () async {
      await store.enqueue('k1', payload('A'));
      await store.markFailed('k1', 'rejected', errorCode: 'X');
      await store.enqueue('k1', payload('A')); // e.g. an ambiguous retry queueing the same sale again
      final r = (await store.getById('k1'))!;
      expect(r.status, 'failed', reason: 'a re-queue must not resurrect or reset a decided row');
      expect(await store.countUnresolved(), 1);
    });

    test('rows survive a restart (a brand-new store object on the same file sees them) with everything the replay needs', () async {
      await store.enqueue('k1', payload('A'), employeeToken: 'tok');
      await store.close();
      final reopened = PendingSaleLocalStore(dbPath: dbFile, cipher: testCipher());
      final r = (await reopened.getById('k1'))!;
      expect(r.id, 'k1');
      expect(r.payload['settingsVersion'], 3);
      expect(r.payload['clientCreatedAt'], '2026-11-02T10:00:00.000Z');
      expect(r.sessionId, 'A');
      expect(r.storeId, 's1');
      expect(r.employeeToken, 'tok');
      expect(r.madeAt.toUtc(), DateTime.utc(2026, 11, 2, 10));
      await reopened.close();
    });

    test('v1 database is migrated to v2 in place; old rows keep their data and gain store/session columns', () async {
      final v1 = await databaseFactoryFfi.openDatabase(dbFile, options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await db.execute('CREATE TABLE pending_sales (id TEXT PRIMARY KEY, payload TEXT NOT NULL, status TEXT NOT NULL, errorMessage TEXT, createdAt TEXT NOT NULL)');
        await db.insert('pending_sales', {'id': 'old-1', 'payload': '{"storeId":"s1","sessionId":"A","items":[]}', 'status': 'pending', 'createdAt': '2026-11-01T09:00:00.000'});
        await db.insert('pending_sales', {'id': 'old-2', 'payload': '{"storeId":"s1","sessionId":"A","items":[]}', 'status': 'failed', 'errorMessage': 'nope', 'createdAt': '2026-11-01T09:05:00.000'});
      }));
      await v1.close();

      final rows = await PendingSaleLocalStore(dbPath: dbFile, cipher: testCipher()).getAll();
      expect(rows.map((r) => r.id), ['old-1', 'old-2']);
      expect(rows[0].sessionId, 'A');
      expect(rows[0].storeId, 's1');
      expect(rows[1].isFailed, isTrue);
      expect(rows[1].errorMessage, 'nope');
      expect(rows[0].attempts, 0);
    });

    test('counts: unresolved = pending + failed, scoped by session and store; discarding rows are not unresolved', () async {
      await store.enqueue('a1', payload('A'));
      await store.enqueue('a2', payload('A'));
      await store.enqueue('b1', payload('B'));
      await store.enqueue('x1', payload('A', store: 's2'));
      await store.markFailed('a2', 'no');
      await store.markDiscarding('b1', reason: 'customer left', discardedBy: 'e1');
      expect(await store.countUnresolved(), 3); // a1, a2, x1
      expect(await store.countUnresolved(sessionId: 'A'), 3);
      expect(await store.countUnresolved(sessionId: 'B'), 0);
      expect(await store.countUnresolved(storeId: 's1'), 2);
      expect(await store.countPending(), 2);
      expect(await store.countFailed(), 1);
    });
  });

  group('sync', () {
    test('success removes the row and records the last successful sync', () async {
      await store.enqueue('k1', payload('A'));
      stubSubmit((_) async => ok);
      await svc.syncNow();
      expect(await store.getAll(), isEmpty);
      expect(svc.lastSuccessfulSync.value, now);
      expect(svc.unresolvedCount.value, 0);
    });

    test('replays with the ORIGINAL payload: same key row, clientCreatedAt, settingsVersion, sessionId, and the saved employee token', () async {
      await store.enqueue('k1', payload('A'), employeeToken: 'tok-1');
      Map<String, dynamic>? sent;
      String? token;
      when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((i) async {
        sent = i.positionalArguments.first as Map<String, dynamic>;
        token = i.namedArguments[#employeeToken] as String?;
        return ok;
      });
      await svc.syncNow();
      expect(sent!['clientCreatedAt'], '2026-11-02T10:00:00.000Z');
      expect(sent!['settingsVersion'], 3);
      expect(sent!['sessionId'], 'A');
      expect(sent!['offline'], true);
      expect(token, 'tok-1');
    });

    test('FIFO per session: oldest first, one at a time', () async {
      await store.enqueue('k1', payload('A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.enqueue('k2', payload('A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.enqueue('k3', payload('A'));
      final order = <String>[];
      var inFlight = 0;
      var maxInFlight = 0;
      stubSubmit((p) async {
        inFlight++;
        maxInFlight = inFlight > maxInFlight ? inFlight : maxInFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        order.add((p['items'] as List).length.toString());
        inFlight--;
        return ok;
      });
      await svc.syncNow();
      expect(maxInFlight, 1);
      expect((await store.getAll()), isEmpty);
    });

    test('concurrent syncNow calls collapse into ONE pass (a mutex), so a sale is never in flight twice', () async {
      await store.enqueue('k1', payload('A'));
      var calls = 0;
      stubSubmit((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return ok;
      });
      await Future.wait([svc.syncNow(), svc.syncNow(), svc.syncNow()]);
      expect(calls, 1);
    });

    test('a retryable failure keeps the sale PENDING, counts the attempt and backs off exponentially', () async {
      await store.enqueue('k1', payload('A'));
      stubSubmit((_) async => serverDown);
      await svc.syncNow();
      var r = (await store.getById('k1'))!;
      expect(r.isPending, isTrue);
      expect(r.attempts, 1);
      expect(r.nextAttemptAt, now.add(PendingSaleSyncService.backoff(0)));

      // not due yet → untouched
      var calls = 0;
      stubSubmit((_) async { calls++; return serverDown; });
      await svc.syncNow();
      expect(calls, 0, reason: 'must not hammer the server before the backoff elapses');

      // due → tried again, the delay doubles
      now = now.add(const Duration(seconds: 6));
      await svc.syncNow();
      r = (await store.getById('k1'))!;
      expect(calls, 1);
      expect(r.attempts, 2);
      expect(r.nextAttemptAt, now.add(PendingSaleSyncService.backoff(1)));
      expect(PendingSaleSyncService.backoff(1), PendingSaleSyncService.backoff(0) * 2);
    });

    test('backoff doubles from 5s and is capped at 15 minutes', () {
      expect(PendingSaleSyncService.backoff(0), const Duration(seconds: 5));
      expect(PendingSaleSyncService.backoff(1), const Duration(seconds: 10));
      expect(PendingSaleSyncService.backoff(2), const Duration(seconds: 20));
      expect(PendingSaleSyncService.backoff(5), const Duration(seconds: 160));
      expect(PendingSaleSyncService.backoff(20), const Duration(minutes: 15));
    });

    test('a sale backing off GATES the later sales of its session, but other sessions still sync', () async {
      await store.enqueue('a1', payload('A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.enqueue('a2', payload('A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.enqueue('b1', payload('B'));
      await store.recordAttempt('a1', attempts: 1, nextAttemptAt: now.add(const Duration(minutes: 5)));
      final sent = <String>[];
      stubSubmit((p) async { sent.add(p['sessionId'] as String); return ok; });
      await svc.syncNow();
      expect(sent, ['B']);
      expect((await store.getAll()).map((r) => r.id), ['a1', 'a2']);
    });

    test('no network stops the whole pass and keeps every sale', () async {
      await store.enqueue('a1', payload('A'));
      await store.enqueue('b1', payload('B'));
      var calls = 0;
      stubSubmit((_) async { calls++; return offline; });
      await svc.syncNow();
      expect(calls, 1);
      expect(await store.countPending(), 2);
    });

    test('a DEFINITE server rejection is KEPT as failed with the server\'s reason and code — never dropped, never retried automatically', () async {
      await store.enqueue('k1', payload('A'));
      stubSubmit((_) async => rejected('OFFLINE_SALE_TOO_OLD', 'This sale is older than the 72-hour offline limit'));
      await svc.syncNow();
      final r = (await store.getById('k1'))!;
      expect(r.isFailed, isTrue);
      expect(r.errorCode, 'OFFLINE_SALE_TOO_OLD');
      expect(r.errorMessage, contains('72-hour'));
      expect(svc.failedCount.value, 1);
      expect(svc.unresolvedCount.value, 1, reason: 'a rejected sale still blocks closing the shift');

      var calls = 0;
      stubSubmit((_) async { calls++; return ok; });
      await svc.syncNow();
      expect(calls, 0, reason: 'a rejected sale waits for a person');
      expect(await store.getById('k1'), isNotNull);
    });

    test('a failed sale does not block the other sales of its session', () async {
      await store.enqueue('a1', payload('A'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await store.enqueue('a2', payload('A'));
      var n = 0;
      stubSubmit((_) async => n++ == 0 ? rejected('X', 'no') : ok);
      await svc.syncNow();
      expect((await store.getAll()).map((r) => '${r.id}:${r.status}'), ['a1:failed']);
    });

    test('Retry resets attempts/backoff and tries again immediately', () async {
      await store.enqueue('k1', payload('A'));
      stubSubmit((_) async => rejected('PLAN', 'plan'));
      await svc.syncNow();
      expect((await store.getById('k1'))!.isFailed, isTrue);
      stubSubmit((_) async => ok);
      await svc.retry('k1');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(await store.getAll(), isEmpty);
    });

    test('only the SIGNED-IN store\'s sales are replayed; another store\'s stay untouched', () async {
      await store.enqueue('mine', payload('A'));
      await store.enqueue('theirs', payload('A', store: 's2'));
      final sent = <String>[];
      stubSubmit((p) async { sent.add(p['storeId'] as String); return ok; });
      await svc.syncNow();
      expect(sent, ['s1']);
      expect((await store.getAll()).map((r) => r.id), ['theirs']);
    });

    test('unresolvedForSession / unresolvedForStore drive the close-shift and sign-out blocks', () async {
      await store.enqueue('a1', payload('A'));
      await store.enqueue('b1', payload('B'));
      expect(await svc.unresolvedForSession('A'), 1);
      expect(await svc.unresolvedForSession('C'), 0);
      expect(await svc.unresolvedForStore(), 2);
    });
  });

  group('manager discard', () {
    test('a reason is required', () async {
      await store.enqueue('k1', payload('A'));
      expect(() => svc.discard('k1', reason: '  ', managerEmployeeId: 'm1'), throwsArgumentError);
      expect(() => svc.discard('k1', reason: 'ab', managerEmployeeId: 'm1'), throwsArgumentError);
      expect((await store.getById('k1'))!.isPending, isTrue);
    });

    test('the sale STAYS on the device until the discard is recorded in the server audit log, then it is removed', () async {
      await store.enqueue('k1', payload('A'), employeeToken: 'sale-token');
      // offline when the manager discards: the audit entry can't be written yet
      when(() => repo.recordOfflineDiscard(storeId: any(named: 'storeId'), idempotencyKey: any(named: 'idempotencyKey'), reason: any(named: 'reason'), summary: any(named: 'summary'), employeeToken: any(named: 'employeeToken')))
          .thenAnswer((_) async => (recorded: false, alreadySynced: false, connectivityError: true, message: null));
      await svc.discard('k1', reason: 'customer left, sale void', managerEmployeeId: 'm1', managerToken: 'mgr-token');
      await Future<void>.delayed(const Duration(milliseconds: 100)); // discard() also kicks a background pass — let it finish
      var r = (await store.getById('k1'))!;
      expect(r.isDiscarding, isTrue, reason: 'kept locally while offline');
      expect(r.discardReason, 'customer left, sale void');
      expect(r.employeeToken, 'mgr-token', reason: 'the audit entry is authorised by the discarding manager');
      expect(svc.unresolvedCount.value, 0, reason: 'a manager-resolved item no longer blocks the shift');

      when(() => repo.recordOfflineDiscard(storeId: any(named: 'storeId'), idempotencyKey: any(named: 'idempotencyKey'), reason: any(named: 'reason'), summary: any(named: 'summary'), employeeToken: any(named: 'employeeToken')))
          .thenAnswer((_) async => (recorded: true, alreadySynced: false, connectivityError: false, message: null));
      await svc.syncNow();
      expect(await store.getById('k1'), isNull, reason: 'removed only AFTER the server recorded the discard');
      final call = verify(() => repo.recordOfflineDiscard(storeId: 's1', idempotencyKey: 'k1', reason: 'customer left, sale void', summary: captureAny(named: 'summary'), employeeToken: 'mgr-token'));
      expect((call.captured.last as Map)['discardedBy'], 'm1');
    });

    test('if the sale had actually reached the server, the discard is moot: it goes back to pending instead of being lost', () async {
      await store.enqueue('k1', payload('A'));
      await store.markDiscarding('k1', reason: 'mistake', discardedBy: 'm1', managerToken: 't');
      when(() => repo.recordOfflineDiscard(storeId: any(named: 'storeId'), idempotencyKey: any(named: 'idempotencyKey'), reason: any(named: 'reason'), summary: any(named: 'summary'), employeeToken: any(named: 'employeeToken')))
          .thenAnswer((_) async => (recorded: false, alreadySynced: true, connectivityError: false, message: 'already synced'));
      stubSubmit((_) async => serverDown);
      await svc.syncNow();
      expect((await store.getById('k1'))!.isPending, isTrue);
    });
  });
}
