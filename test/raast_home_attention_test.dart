// Home: the read-only business-verification card and the "digital payments need attention" row (managers / owners only).
// Needs attention: the Raast items and the manager actions (attach to a sale / refund / resolve with a note) — each behind a
// manager PIN session, each with a confirmation or a required note.
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/views/pos_needs_attention_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/fake_payments.dart';
import 'support/sale_harness.dart';

class MockInventoryRepository extends Mock implements InventoryRepository {}

class MockSync extends Mock implements PendingSaleSyncService {}

final String rs1500 = Money.format(15.00 * 100, currency: 'PKR', exponent: 2); // what the till prints for 150000 minor units of PKR (exponent 2)

PosAttentionItem item(PosAttentionReason r, {String id = 'pi-1', int minor = 150000}) =>
    PosAttentionItem(intentId: id, reason: r, amountMinor: minor, currency: 'PKR', currencyExponent: 2, confirmedAt: DateTime.utc(2026, 11, 5, 12));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  late FakePaymentsRepo pay;
  late MockPosRepository pos;
  late MockInventoryRepository inv;

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'store-1', 'pos_session_id': 'session-1', 'pos_employee_name': 'Mia', 'pos_employee_role': 'manager'});
    pay = FakePaymentsRepo();
    pos = MockPosRepository();
    inv = MockInventoryRepository();
    when(() => pos.getSessionReport(any())).thenAnswer((_) async => null);
    when(() => pos.getDailyReport(any())).thenAnswer((_) async => null);
    when(() => pos.getRangeReport(any(), from: any(named: 'from'), to: any(named: 'to'))).thenAnswer((_) async => null);
    when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => null);
  });
  tearDown(Get.reset);

  Future<void> mountHome(WidgetTester t, PosAccess access) async {
    t.view.physicalSize = const Size(390, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final c = PosHomeTabController(posRepository: pos, inventoryRepository: inv, paymentsRepository: pay, accessOverride: access);
    Get.put<PosHomeTabController>(c);
    await t.pumpWidget(MaterialApp(theme: AppTheme.light, home: PosHomeTabView(controller: c)));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  group('Home — business verification card (read-only)', () {
    const cases = <(PosKybState, bool, String?, String)>[
      (PosKybState.verified, true, null, 'Raast QR payments are on'),
      (PosKybState.verified, false, null, 'will switch on once the payment provider'),
      (PosKybState.submitted, false, null, 'Solvexo is reviewing'),
      (PosKybState.rejected, false, 'The CNIC photo is unreadable', 'The CNIC photo is unreadable'),
      (PosKybState.draft, false, null, 'not submitted yet'),
      (PosKybState.notStarted, false, null, 'has not been started'),
    ];
    for (final (state, enabled, reason, text) in cases) {
      testWidgets('manager sees "${state.label}"${enabled ? ' (payments on)' : ''}', (t) async {
        pay.kyb = PosKybStatus(state: state, digitalPaymentsEnabled: enabled, rejectionReason: reason);
        await mountHome(t, PosAccess.manager);
        expect(find.byKey(const Key('kybCard')), findsOneWidget);
        expect(find.textContaining(text), findsOneWidget);
        expect(find.text(state.label), findsOneWidget);
        // read-only: nothing on the card can be tapped to change anything
        expect(find.descendant(of: find.byKey(const Key('kybCard')), matching: find.byType(InkWell)), findsNothing);
      });
    }

    testWidgets('a CASHIER never sees the card or the digital row (the server would refuse them anyway)', (t) async {
      pay.kyb = const PosKybStatus(state: PosKybState.submitted, digitalPaymentsEnabled: false);
      pay.attentionItems.add(item(PosAttentionReason.paidAfterExpiry));
      await mountHome(t, PosAccess.cashier);
      expect(find.byKey(const Key('kybCard')), findsNothing);
      expect(find.byKey(const Key('digital')), findsNothing);
    });

    testWidgets('the digital row counts the items that need a manager', (t) async {
      pay.kyb = const PosKybStatus(state: PosKybState.verified, digitalPaymentsEnabled: true);
      pay.attentionItems..add(item(PosAttentionReason.paidAfterExpiry))..add(item(PosAttentionReason.anomaly, id: 'pi-2'));
      await mountHome(t, PosAccess.manager);
      expect(find.text('2 digital payments need attention'), findsOneWidget);
    });
  });

  group('Needs attention — digital payments', () {
    late MockSync sync;
    late PosNeedsAttentionController c;

    Future<void> mountAttention(WidgetTester t, {bool manager = true}) async {
      SharedPreferences.setMockInitialValues({'store_id': 'store-1', 'pos_employee_role': manager ? 'manager' : 'cashier'});
      sync = MockSync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => pos.getSalesNeedingReview(any())).thenAnswer((_) async => []);
      t.view.physicalSize = const Size(600, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      c = PosNeedsAttentionController(syncService: sync, posRepository: pos, paymentsRepository: pay);
      Get.put<PosNeedsAttentionController>(c);
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: PosNeedsAttentionView(controller: c)))); // the older screens size text with ResponsiveSizer
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('each item says what happened and offers the right actions: paid-after-expiry and unattached can be attached; an amount mismatch cannot', (t) async {
      pay.attentionItems..add(item(PosAttentionReason.paidAfterExpiry))..add(item(PosAttentionReason.anomaly, id: 'pi-2', minor: 150000))..add(item(PosAttentionReason.refundFailed, id: 'pi-3'));
      await mountAttention(t);
      expect(find.text('Digital payments (Raast)'), findsOneWidget);
      expect(find.textContaining('Paid after the QR expired'), findsOneWidget);
      expect(find.textContaining('Amount did not match'), findsOneWidget);
      expect(find.textContaining('Refund failed'), findsOneWidget);
      expect(find.textContaining(rs1500), findsNWidgets(3));
      expect(find.byKey(const Key('digitalAttach')), findsOneWidget); // only the paid-after-expiry item
      expect(find.byKey(const Key('digitalRefund')), findsNWidgets(3));
      expect(find.byKey(const Key('digitalResolve')), findsNWidgets(3));
      expect(find.text('Retry refund'), findsOneWidget);
    });

    testWidgets('a CASHIER sees them read-only: "Ask a manager" and no action buttons', (t) async {
      pay.attentionItems.add(item(PosAttentionReason.paidAfterExpiry));
      await mountAttention(t, manager: false);
      expect(find.text('Ask a manager to resolve this.'), findsOneWidget);
      expect(find.byKey(const Key('digitalRefund')), findsNothing);
      await c.refund(item(PosAttentionReason.paidAfterExpiry)); // even calling it directly does nothing
      expect(pay.reconcileCalls, isEmpty);
    });

    testWidgets('REFUND asks for confirmation; Cancel changes nothing, Refund calls the server with resolution "refund"', (t) async {
      pay.attentionItems.add(item(PosAttentionReason.paidAfterExpiry));
      await mountAttention(t);
      await t.tap(find.byKey(const Key('digitalRefund')));
      await t.pumpAndSettle();
      expect(find.textContaining('Refund $rs1500'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(pay.reconcileCalls, isEmpty);
      await t.tap(find.byKey(const Key('digitalRefund')));
      await t.pumpAndSettle();
      await t.tap(find.text('Refund').last);
      await t.pumpAndSettle();
      expect(pay.reconcileCalls.single, containsPair('resolution', 'refund'));
      expect(pay.reconcileCalls.single['id'], 'pi-1');
    });

    testWidgets('ATTACH needs a receipt number and sends it as saleNumber', (t) async {
      pay.attentionItems.add(item(PosAttentionReason.confirmedUnattached));
      await mountAttention(t);
      await t.tap(find.byKey(const Key('digitalAttach')));
      await t.pumpAndSettle();
      await t.tap(find.text('Attach'));
      await t.pumpAndSettle();
      expect(pay.reconcileCalls, isEmpty); // empty receipt number: refused in the dialog
      await t.enterText(find.byType(TextField).last, 'POS-00012');
      await t.tap(find.text('Attach'));
      await t.pumpAndSettle();
      expect(pay.reconcileCalls.single, containsPair('resolution', 'sale_recorded'));
      expect(pay.reconcileCalls.single['saleNumber'], 'POS-00012');
    });

    testWidgets('RESOLVE WITH NOTE needs at least 10 characters, then sends the note', (t) async {
      pay.attentionItems.add(item(PosAttentionReason.anomaly));
      await mountAttention(t);
      await t.tap(find.byKey(const Key('digitalResolve')));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).last, 'too short');
      await t.tap(find.text('Resolve'));
      await t.pumpAndSettle();
      expect(pay.reconcileCalls, isEmpty);
      await t.enterText(find.byType(TextField).last, 'cash handed back at the counter');
      await t.tap(find.text('Resolve'));
      await t.pumpAndSettle();
      expect(pay.reconcileCalls.single, containsPair('resolution', 'resolved'));
      expect(pay.reconcileCalls.single['note'], 'cash handed back at the counter');
    });

    testWidgets('the list is reloaded after an action, and a refused action shows the server\'s reason instead of pretending it worked', (t) async {
      pay.attentionItems.add(item(PosAttentionReason.paidAfterExpiry));
      await mountAttention(t);
      pay.reconcileAnswer = FakePaymentsRepo.refused('REFUND_FAILED', 'The provider declined the refund');
      pay.attentionItems.clear();
      await t.tap(find.byKey(const Key('digitalRefund')));
      await t.pumpAndSettle();
      await t.tap(find.text('Refund').last);
      await t.pumpAndSettle();
      expect(find.textContaining('The provider declined the refund'), findsOneWidget);
      expect(pay.reconcileCalls, hasLength(1));
      await t.pump(const Duration(seconds: 4));
    });
  });
}
