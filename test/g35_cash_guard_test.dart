// Closing a shift / signing out is blocked while cash entries made offline have not reached the server (they change the drawer's count);
// receipt photos are not money and never block.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_cash_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_cash_sync_service.dart';
import 'package:solvexo_pos/utils/unsynced_guard.dart';

class _Repo extends Mock implements PosRepository {}

class _Queue extends PendingCashSyncService {
  _Queue(this.rows)
    : super(
        posRepository: _Repo(),
        localStore: PendingCashLocalStore(dbPath: 'unused.db'),
      );
  final List<PendingCashRecord> rows;
  int syncs = 0;
  @override
  Future<List<PendingCashRecord>> records() async => rows;
  @override
  Future<void> syncNow({bool ignoreBackoff = false}) async => syncs++;
}

PendingCashRecord row(String id, {String status = 'pending', String kind = 'movement', String session = 'se1'}) =>
    PendingCashRecord(seq: 1, id: id, kind: kind, payload: const {'amountMinor': 100}, status: status, createdAt: DateTime(2026, 11, 9), sessionId: session);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    Get.reset();
  });

  test('a pending or refused cash entry of THIS shift blocks closing it; another shift\'s does not; a photo never does', () async {
    final q = _Queue([row('a'), row('b', status: 'failed'), row('c', session: 'other'), row('d', kind: 'receipt', session: '')]);
    q.unresolvedCount.value = 3;
    final s = await UnsyncedGuard.check(sessionId: 'se1', cashService: q);
    expect((s.cashPending, s.cashFailed), (1, 1));
    expect(s.cash, 2);
    expect(s.blocks, isTrue);
    expect(s.total, 0, reason: 'no sales in this test');
    expect(q.syncs, 1, reason: 'one immediate sync is tried first (the queue may only be waiting on a backoff timer)');
  });

  test('signing out (no session) counts every shift\'s entries', () async {
    final q = _Queue([row('a'), row('c', session: 'other')]);
    q.unresolvedCount.value = 2;
    expect((await UnsyncedGuard.check(cashService: q)).cash, 2);
  });

  test('nothing queued: it does not block', () async {
    final q = _Queue([]);
    final s = await UnsyncedGuard.check(sessionId: 'se1', cashService: q);
    expect(s.blocks, isFalse);
  });

  test('sales-only behaviour is unchanged (the old constructor still works)', () {
    const s = UnsyncedStatus(pending: 1, failed: 2);
    expect((s.total, s.cash, s.blocks), (3, 0, true));
  });

  testWidgets('the blocking dialog names the cash entries', (t) async {
    final q = _Queue([row('a'), row('b', status: 'failed')]);
    q.unresolvedCount.value = 2;
    await t.pumpWidget(const GetMaterialApp(home: Scaffold(body: SizedBox())));
    final f = UnsyncedGuard.blockIfUnsynced(action: 'close the shift', sessionId: 'se1', cashService: q);
    await t.pumpAndSettle();
    expect(find.text("Can't close the shift yet"), findsOneWidget);
    expect(find.textContaining('2 cash entries on this device haven\'t reached the server'), findsOneWidget);
    expect(find.textContaining('1 cash waiting to sync'), findsOneWidget);
    expect(find.textContaining('1 cash refused by the server'), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(await f, isTrue);
  });
}
