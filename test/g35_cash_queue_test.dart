// G3.5 offline queue of cash in / out, drawer expenses and receipt photos against a real SQLite (in-memory via sqflite_common_ffi) and a mocked
// repository: stored in order, persisted across a restart, replayed IN ORDER and EXACTLY ONCE (a `duplicate: true` answer is success), a retryable failure
// backs off and never drops or reorders anything, a definite "no" (shift closed meanwhile, over the limit, validation) is parked for Needs attention and
// never retried by itself, photos wait for their expense and are deleted from the device once uploaded.
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/g35_fixtures.dart';

class _MockRepo extends Mock implements PosRepository {}

typedef MoveRes = ({bool success, String? message, String? code, bool retryable, CashMovementResult? result});
typedef ExpRes = ({bool success, String? message, String? code, bool retryable, ExpenseSaved? result});
typedef UpRes = ({bool success, String? message, String? code, bool retryable});

MoveRes moveOk({bool duplicate = false}) => (success: true, message: null, code: null, retryable: false, result: movementResult(duplicate: duplicate));
const MoveRes moveOffline = (success: false, message: 'Could not reach the server.', code: null, retryable: true, result: null);
MoveRes moveRefused(String code) => (success: false, message: 'x', code: code, retryable: false, result: null);
ExpRes expOk({bool duplicate = false}) => (success: true, message: null, code: null, retryable: false, result: expenseSaved(duplicate: duplicate));
ExpRes expRefused(String code) => (success: false, message: 'x', code: code, retryable: false, result: null);
const UpRes upOk = (success: true, message: null, code: null, retryable: false);
const UpRes upOffline = (success: false, message: 'offline', code: null, retryable: true);

AesGcmQueueCipher _cipher() => AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 9)));

