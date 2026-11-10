// G3.6 offline queue of clock events against a real SQLite (in-memory via sqflite_common_ffi) and a mocked repository: stored in order and encrypted, replayed
// IN ORDER and EXACTLY ONCE (duplicate:true is success), a retryable failure backs off without dropping or reordering anything, a definite refusal is parked
// for Needs attention and never retried by itself, a person is never blocked offline.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_team_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_team_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/g36_fixtures.dart';

class _MockRepo extends Mock implements PosRepository {}

typedef ClockRes = ({bool success, String? message, String? code, bool retryable, ClockResult? result});
ClockRes ok({bool duplicate = false}) => (success: true, message: null, code: null, retryable: false, result: clockResult(duplicate: duplicate));
const ClockRes offline = (success: false, message: 'Could not reach the server.', code: null, retryable: true, result: null);
ClockRes refused(String code) => (success: false, message: 'x', code: code, retryable: false, result: null);

AesGcmQueueCipher _cipher() => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 4)));

void main() {
  late Directory tmp;
  late _MockRepo repo;
  late PendingTeamLocalStore store;
  late PendingTeamSyncService svc;
  late DateTime now;
  var currentStore = 's1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Get.testMode = true;
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pos_team_queue_');
    repo = _MockRepo();
    now = DateTime(2026, 11, 9, 12);
    currentStore = 's1';
    when(() => repo.lastErrorCode).thenReturn(null);
    store = PendingTeamLocalStore(dbPath: '${tmp.path}/t.db', cipher: _cipher());
    svc = PendingTeamSyncService(posRepository: repo, localStore: store, currentStoreId: () async => currentStore, clock: () => now);
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Future<PendingClockRecord> ev(String id, String action, {DateTime? at, String employee = 'e1', String? token, String storeId = 's1'}) =>
      svc.enqueue(storeId: storeId, requestId: id, action: action, deviceAt: at ?? DateTime.utc(2026, 11, 9, 4, 2), employeeId: employee, employeeToken: token);

  void stub(Future<ClockRes> Function(Map<Symbol, dynamic> a) f) {
    when(
      () => repo.teamClock(
        any(),
        action: any(named: 'action'),
        requestId: any(named: 'requestId'),
        deviceAt: any(named: 'deviceAt'),
        note: any(named: 'note'),
        employeeToken: any(named: 'employeeToken'),
      ),
    ).thenAnswer((i) => f(i.namedArguments));
  }

  group('storage', () {
    test('rows keep their order, survive a restart, and are encrypted at rest', () async {
      await ev('r1', 'clock_in', at: DateTime.utc(2026, 11, 9, 4, 2));
      await ev('r2', 'break_start', at: DateTime.utc(2026, 11, 9, 8));
      await store.close();
      final bytes = String.fromCharCodes(await File('${tmp.path}/t.db').readAsBytes());
      expect(bytes.contains('clock_in'), isFalse);
      final reopened = PendingTeamLocalStore(dbPath: '${tmp.path}/t.db', cipher: _cipher());
      final all = await reopened.getAll();
      expect(all.map((r) => r.id), ['r1', 'r2']);
      expect(all.first.action, 'clock_in');
      expect(all.first.deviceAt.toUtc(), DateTime.utc(2026, 11, 9, 4, 2));
      await reopened.close();
    });

    test('the same request id queued twice is one row and keeps its place and state', () async {
      await ev('r1', 'clock_in');
      await store.markFailed('r1', 'no', errorCode: 'EMPLOYEE_REQUIRED');
      await ev('r1', 'clock_in');
      final all = await store.getAll();
      expect(all, hasLength(1));
      expect(all.single.status, 'failed');
    });

    test('a row that cannot be decrypted is kept, shown as failed and never replayed', () async {
      await ev('r1', 'clock_in');
      await store.close();
      final other = PendingTeamLocalStore(
        dbPath: '${tmp.path}/t.db',
        cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 1))),
      );
      final r = (await other.getAll()).single;
      expect((r.unreadable, r.isFailed), (true, true));
      await other.close();
    });
  });

  group('replay', () {
    test('sends in order, one at a time, with the ORIGINAL request id and the time the person tapped, as the person who made it', () async {
      await ev('r1', 'clock_in', at: DateTime.utc(2026, 11, 9, 4), token: 'tok-sam');
      await ev('r2', 'break_start', at: DateTime.utc(2026, 11, 9, 8));
      await ev('r3', 'break_end', at: DateTime.utc(2026, 11, 9, 8, 30));
      final seen = <(String, String, DateTime, String?)>[];
      var inFlight = 0, maxInFlight = 0;
      stub((a) async {
        inFlight++;
        maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
        seen.add((a[#requestId] as String, a[#action] as String, a[#deviceAt] as DateTime, a[#employeeToken] as String?));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return ok();
      });
      await svc.syncNow();
      expect(seen.map((e) => e.$1), ['r1', 'r2', 'r3']);
      expect(seen.map((e) => e.$2), ['clock_in', 'break_start', 'break_end']);
      expect(seen.first.$3.toUtc(), DateTime.utc(2026, 11, 9, 4));
      expect(seen.first.$4, 'tok-sam');
      expect(maxInFlight, 1);
      expect(svc.pendingCount.value, 0);
      expect(svc.syncedTick.value, 1);
    });

    test('exactly once: syncing again sends nothing; a duplicate:true answer is success and clears the row', () async {
      await ev('r1', 'clock_in');
      var calls = 0;
      stub((_) async {
        calls++;
        return ok(duplicate: true);
      });
      await svc.syncNow();
      await svc.syncNow();
      expect(calls, 1);
      expect(await store.getAll(), isEmpty);
    });

    test('two overlapping syncs make one pass (a mutex)', () async {
      await ev('r1', 'clock_in');
      var calls = 0;
      stub((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return ok();
      });
      await Future.wait([svc.syncNow(), svc.syncNow()]);
      expect(calls, 1);
    });

    test('a replay after a crash (the row is still there, the server already counted it) ends clean via duplicate:true', () async {
      await ev('r1', 'clock_in');
      stub((_) async => ok(duplicate: true));
      final restarted = PendingTeamSyncService(
        posRepository: repo,
        localStore: PendingTeamLocalStore(dbPath: '${tmp.path}/t.db', cipher: _cipher()),
        currentStoreId: () async => 's1',
        clock: () => now,
      );
      await restarted.syncNow();
      expect(restarted.pendingCount.value, 0);
    });

    test('a retryable failure stops the pass, keeps the order, backs off 5s then goes through; nothing is dropped', () async {
      await ev('r1', 'clock_in');
      await ev('r2', 'clock_out');
      stub((_) async => offline);
      await svc.syncNow();
      var all = await store.getAll();
      expect(all.map((r) => r.status), ['pending', 'pending']);
      expect(all.first.attempts, 1);
      expect(all.first.nextAttemptAt, now.add(const Duration(seconds: 5)));
      expect(all.last.attempts, 0, reason: 'the second one was not even tried: order is kept');
      await svc.syncNow();
      expect((await store.getAll()).first.attempts, 1, reason: 'still inside the backoff');
      now = now.add(const Duration(seconds: 6));
      stub((_) async => ok());
      await svc.syncNow();
      expect(await store.getAll(), isEmpty);
    });

    test('a definite refusal (EMPLOYEE_REQUIRED) is parked with a plain message, never retried by itself, and does not block the rows after it', () async {
      await ev('r1', 'clock_in');
      await ev('r2', 'clock_out');
      stub((a) async => a[#requestId] == 'r1' ? refused('EMPLOYEE_REQUIRED') : ok());
      await svc.syncNow();
      final all = await store.getAll();
      expect(all.map((r) => '${r.id}:${r.status}'), ['r1:failed']);
      expect(all.single.errorMessage, contains('Sign in with your PIN'));
      var calls = 0;
      stub((_) async {
        calls++;
        return ok();
      });
      await svc.syncNow(ignoreBackoff: true);
      expect(calls, 0);
      expect(svc.failedCount.value, 1);
    });

    test('Retry puts a parked row back, sent as whoever is signed in (the stored token is dropped)', () async {
      await ev('r1', 'clock_in', token: 'old');
      stub((_) async => refused('POS_PIN_REQUIRED'));
      await svc.syncNow();
      String? used = 'unset';
      stub((a) async {
        used = a[#employeeToken] as String?;
        return ok();
      });
      await svc.retry('r1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(used, isNull);
      expect(await store.getAll(), isEmpty);
    });

    test('Dismiss removes a parked row', () async {
      await ev('r1', 'clock_in');
      stub((_) async => refused('EMPLOYEE_REQUIRED'));
      await svc.syncNow();
      await svc.dismiss('r1');
      expect(await store.getAll(), isEmpty);
    });

    test('only the signed-in store is synced; nothing is sent without credentials', () async {
      await ev('other', 'clock_in', storeId: 's2');
      await ev('mine', 'clock_in');
      final ids = <String>[];
      stub((a) async {
        ids.add(a[#requestId] as String);
        return ok();
      });
      await svc.syncNow();
      expect(ids, ['mine']);
      final locked = PendingTeamSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's2', hasCredentials: () => false);
      await locked.syncNow();
      expect((await store.getAll()).map((r) => r.id), ['other']);
    });
  });

  test('pendingFor lists only this person\'s waiting events, oldest first (what the local clock state is derived from)', () async {
    await ev('a', 'clock_in', employee: 'e1');
    await ev('b', 'clock_in', employee: 'e2');
    await ev('c', 'break_start', employee: 'e1');
    await store.markFailed('c', 'x');
    await svc.refreshCounts();
    expect(svc.pendingFor('e1').map((r) => r.id), ['a']);
    expect(svc.pendingFor('e2').map((r) => r.id), ['b']);
  });
}
