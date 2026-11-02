// Runs ON a simulator/device with the REAL native SQLite (not the ffi test double) and real SharedPreferences.
// "Airplane mode" is simulated at the repository seam (the server is unreachable until the flag flips) — the OS
// network toggle itself can't be scripted from a test. What this proves on a real platform: sales queued offline
// survive a restart of the queue objects, back off instead of hammering, stay FIFO per session, sync when the
// connection returns with their original key / time / settingsVersion, and a rejected sale is kept, not dropped.

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';

class MockPosRepository extends Mock implements PosRepository {}

typedef RawResult = ({bool success, bool connectivityError, bool retryable, String? message, String? code});

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late PendingSaleLocalStore store;
  late MockPosRepository repo;
  var online = false;
  final sent = <Map<String, dynamic>>[];
  var now = DateTime.now();

  Map<String, dynamic> payload(String session, int n) => {
        'storeId': 's1', 'sessionId': session, 'items': [{'variantId': 'v', 'qty': n}], 'clientTotal': 10.0 * n,
        'clientCreatedAt': DateTime.now().toUtc().toIso8601String(), 'settingsVersion': 4, 'offline': true,
      };

  PendingSaleSyncService service() => PendingSaleSyncService(posRepository: repo, localStore: store, currentStoreId: () async => 's1', clock: () => now, persistLastSync: false);

  setUp(() async {
    store = PendingSaleLocalStore();
    for (final r in await store.getAll()) {
      await store.remove(r.id);
    }
    repo = MockPosRepository();
    online = false;
    sent.clear();
    now = DateTime.now();
    when(() => repo.submitRawSale(any(), employeeToken: any(named: 'employeeToken'))).thenAnswer((inv) async {
      final p = inv.positionalArguments.first as Map<String, dynamic>;
      if (!online) return (success: false, connectivityError: true, retryable: true, message: null, code: null) as RawResult;
      if (p['items'][0]['qty'] == 99) return (success: false, connectivityError: false, retryable: false, message: 'sale is older than the offline limit', code: 'OFFLINE_SALE_TOO_OLD') as RawResult;
      sent.add(p);
      return (success: true, connectivityError: false, retryable: false, message: null, code: null) as RawResult;
    });
  });

  tearDown(() async {
    for (final r in await store.getAll()) {
      await store.remove(r.id);
    }
    await store.close();
  });

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  testWidgets('offline → queued, survives a restart, backs off, then syncs FIFO with the original data when the connection returns', (tester) async {
    var svc = service();
    await svc.enqueue('k1', payload('A', 1));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await svc.enqueue('k2', payload('A', 2));
    await svc.enqueue('k3', payload('B', 3));
    expect(svc.unresolvedCount.value, 3);

    // offline: nothing leaves, attempts are counted, backoff is scheduled
    await svc.syncNow();
    expect(sent, isEmpty);
    expect((await store.getById('k1'))!.attempts, 1);
    expect((await store.getById('k1'))!.nextAttemptAt, isNotNull);

    // the app is killed and relaunched: brand-new store + service objects over the same on-device database
    await store.close();
    store = PendingSaleLocalStore();
    svc = service();
    await svc.refreshCounts();
    expect(svc.unresolvedCount.value, 3, reason: 'queued sales survive a restart');

    // connection returns
    online = true;
    await svc.syncNow(ignoreBackoff: true);
    expect(await store.getAll(), isEmpty);
    expect(sent.length, 3);
    final sessionA = sent.where((p) => p['sessionId'] == 'A').toList();
    expect(sessionA.map((p) => (p['items'][0]['qty'])).toList(), [1, 2], reason: 'FIFO within a session');
    expect(sent.every((p) => p['settingsVersion'] == 4 && p['offline'] == true && p['clientCreatedAt'] != null), isTrue);
    expect(svc.lastSuccessfulSync.value, isNotNull);
  });

  testWidgets('a sale the server rejects is KEPT (needs attention), never dropped, and does not block the others', (tester) async {
    online = true;
    final svc = service();
    await svc.enqueue('bad', payload('A', 99));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await svc.enqueue('good', payload('A', 1));
    await svc.syncNow();
    expect((await store.getAll()).map((r) => '${r.id}:${r.status}'), ['bad:failed']);
    expect((await store.getById('bad'))!.errorCode, 'OFFLINE_SALE_TOO_OLD');
    expect(svc.failedCount.value, 1);
    expect(sent.length, 1);
  });
}