void main() {
  late Directory tmp;
  late _MockRepo repo;
  late PendingCashLocalStore store;
  late PendingCashSyncService svc;
  late DateTime now;
  late List<String> deleted;
  var currentStore = 's1';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    Get.testMode = true;
    registerFallbackValue(File('x'));
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pos_cash_queue_');
    repo = _MockRepo();
    now = DateTime(2026, 11, 9, 12);
    currentStore = 's1';
    deleted = [];
    when(() => repo.lastErrorCode).thenReturn(null);
    store = PendingCashLocalStore(dbPath: '${tmp.path}/c.db', cipher: _cipher());
    svc = PendingCashSyncService(
      posRepository: repo,
      localStore: store,
      currentStoreId: () async => currentStore,
      clock: () => now,
      deleteFile: (p) async => deleted.add(p),
      keepFile: (f) async => f.path,
    );
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Future<PendingCashRecord> move(String id, {int amount = 1000, String type = 'cash_in', String session = 'se1', String? token}) => svc.enqueueMovement(
    storeId: 's1',
    requestId: id,
    type: type,
    category: type == 'cash_in' ? 'float_topup' : 'bank_deposit',
    amountMinor: amount,
    sessionId: session,
    currency: 'USD',
    currencyExponent: 2,
    occurredAt: DateTime.utc(2026, 11, 9, 7, 30),
    employeeToken: token,
  );

  Future<PendingCashRecord> exp(String id, {int amount = 4000, String session = 'se1'}) =>
      svc.enqueueExpense(storeId: 's1', requestId: id, category: 'supplies', amountMinor: amount, sessionId: session, currency: 'USD', currencyExponent: 2, payee: 'Shop');

  void stubMove(Future<MoveRes> Function(String id) f) {
    when(
      () => repo.recordCashMovement(
        any(),
        type: any(named: 'type'),
        category: any(named: 'category'),
        amountMinor: any(named: 'amountMinor'),
        sessionId: any(named: 'sessionId'),
        requestId: any(named: 'requestId'),
        note: any(named: 'note'),
        occurredAt: any(named: 'occurredAt'),
        employeeToken: any(named: 'employeeToken'),
        approverToken: any(named: 'approverToken'),
      ),
    ).thenAnswer((i) => f(i.namedArguments[#requestId] as String));
  }

  void stubExpense(Future<ExpRes> Function(String id) f) {
    when(
      () => repo.recordExpense(
        any(),
        category: any(named: 'category'),
        method: any(named: 'method'),
        amountMinor: any(named: 'amountMinor'),
        requestId: any(named: 'requestId'),
        sessionId: any(named: 'sessionId'),
        payee: any(named: 'payee'),
        note: any(named: 'note'),
        occurredAt: any(named: 'occurredAt'),
        employeeToken: any(named: 'employeeToken'),
        approverToken: any(named: 'approverToken'),
      ),
    ).thenAnswer((i) => f(i.namedArguments[#requestId] as String));
  }

  void stubUpload(Future<UpRes> Function(String expenseId) f) {
    when(() => repo.uploadExpenseReceipt(any(), any(), any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((i) => f(i.positionalArguments[1] as String));
  }

  group('storage', () {
    test('rows keep their order, survive a restart, and are encrypted at rest (no readable amount or note in the file)', () async {
      await move('r1', amount: 12345);
      await exp('r2');
      await store.close();
      final bytes = await File('${tmp.path}/c.db').readAsBytes();
      expect(String.fromCharCodes(bytes).contains('12345'), isFalse);
      expect(String.fromCharCodes(bytes).contains('Shop'), isFalse);
      final reopened = PendingCashLocalStore(dbPath: '${tmp.path}/c.db', cipher: _cipher());
      final all = await reopened.getAll();
      expect(all.map((r) => r.id), ['r1', 'r2']);
      expect(all.first.amountMinor, 12345);
      expect(all.first.payload['occurredAt'], '2026-11-09T07:30:00.000Z');
      expect(all.first.title, 'Cash in · Float topup');
      await reopened.close();
    });

    test('the same request id queued twice is one row and keeps its place and state', () async {
      await move('r1');
      await store.markFailed('r1', 'no', errorCode: 'NO_OPEN_SHIFT');
      await move('r1');
      final all = await store.getAll();
      expect(all, hasLength(1));
      expect(all.single.status, 'failed');
    });

    test('a row that cannot be decrypted is kept, shown as failed and never replayed', () async {
      await move('r1');
      await store.close();
      final other = PendingCashLocalStore(
        dbPath: '${tmp.path}/c.db',
        cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 1))),
      );
      final r = (await other.getAll()).single;
      expect(r.unreadable, isTrue);
      expect(r.isFailed, isTrue);
      await other.close();
    });
  });

  group('replay', () {
    test('sends in order, one at a time, with the ORIGINAL request id and device time, and the employee token of whoever made it', () async {
      await move('r1', token: 'tok-sam');
      await exp('r2');
      await move('r3', type: 'cash_out', amount: 500);
      final seen = <String>[];
      var inFlight = 0, maxInFlight = 0;
      stubMove((id) async {
        inFlight++;
        maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
        seen.add(id);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return moveOk();
      });
      stubExpense((id) async {
        inFlight++;
        maxInFlight = maxInFlight < inFlight ? inFlight : maxInFlight;
        seen.add(id);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return expOk();
      });
      await svc.syncNow();
      expect(seen, ['r1', 'r2', 'r3']);
      expect(maxInFlight, 1);
      expect(svc.unresolvedCount.value, 0);
      final c = verify(
        () => repo.recordCashMovement(
          's1',
          type: 'cash_in',
          category: 'float_topup',
          amountMinor: 1000,
          sessionId: 'se1',
          requestId: 'r1',
          note: null,
          occurredAt: DateTime.utc(2026, 11, 9, 7, 30),
          employeeToken: 'tok-sam',
          approverToken: null,
        ),
      )..called(1);
      expect(c, isNotNull);
    });

    test('exactly once: syncing again after success sends nothing; a duplicate:true answer is success and clears the row', () async {
      await move('r1');
      var calls = 0;
      stubMove((_) async {
        calls++;
        return moveOk(duplicate: true);
      });
      await svc.syncNow();
      await svc.syncNow();
      expect(calls, 1);
      expect(await store.getAll(), isEmpty);
    });

    test('two overlapping syncs make one pass (a mutex), so a row cannot be sent twice at once', () async {
      await move('r1');
      var calls = 0;
      stubMove((_) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return moveOk();
      });
      await Future.wait([svc.syncNow(), svc.syncNow()]);
      expect(calls, 1);
    });

    test('a replay after a crash (the row is still there, the server already booked it) ends clean via duplicate:true', () async {
      await move('r1');
      stubMove((_) async => moveOk(duplicate: true));
      final restarted = PendingCashSyncService(
        posRepository: repo,
        localStore: PendingCashLocalStore(dbPath: '${tmp.path}/c.db', cipher: _cipher()),
        currentStoreId: () async => 's1',
        clock: () => now,
      );
      await restarted.syncNow();
      expect(restarted.unresolvedCount.value, 0);
    });

    test('a retryable failure (offline / timeout / 5xx) stops the pass, keeps order, backs off 5s, 10s, … and never drops anything', () async {
      await move('r1');
      await move('r2');
      stubMove((id) async => moveOffline);
      await svc.syncNow();
      var all = await store.getAll();
      expect(all.map((r) => r.status), ['pending', 'pending']);
      expect(all.first.attempts, 1);
      expect(all.first.nextAttemptAt, now.add(const Duration(seconds: 5)));
      expect(all.last.attempts, 0, reason: 'the second one was not even tried: order is kept');
      verify(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: 'r1',
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).called(1);
      // before the backoff ends nothing is sent
      await svc.syncNow();
      expect((await store.getAll()).first.attempts, 1);
      // after it, the first one goes (and works), then the second
      now = now.add(const Duration(seconds: 6));
      stubMove((_) async => moveOk());
      await svc.syncNow();
      expect(await store.getAll(), isEmpty);
    });

    test('a definite refusal parks the row (failed, with a plain message) and is NEVER retried by itself; it does not block the rows after it', () async {
      await move('r1');
      await move('r2');
      stubMove((id) async => id == 'r1' ? moveRefused('NO_OPEN_SHIFT') : moveOk());
      await svc.syncNow();
      var all = await store.getAll();
      expect(all.map((r) => '${r.id}:${r.status}'), ['r1:failed']);
      expect(all.single.errorCode, 'NO_OPEN_SHIFT');
      expect(all.single.errorMessage, 'There is no open shift on this till. Open a shift first.');
      expect(svc.failedCount.value, 1);
      var calls = 0;
      stubMove((_) async {
        calls++;
        return moveOk();
      });
      await svc.syncNow(ignoreBackoff: true);
      await svc.syncNow(ignoreBackoff: true);
      expect(calls, 0, reason: 'a refused entry waits for a person');
    });

    test('over the limit with nobody to approve (POS_APPROVAL_REQUIRED / POS_OWNER_REQUIRED) is a conflict, not a retry loop', () async {
      await move('r1', amount: 999999);
      await move('r2', amount: 888888);
      stubMove((id) async => moveRefused(id == 'r1' ? 'POS_APPROVAL_REQUIRED' : 'POS_OWNER_REQUIRED'));
      await svc.syncNow();
      final all = await store.getAll();
      expect(all.map((r) => r.errorCode), ['POS_APPROVAL_REQUIRED', 'POS_OWNER_REQUIRED']);
      expect(all.every((r) => r.isFailed), isTrue);
    });

    test('Retry puts a parked row back (sent as whoever is signed in: the stored token is dropped) and then it goes through', () async {
      await move('r1', token: 'old-token');
      stubMove((_) async => moveRefused('POS_PIN_REQUIRED'));
      await svc.syncNow();
      expect((await store.getById('r1'))!.isFailed, isTrue);
      String? tokenUsed = 'unset';
      stubMove((_) async => moveOk());
      when(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((i) async {
        tokenUsed = i.namedArguments[#employeeToken] as String?;
        return moveOk();
      });
      await svc.retry('r1');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(tokenUsed, isNull);
      expect(await store.getAll(), isEmpty);
    });

    test('only the signed-in store is synced; another store\'s rows stay put', () async {
      await svc.enqueueMovement(storeId: 's2', requestId: 'other', type: 'cash_in', category: 'float_topup', amountMinor: 1, sessionId: 'x', currency: 'USD', currencyExponent: 2);
      await move('mine');
      final ids = <String>[];
      stubMove((id) async {
        ids.add(id);
        return moveOk();
      });
      await svc.syncNow();
      expect(ids, ['mine']);
      expect((await store.getAll()).map((r) => r.id), ['other']);
    });

    test('nothing is sent without credentials (the queue waits, nothing is dropped)', () async {
      await move('r1');
      final locked = PendingCashSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's1', hasCredentials: () => false);
      await locked.syncNow();
      verifyNever(
        () => repo.recordCashMovement(
          any(),
          type: any(named: 'type'),
          category: any(named: 'category'),
          amountMinor: any(named: 'amountMinor'),
          sessionId: any(named: 'sessionId'),
          requestId: any(named: 'requestId'),
          note: any(named: 'note'),
          occurredAt: any(named: 'occurredAt'),
          employeeToken: any(named: 'employeeToken'),
          approverToken: any(named: 'approverToken'),
        ),
      );
      expect(await store.getAll(), hasLength(1));
    });
  });

  group('receipt photos', () {
    late File photo;
    setUp(() async {
      photo = File('${tmp.path}/p.jpg')..writeAsBytesSync([1, 2, 3]);
    });

    test('the photo waits for its expense, uploads to the id the server gave it, then the local copy is deleted', () async {
      await exp('e1');
      await svc.enqueueReceipt(storeId: 's1', path: photo.path, expenseRequestId: 'e1');
      final order = <String>[];
      stubExpense((id) async {
        order.add('expense');
        return expOk();
      });
      stubUpload((expenseId) async {
        order.add('photo:$expenseId');
        return upOk;
      });
      await svc.syncNow();
      expect(order, ['expense', 'photo:x1']);
      expect(deleted, [photo.path]);
      expect(await store.getAll(), isEmpty);
    });

    test('a photo whose upload cannot reach the server stays queued with its file; it is deleted only once uploaded', () async {
      await svc.enqueueReceipt(storeId: 's1', path: photo.path, expenseId: 'x9');
      stubUpload((_) async => upOffline);
      await svc.syncNow();
      expect(deleted, isEmpty);
      expect(await store.getAll(), hasLength(1));
      now = now.add(const Duration(minutes: 1));
      stubUpload((_) async => upOk);
      await svc.syncNow();
      expect(deleted, [photo.path]);
      expect(await store.getAll(), isEmpty);
    });

    test('if the expense is refused the photo waits (it is not uploaded to nothing); dismissing the expense deletes the photo and its file', () async {
      await exp('e1');
      await svc.enqueueReceipt(storeId: 's1', path: photo.path, expenseRequestId: 'e1');
      stubExpense((_) async => expRefused('NO_OPEN_SHIFT'));
      var uploads = 0;
      stubUpload((_) async {
        uploads++;
        return upOk;
      });
      await svc.syncNow();
      expect(uploads, 0);
      expect((await store.getAll()).map((r) => '${r.kind}:${r.status}'), ['expense:failed', 'receipt:pending']);
      await svc.dismiss('e1');
      expect(await store.getAll(), isEmpty);
      expect(deleted, [photo.path]);
    });

    test('a duplicate expense answer still lets its photo upload (the expense is on the server)', () async {
      await exp('e1');
      await svc.enqueueReceipt(storeId: 's1', path: photo.path, expenseRequestId: 'e1');
      stubExpense((_) async => expOk(duplicate: true));
      stubUpload((_) async => upOk);
      await svc.syncNow();
      expect(await store.getAll(), isEmpty);
    });

    test('a missing local file is parked, not retried forever', () async {
      await svc.enqueueReceipt(storeId: 's1', path: '${tmp.path}/gone.jpg', expenseId: 'x9');
      await svc.syncNow();
      final r = (await store.getAll()).single;
      expect(r.isFailed, isTrue);
      verifyNever(() => repo.uploadExpenseReceipt(any(), any(), any(), employeeToken: any(named: 'employeeToken')));
    });

    test('a refused photo (type / size) is parked with the server\'s plain message and the file is kept until dismissed', () async {
      await svc.enqueueReceipt(storeId: 's1', path: photo.path, expenseId: 'x9');
      stubUpload((_) async => (success: false, message: 'x', code: 'FILE_TOO_LARGE', retryable: false));
      await svc.syncNow();
      expect((await store.getAll()).single.errorMessage, 'That file is too large. Take a smaller photo.');
      expect(deleted, isEmpty);
      await svc.dismiss((await store.getAll()).single.id);
      expect(deleted, [photo.path]);
    });
  });

  group('counts', () {
    test('per-shift unresolved counts ignore photos, and waitingForSession lists the pending movements of that shift', () async {
      await move('r1');
      await move('r2', session: 'other');
      await svc.enqueueReceipt(storeId: 's1', path: '/x.jpg', expenseId: 'x1');
      expect(await svc.unresolvedForSession('se1'), 1);
      expect(svc.waitingForSession('se1').map((r) => r.id), ['r1']);
      expect(svc.pendingCount.value, 3);
    });
  });
}
