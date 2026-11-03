// Account deletion must be refused while sales rung up on this device have not reached the server — the offline queue is the only
// copy of that money, and deletion revokes every session so it could never sync afterwards. (The guard itself is unit-tested in
// offline_support_test; this pins that the DELETE screen actually uses it — the other delete-account tests bypass it.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/account_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_device/views/delete_account_view.dart';

class MockAccountRepo extends Mock implements AccountRepository {}

class UnsyncedSync extends PendingSaleSyncService {
  UnsyncedSync(this.rows) {
    unresolvedCount.value = rows.length;
  }
  final List<PendingSaleRecord> rows;
  @override
  Future<void> syncNow({bool ignoreBackoff = false}) async {} // still offline: nothing resolves
  @override
  Future<List<PendingSaleRecord>> records() async => rows;
  @override
  Future<int> unresolvedForStore() async => rows.length;
  @override
  Future<int> unresolvedForSession(String sessionId) async => rows.where((r) => r.sessionId == sessionId).length;
}

void main() {
  late MockAccountRepo repo;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );
  });
  setUp(() {
    Get.reset();
    OwnerSession.end();
    SharedPreferences.setMockInitialValues({'pos_sound_effects': false});
    repo = MockAccountRepo();
    when(() => repo.authMethods()).thenAnswer((_) async => const DeletionAuthMethods());
    when(() => repo.requestDeletion(password: any(named: 'password')))
        .thenAnswer((_) async => (outcome: DeletionOutcome.requested, scheduledFor: DateTime(2030), message: null));
  });

  Future<void> tryDelete(WidgetTester tester) async {
    await tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(home: DeleteAccountView(repository: repo))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('deletePassword')), 'pw');
    await tester.ensureVisible(find.byKey(const Key('deleteConfirm')));
    await tester.tap(find.byKey(const Key('deleteConfirm')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('deleteSubmit')));
    await tester.tap(find.byKey(const Key('deleteSubmit')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  testWidgets('with an unsynced sale on the device: the guard dialog shows and NO deletion request is sent', (tester) async {
    Get.put<PendingSaleSyncService>(UnsyncedSync([
      PendingSaleRecord(id: 'k1', payload: const {}, status: 'pending', createdAt: DateTime(2026), storeId: 's1', sessionId: 'A'),
    ]));
    await tryDelete(tester);
    expect(find.textContaining("Can't delete the account yet"), findsOneWidget);
    verifyNever(() => repo.requestDeletion(password: any(named: 'password')));
  });

  testWidgets('a REJECTED (failed) queued sale blocks too — it is still unrecovered money', (tester) async {
    Get.put<PendingSaleSyncService>(UnsyncedSync([
      PendingSaleRecord(id: 'k2', payload: const {}, status: 'failed', errorMessage: 'rejected', createdAt: DateTime(2026), storeId: 's1', sessionId: 'A'),
    ]));
    await tryDelete(tester);
    expect(find.textContaining("Can't delete the account yet"), findsOneWidget);
    verifyNever(() => repo.requestDeletion(password: any(named: 'password')));
  });

  testWidgets('with an empty queue the request goes through', (tester) async {
    Get.put<PendingSaleSyncService>(UnsyncedSync([]));
    await tryDelete(tester);
    expect(find.textContaining("Can't delete the account yet"), findsNothing);
    verify(() => repo.requestDeletion(password: 'pw')).called(1);
  });
}
