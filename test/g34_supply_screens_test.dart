// G3.4 supply screens on phone, tablet and dark: every state (loading, empty, error, needs-internet / read-only last-synced), the cashier's
// money-free view, and the success flows against a mocked repository. Money is shown only in the response's own currency.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_supply_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/pay_supplier_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/payables_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_ledger_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/pay_supplier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/payables_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_form_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/po_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/receive_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_ledger_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_profile_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_return_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_home_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/g34_fixtures.dart';
import 'support/sale_harness.dart' show MockPosRepository;

// a tall phone so a lazily built list shows its whole content
const _phone = Size(390, 1500);
const _tablet = Size(834, 1194);

enum _Env { phone, tablet, dark }

void main() {
  late MockPosRepository repo;
  late SupplyOrdersCache cache;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    Money.configure(currency: 'USD', exponent: 2);
    repo = MockPosRepository();
    cache = testSupplyCache();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(theme: env == _Env.dark ? AppTheme.dark : AppTheme.light, home: w),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.tap(f);
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.enterText(find.descendant(of: f, matching: find.byType(TextField)), text);
    await t.pump();
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
  bool noMoney(WidgetTester t) => find.textContaining(RegExp(r'\$\s?\d')).evaluate().isEmpty && find.textContaining('USD').evaluate().isEmpty;

  // ── hub ────────────────────────────────────────────────────────────────────────────────────────
  testWidgets('supply home lists suppliers, orders, receiving and payables', (t) async {
    await pump(t, const SupplyHomeView());
    for (final s in ['Purchase orders', 'Receive stock', 'Suppliers', 'Payables']) {
      expect(find.text(s), findsOneWidget);
    }
    expect(t.takeException(), isNull);
  });

  // ── suppliers list ─────────────────────────────────────────────────────────────────────────────
  group('SupplierListView', () {
    SupplierListController put() => Get.put(SupplierListController(repository: repo, storeId: 'st1'));

    for (final env in _Env.values) {
      testWidgets('${env.name}: name, contact, balance owed (AmountText) and open orders', (t) async {
        when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier(), supplier(id: 's2', name: 'Other Co', balance: 0, open: 0)]));
        await pump(t, SupplierListView(controller: put()), env);
        expect(find.text('Dev Supplies'), findsOneWidget);
        expect(find.text('Sam · 0300111'), findsNWidgets(2));
        expect(find.byType(AmountText), findsNWidgets(2));
        expect(find.text('2 open orders'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('loading', (t) async {
      final c = Completer<SupplierList?>();
      when(() => repo.getSuppliers('st1')).thenAnswer((_) => c.future);
      await pump(t, SupplierListView(controller: put()));
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      c.complete(supplierList([]));
      await t.pump();
    });

    testWidgets('empty offers adding the first supplier', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([]));
      await pump(t, SupplierListView(controller: put()));
      expect(find.text('No suppliers yet'), findsOneWidget);
      expect(find.text('Add supplier'), findsWidgets);
    });

    testWidgets('error shows the server message with a retry', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      await pump(t, SupplierListView(controller: put()));
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline: Needs internet, the add button is disabled, no request is made', (t) async {
      offline();
      await pump(t, SupplierListView(controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
      expect(t.widget<IconButton>(find.byKey(const Key('suppliersAdd'))).onPressed, isNull);
      verifyNever(() => repo.getSuppliers(any()));
    });

    testWidgets('a response with no currency shows no money', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()], cur: null));
      await pump(t, SupplierListView(controller: put()));
      expect(find.text('Dev Supplies'), findsOneWidget);
      expect(find.byType(AmountText), findsNothing);
    });

    testWidgets('search narrows the list', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier(), supplier(id: 's2', name: 'Other Co')]));
      await pump(t, SupplierListView(controller: put()));
      await t.enterText(find.byType(TextField).first, 'other');
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Dev Supplies'), findsNothing);
      expect(find.text('Other Co'), findsOneWidget);
    });
  });

  // ── supplier form sheet ────────────────────────────────────────────────────────────────────────
  group('SupplierFormSheet', () {
    testWidgets('save is disabled until there is a name; saving sends the filled fields and closes', (t) async {
      final c = SupplierFormController(repository: repo, storeId: 'st1');
      Supplier? saved;
      when(() => repo.createSupplier('st1', any())).thenAnswer((_) async => (success: true, message: null, code: null, supplier: supplier(name: 'Acme')));
      await pump(
        t,
        Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () async => saved = await showModalBottomSheet<Supplier>(
                context: ctx,
                isScrollControlled: true,
                builder: (_) => SingleChildScrollView(child: SupplierFormSheet(controller: c)),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(t.widget<AppButton>(find.byKey(const Key('sfSave'))).onPressed, isNull);
      await typeKey(t, 'sfName', 'Acme');
      await typeKey(t, 'sfNtn', '123-4');
      expect(t.widget<AppButton>(find.byKey(const Key('sfSave'))).onPressed, isNotNull);
      await tapKey(t, 'sfSave');
      await t.pumpAndSettle();
      expect(saved?.name, 'Acme');
      verify(() => repo.createSupplier('st1', {'name': 'Acme', 'ntn': '123-4'})).called(1);
    });

    testWidgets('a server error stays on the sheet; offline says Needs internet and disables save', (t) async {
      final c = SupplierFormController(repository: repo, storeId: 'st1')..name.value = 'Acme';
      when(() => repo.createSupplier('st1', any())).thenAnswer((_) async => (success: false, message: null, code: 'POS_ACTION_FORBIDDEN', supplier: null));
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierFormSheet(controller: c)),
        ),
      );
      await tapKey(t, 'sfSave');
      expect(find.byKey(const Key('sfError')), findsOneWidget);
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
    });

    testWidgets('offline', (t) async {
      offline();
      final c = SupplierFormController(repository: repo, storeId: 'st1')..name.value = 'Acme';
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierFormSheet(controller: c)),
        ),
      );
      expect(find.byKey(const Key('sfOffline')), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('sfSave'))).onPressed, isNull);
    });
  });

  // ── supplier profile ───────────────────────────────────────────────────────────────────────────
  group('SupplierProfileView', () {
    SupplierProfileController put() => Get.put(
      SupplierProfileController(supplierId: 's1', repository: repo, storeId: 'st1'),
      tag: 's1',
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: NTN / STRN, terms, aging buckets, recent orders and receipts', (t) async {
        when(() => repo.getSupplier('st1', 's1')).thenAnswer((_) async => supplierProfile());
        await pump(t, SupplierProfileView(supplierId: 's1', controller: put()), env);
        expect(find.text('1234567-8'), findsOneWidget);
        expect(find.text('STRN-1'), findsOneWidget);
        expect(find.text('Net 30'), findsOneWidget);
        for (final k in ['agingCurrent', 'aging30', 'aging60', 'aging90']) {
          expect(find.byKey(Key(k)), findsOneWidget);
        }
        expect(find.text(r'$50.00'), findsWidgets);
        await t.scrollUntilVisible(find.byKey(const Key('receipt_r1')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const Key('po_po1')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('loading, error and offline', (t) async {
      final c = Completer<SupplierProfile?>();
      when(() => repo.getSupplier('st1', 's1')).thenAnswer((_) => c.future);
      await pump(t, SupplierProfileView(supplierId: 's1', controller: put()));
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      c.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline without data: Needs internet', (t) async {
      offline();
      await pump(t, SupplierProfileView(supplierId: 's1', controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });

    testWidgets('no currency in the response: the balance and buckets show no money, and Pay is disabled', (t) async {
      when(() => repo.getSupplier('st1', 's1')).thenAnswer((_) async => supplierProfile(cur: null));
      await pump(t, SupplierProfileView(supplierId: 's1', controller: put()));
      expect(find.byKey(const Key('supplierBalance')), findsNothing);
      expect(t.widget<AppButton>(find.byKey(const Key('supplierPay'))).onPressed, isNull);
    });
  });

  // ── purchase order list ────────────────────────────────────────────────────────────────────────
  group('PoListView', () {
    PoListController put() => Get.put(PoListController(repository: repo, cache: cache, storeId: 'st1'));

    for (final env in _Env.values) {
      testWidgets('${env.name}: manager sees the status chips, totals and the new-order button', (t) async {
        when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson(), poJson(id: 'po2', number: 'PO-000002', status: 'draft')]));
        await pump(t, PoListView(controller: put()), env);
        for (final (id, _) in PoStatus.filters) {
          expect(find.byKey(Key('poFilter_$id')), findsOneWidget, reason: id);
        }
        expect(find.byKey(const Key('poTotal_po1')), findsOneWidget);
        expect(find.text(r'$26.50'), findsNWidgets(2));
        expect(find.byKey(const Key('poNew')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('cashier: only receivable orders, NO money anywhere, no chips, no new-order button', (t) async {
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson(costs: false)]));
      await pump(t, PoListView(controller: put()));
      expect(find.text('PO-000001'), findsOneWidget);
      expect(find.textContaining('10 to receive'), findsOneWidget, reason: 'the row says how much is still due');
      expect(find.byKey(const Key('poTotal_po1')), findsNothing);
      expect(find.byKey(const Key('poFilters')), findsNothing);
      expect(find.byKey(const Key('poNew')), findsNothing);
      expect(noMoney(t), isTrue);
    });

    testWidgets('picking a chip reloads with that status', (t) async {
      when(() => repo.getSupplyOrders('st1', status: any(named: 'status'), supplierId: null)).thenAnswer((i) async => poList([poJson(status: i.namedArguments[#status] as String)]));
      await pump(t, PoListView(controller: put()));
      await tapKey(t, 'poFilter_partially_received');
      verify(() => repo.getSupplyOrders('st1', status: 'partially_received', supplierId: null)).called(1);
    });

    testWidgets('loading / empty / error', (t) async {
      final c = Completer<PoList?>();
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) => c.future);
      final ctl = put();
      await pump(t, PoListView(controller: ctl));
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      c.complete(poList([]));
      await t.pump();
      await t.pump();
      expect(find.text('Nothing to receive'), findsOneWidget, reason: 'a cashier-looking (empty) list explains what would show');
      ctl.canManageHint.value = true; // the till knows the signed-in role is a manager
      await t.pump();
      expect(find.text('No purchase orders'), findsOneWidget);
    });

    testWidgets('error with the server message and retry', (t) async {
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      await pump(t, PoListView(controller: put()));
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline with a remembered list: "Last synced <time> — read only", rows shown, no new-order button', (t) async {
      await cache.save('st1', poList([poJson()]));
      offline();
      await pump(t, PoListView(controller: put()));
      expect(find.byKey(const Key('supplyLastSynced')), findsOneWidget);
      expect(find.textContaining('Last synced'), findsOneWidget);
      expect(find.textContaining('read only'), findsOneWidget);
      expect(find.text('PO-000001'), findsOneWidget);
      expect(find.byKey(const Key('poNew')), findsNothing);
      verifyNever(
        () => repo.getSupplyOrders(
          any(),
          status: any(named: 'status'),
          supplierId: any(named: 'supplierId'),
        ),
      );
    });

    testWidgets('offline, a remembered CASHIER list stays money-free', (t) async {
      await cache.save('st1', poList([poJson(costs: false)]));
      offline();
      await pump(t, PoListView(controller: put()));
      expect(find.byKey(const Key('supplyLastSynced')), findsOneWidget);
      expect(noMoney(t), isTrue);
    });

    testWidgets('offline with nothing remembered: Needs internet', (t) async {
      offline();
      await pump(t, PoListView(controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
      expect(find.byKey(const Key('supplyLastSynced')), findsNothing);
    });

    testWidgets('coming back online reloads the real list and drops the banner', (t) async {
      await cache.save('st1', poList([poJson()]));
      offline();
      when(() => repo.getSupplyOrders('st1', status: 'all', supplierId: null)).thenAnswer((_) async => poList([poJson(number: 'PO-000009')]));
      await pump(t, PoListView(controller: put()));
      expect(find.byKey(const Key('supplyLastSynced')), findsOneWidget);
      Get.find<NetworkStatusService>().isOnline.value = true;
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('supplyLastSynced')), findsNothing);
      expect(find.text('PO-000009'), findsOneWidget);
    });
  });

  // ── purchase order detail ──────────────────────────────────────────────────────────────────────
  group('PoDetailView', () {
    PoDetailController put({PurchaseOrder? o, Future<String?> Function({required String reason, PosRepositoryLike? repository})? approval}) {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: o ?? po(), cur: usd));
      return Get.put(
        PoDetailController(orderId: 'po1', repository: repo, storeId: 'st1'),
        tag: 'po1',
      );
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: manager sees ordered / received / damaged / remaining, totals and the actions of an approved order', (t) async {
        await pump(
          t,
          PoDetailView(
            orderId: 'po1',
            controller: put(o: po(items: [poLineJson(received: 4, damaged: 1)], editable: true)),
          ),
          env,
        );
        for (final q in ['Ordered 10', 'Received 4', 'Damaged 1', 'Remaining 5']) {
          expect(find.text(q), findsOneWidget, reason: q);
        }
        expect(find.byKey(const Key('poTotals')), findsOneWidget);
        expect(find.text(r'$26.50'), findsOneWidget);
        expect(find.byKey(const Key('poReceive')), findsOneWidget);
        expect(find.byKey(const Key('poSend')), findsOneWidget);
        expect(find.byKey(const Key('poApprove')), findsNothing);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('draft: Approve, Edit, Cancel; no Send, no Receive', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(status: 'draft')),
        ),
      );
      expect(find.byKey(const Key('poApprove')), findsOneWidget);
      expect(find.byKey(const Key('poEdit')), findsOneWidget);
      expect(find.byKey(const Key('poCancel')), findsOneWidget);
      expect(find.byKey(const Key('poSend')), findsNothing);
      expect(find.byKey(const Key('poReceive')), findsNothing);
    });

    testWidgets('partially received: Close short and Receive; no Edit / Cancel', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(status: 'partially_received', editable: false)),
        ),
      );
      expect(find.byKey(const Key('poCloseShort')), findsOneWidget);
      expect(find.byKey(const Key('poReceive')), findsOneWidget);
      expect(find.byKey(const Key('poEdit')), findsNothing);
      expect(find.byKey(const Key('poCancel')), findsNothing);
    });

    testWidgets('received and cancelled orders have no actions', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(status: 'received', editable: false)),
        ),
      );
      for (final k in ['poReceive', 'poApprove', 'poSend', 'poEdit', 'poCancel', 'poCloseShort']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('cashier: lines with quantities, NO money, and only the Receive button', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(costs: false)),
        ),
      );
      for (final q in ['Ordered 10', 'Received 0', 'Damaged 0', 'Remaining 10']) {
        expect(find.text(q), findsOneWidget, reason: q);
      }
      expect(find.byKey(const Key('poTotals')), findsNothing);
      expect(noMoney(t), isTrue);
      expect(find.byKey(const Key('poReceive')), findsOneWidget);
      for (final k in ['poApprove', 'poSend', 'poEdit', 'poCancel', 'poCloseShort']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('Approve: success updates the status; an owner-needed answer is a clear message', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(status: 'draft')),
        ),
      );
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED', order: null));
      await tapKey(t, 'poApprove');
      expect(find.byKey(const Key('poActionError')), findsOneWidget);
      expect(find.textContaining('store owner must do this'), findsOneWidget);
      when(() => repo.supplyOrderAction('st1', 'po1', 'approve')).thenAnswer((_) async => (success: true, message: null, code: null, order: po(status: 'approved')));
      await tapKey(t, 'poApprove');
      expect(find.byKey(const Key('poNotice')), findsOneWidget);
      expect(find.byKey(const Key('poSend')), findsOneWidget);
    });

    testWidgets('Cancel asks first, then cancels', (t) async {
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: put(o: po(status: 'draft')),
        ),
      );
      when(() => repo.supplyOrderAction('st1', 'po1', 'cancel')).thenAnswer((_) async => (success: true, message: null, code: null, order: po(status: 'cancelled', editable: false)));
      await tapKey(t, 'poCancel');
      expect(find.text('Cancel this order?'), findsOneWidget);
      verifyNever(() => repo.supplyOrderAction(any(), any(), 'cancel'));
      await t.tap(find.byKey(const Key('poConfirmYes')));
      await t.pumpAndSettle();
      verify(() => repo.supplyOrderAction('st1', 'po1', 'cancel')).called(1);
      expect(find.byKey(const Key('poCancel')), findsNothing);
    });

    testWidgets('loading, error and offline', (t) async {
      final c = Completer<PoDetail?>();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) => c.future);
      await pump(
        t,
        PoDetailView(
          orderId: 'po1',
          controller: Get.put(
            PoDetailController(orderId: 'po1', repository: repo, storeId: 'st1'),
            tag: 'po1',
          ),
        ),
      );
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      c.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, PoDetailView(orderId: 'po1', controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });
  });

  // ── purchase order form ────────────────────────────────────────────────────────────────────────
  group('PoFormView', () {
    PoFormController put({String? orderId, InvCur cur = usd}) {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()], cur: cur));
      when(
        () => repo.getInventoryStock(
          'st1',
          search: any(named: 'search'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => InvPage<InvRow>(items: [invRow(costMinor: null)], total: 1, page: 1, hasMore: false, cur: usd));
      return Get.put(
        PoFormController(orderId: orderId, repository: repo, storeId: 'st1', searchDebounce: const Duration(milliseconds: 5)),
        tag: 'po_${orderId ?? 'new'}',
      );
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: pick a supplier, search and add a product, set qty and cost, save', (t) async {
        final c = put();
        await pump(t, PoFormView(controller: c), env);
        expect(t.widget<AppButton>(find.byKey(const Key('poFormSave'))).onPressed, isNull);
        await tapKey(t, 'poFormSupplier');
        await tapKey(t, 'pickSupplier_s1');
        expect(find.text('Dev Supplies'), findsOneWidget);
        await tapKey(t, 'poAddProduct');
        await t.enterText(find.byType(TextField).last, 'latte');
        await t.pump(const Duration(milliseconds: 50));
        await t.pump(const Duration(milliseconds: 50));
        await tapKey(t, 'supplyPick_v1');
        expect(find.text('Dev Latte'), findsOneWidget);
        await tapKey(t, 'poLineQty_v1'); // the stepper widget itself; qty stays 1
        await typeKey(t, 'poLineCost_v1', '12.5');
        expect(find.byKey(const Key('poFormTotal')), findsOneWidget);
        expect(find.text(r'$12.50'), findsOneWidget);
        Map<String, dynamic>? sent;
        when(() => repo.createSupplyOrder('st1', any())).thenAnswer((i) async {
          sent = i.positionalArguments[1] as Map<String, dynamic>;
          return (success: true, message: null, code: null, order: po(status: 'draft'));
        });
        await tapKey(t, 'poFormSave');
        expect((sent!['items'] as List).single, {'variantId': 'v1', 'quantityOrdered': 1, 'unitCostMinor': 1250});
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a server error shows on the form', (t) async {
      final c = put();
      await pump(t, PoFormView(controller: c));
      c.pickSupplier(supplier());
      c.addProduct(invRow());
      await t.pump();
      when(() => repo.createSupplyOrder('st1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'DUPLICATE_LINE', order: null));
      await tapKey(t, 'poFormSave');
      expect(find.byKey(const Key('poFormError')), findsOneWidget);
      expect(find.textContaining('listed twice'), findsOneWidget);
    });

    testWidgets('edit mode: lines are prefilled, the draft note is shown, PO_NOT_EDITABLE is explained', (t) async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) async => PoDetail(order: po(), cur: usd));
      final c = put(orderId: 'po1');
      await pump(t, PoFormView(orderId: 'po1', controller: c));
      expect(find.byKey(const Key('poFormEditNote')), findsOneWidget);
      expect(find.text('Dev Latte'), findsOneWidget);
      when(() => repo.updateSupplyOrder('st1', 'po1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'PO_NOT_EDITABLE', order: null));
      await tapKey(t, 'poFormSave');
      expect(find.textContaining('Receiving has started'), findsOneWidget);
    });

    testWidgets('loading, load error, offline', (t) async {
      final comp = Completer<SupplierList?>();
      when(() => repo.getSuppliers('st1')).thenAnswer((_) => comp.future);
      await pump(
        t,
        PoFormView(
          controller: Get.put(
            PoFormController(repository: repo, storeId: 'st1'),
            tag: 'po_new',
          ),
        ),
      );
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, PoFormView(controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });
  });

  // ── receive ────────────────────────────────────────────────────────────────────────────────────
  group('ReceiveView', () {
    ReceiveController putPo({bool costs = false, bool trackLots = false}) {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer(
        (_) async => PoDetail(
          order: po(
            costs: costs,
            items: [
              poLineJson(costs: costs, trackLots: trackLots),
              poLineJson(id: 'li2', variantId: 'v2', name: 'Dev Mocha', ordered: 4, costs: costs),
            ],
          ),
          cur: usd,
        ),
      );
      return Get.put(
        ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1', requestIdFactory: () => 'rid'),
        tag: 'recv_po1',
      );
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: cashier receives against the order: steppers, no cost field, success shows the GRN number', (t) async {
        final c = putPo();
        await pump(t, ReceiveView(orderId: 'po1', controller: c), env);
        expect(find.text('PO-000001'), findsOneWidget);
        expect(find.byKey(const Key('recvLine_li1')), findsOneWidget);
        expect(find.byKey(const Key('recvCost_li1')), findsNothing, reason: 'a cashier receives at the purchase-order cost');
        expect(noMoney(t), isTrue);
        expect(t.widget<AppButton>(find.byKey(const Key('recvConfirm'))).onPressed, isNull);
        await tapKey(t, 'recvGood_li1'); // the stepper
        c.lines[0].good.value = 6;
        await t.pump();
        when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: true, message: null, code: null, result: receiveResult(costs: false)));
        await tapKey(t, 'recvConfirm');
        expect(find.byKey(const Key('recvGrn')), findsOneWidget);
        expect(find.text('GRN-000001'), findsOneWidget);
        expect(find.byKey(const Key('recvTotal')), findsNothing, reason: 'no money for a cashier');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('LOT_REQUIRED: the lot field appears after the server error, and the receipt then goes through', (t) async {
      final c = putPo();
      await pump(t, ReceiveView(orderId: 'po1', controller: c));
      c.lines[0].good.value = 2;
      await t.pump();
      expect(find.byKey(const Key('recvLot_li1')), findsNothing);
      expect(find.byKey(const Key('recvAddLot_li1')), findsOneWidget);
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: false, message: 'Dev Latte tracks lots: enter the lot number.', code: 'LOT_REQUIRED', result: null));
      await tapKey(t, 'recvConfirm');
      expect(find.text('Dev Latte tracks lots: enter the lot number.'), findsOneWidget);
      expect(find.byKey(const Key('recvLot_li1')), findsOneWidget);
      await typeKey(t, 'recvLot_li1', 'L-1');
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: true, message: null, code: null, result: receiveResult(costs: false)));
      await tapKey(t, 'recvConfirm');
      expect(find.byKey(const Key('recvGrn')), findsOneWidget);
    });

    testWidgets('a variant known to track lots shows the lot field up front', (t) async {
      await pump(t, ReceiveView(orderId: 'po1', controller: putPo(trackLots: true)));
      expect(find.byKey(const Key('recvLot_li1')), findsOneWidget);
      expect(find.text('Expiry date'), findsOneWidget, reason: 'the expiry picker is there too, only on the lot-tracked line');
      expect(find.byKey(const Key('recvLot_li2')), findsNothing);
    });

    testWidgets('OVER_RECEIPT shows the server sentence', (t) async {
      final c = putPo();
      await pump(t, ReceiveView(orderId: 'po1', controller: c));
      c.lines[0].good.value = 3;
      await t.pump();
      when(
        () => repo.receiveSupply('st1', any()),
      ).thenAnswer((_) async => (success: false, message: 'Dev Latte: only 1 more can be received on this purchase order.', code: 'OVER_RECEIPT', result: null));
      await tapKey(t, 'recvConfirm');
      expect(find.text('Dev Latte: only 1 more can be received on this purchase order.'), findsOneWidget);
    });

    testWidgets('a duplicate (retried) receipt says it had already been recorded', (t) async {
      final c = putPo();
      await pump(t, ReceiveView(orderId: 'po1', controller: c));
      c.lines[0].good.value = 3;
      await t.pump();
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: true, message: null, code: null, result: receiveResult(duplicate: true, costs: false)));
      await tapKey(t, 'recvConfirm');
      expect(find.byKey(const Key('recvDuplicate')), findsOneWidget);
    });

    testWidgets('a manager\'s receipt shows the total in the response currency', (t) async {
      final c = putPo(costs: true);
      await pump(t, ReceiveView(orderId: 'po1', controller: c));
      c.lines[0].good.value = 3;
      await t.pump();
      when(() => repo.receiveSupply('st1', any())).thenAnswer((_) async => (success: true, message: null, code: null, result: receiveResult()));
      await tapKey(t, 'recvConfirm');
      expect(find.text(r'Total $25.00'), findsOneWidget);
    });

    testWidgets('direct receiving (manager): supplier picker, add product, unit cost field, then success', (t) async {
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => supplierList([supplier()]));
      when(
        () => repo.getInventoryStock(
          'st1',
          search: any(named: 'search'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => InvPage<InvRow>(items: [invRow(trackLots: true, costMinor: null)], total: 1, page: 1, hasMore: false, cur: usd));
      final c = Get.put(
        ReceiveController(repository: repo, storeId: 'st1', requestIdFactory: () => 'rid', searchDebounce: const Duration(milliseconds: 5)),
        tag: 'recv_direct',
      );
      await pump(t, ReceiveView(controller: c));
      expect(find.byKey(const Key('recvSupplier')), findsOneWidget);
      expect(find.byKey(const Key('recvNoLines')), findsOneWidget);
      await tapKey(t, 'recvSupplier');
      await tapKey(t, 'pickSupplier_s1');
      await tapKey(t, 'recvAddProduct');
      await t.enterText(find.byType(TextField).last, 'latte');
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));
      await tapKey(t, 'supplyPick_v1');
      expect(find.byKey(const Key('recvCost_v1')), findsOneWidget);
      expect(find.byKey(const Key('recvLot_v1')), findsOneWidget, reason: 'the product tracks lots');
      await typeKey(t, 'recvCost_v1', '2.5');
      await typeKey(t, 'recvLot_v1', 'L9');
      Map<String, dynamic>? sent;
      when(() => repo.receiveSupply('st1', any())).thenAnswer((i) async {
        sent = i.positionalArguments[1] as Map<String, dynamic>;
        return (success: true, message: null, code: null, result: receiveResult());
      });
      await tapKey(t, 'recvConfirm');
      expect((sent!['lines'] as List).single, {'variantId': 'v1', 'qtyGood': 1, 'qtyDamaged': 0, 'lotNumber': 'L9', 'unitCostMinor': 250});
      expect(find.byKey(const Key('recvGrn')), findsOneWidget);
    });

    testWidgets('loading / load error / offline', (t) async {
      final comp = Completer<PoDetail?>();
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer((_) => comp.future);
      await pump(
        t,
        ReceiveView(
          orderId: 'po1',
          controller: Get.put(
            ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1'),
            tag: 'recv_po1',
          ),
        ),
      );
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('nothing left to receive', (t) async {
      when(() => repo.getSupplyOrder('st1', 'po1')).thenAnswer(
        (_) async => PoDetail(
          order: po(costs: false, items: [poLineJson(costs: false, received: 10)]),
          cur: usd,
        ),
      );
      await pump(
        t,
        ReceiveView(
          orderId: 'po1',
          controller: Get.put(
            ReceiveController(orderId: 'po1', repository: repo, storeId: 'st1'),
            tag: 'recv_po1',
          ),
        ),
      );
      expect(find.text('Everything on this order has been received.'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, ReceiveView(orderId: 'po1', controller: putPo()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });
  });

  // ── supplier return ────────────────────────────────────────────────────────────────────────────
  group('SupplierReturnSheet', () {
    testWidgets('pick quantities and a reason; the credit created is shown', (t) async {
      final c = SupplierReturnController(receipt: receipt(), repository: repo, storeId: 'st1')..onInit();
      when(() => repo.createSupplierReturn('st1', any())).thenAnswer(
        (_) async =>
            (success: true, message: null, code: null, result: SupplierReturnResult(id: 'x', returnNumber: 'SR-000001', supplierName: 'Dev Supplies', reason: 'damaged', creditMinor: 750, cur: usd)),
      );
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierReturnSheet(controller: c)),
        ),
      );
      expect(t.widget<AppButton>(find.byKey(const Key('retConfirm'))).onPressed, isNull);
      c.lines.single.qty.value = 3;
      await t.pump();
      await tapKey(t, 'retReason_damaged');
      await tapKey(t, 'retConfirm');
      expect(find.byKey(const Key('retNumber')), findsOneWidget);
      expect(find.text(r'$7.50'), findsOneWidget);
    });

    testWidgets('EXCEEDS_RECEIPT is shown on the sheet', (t) async {
      final c = SupplierReturnController(receipt: receipt(), repository: repo, storeId: 'st1')..onInit();
      c.lines.single.qty.value = 3;
      when(() => repo.createSupplierReturn('st1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'EXCEEDS_RECEIPT', result: null));
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierReturnSheet(controller: c)),
        ),
      );
      await tapKey(t, 'retConfirm');
      expect(find.byKey(const Key('retError')), findsOneWidget);
    });

    testWidgets('from a supplier: lists receipts first; empty and offline states', (t) async {
      when(() => repo.getSupplyReceipts('st1', supplierId: 's1')).thenAnswer((_) async => [receipt()]);
      final c = SupplierReturnController(supplierId: 's1', repository: repo, storeId: 'st1');
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierReturnSheet(controller: c)),
        ),
      );
      expect(find.byKey(const Key('retReceipt_r1')), findsOneWidget);
      await tapKey(t, 'retReceipt_r1');
      expect(find.byKey(const Key('retConfirm')), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      final c = SupplierReturnController(receipt: receipt(), repository: repo, storeId: 'st1');
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(child: SupplierReturnSheet(controller: c)),
        ),
      );
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });
  });

  // ── pay supplier ───────────────────────────────────────────────────────────────────────────────
  group('PaySupplierSheet', () {
    PaySupplierController make({String? session = 'sess1', int exponent = 2}) =>
        PaySupplierController(supplierId: 's1', exponent: exponent, balanceMinor: 5000, repository: repo, storeId: 'st1', sessionIdProvider: () async => session, requestIdFactory: () => 'pay-1');
    Future<PaySupplierController> mount(WidgetTester t, PaySupplierController c, [_Env env = _Env.phone]) async {
      c.onInit();
      await pump(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: PaySupplierSheet(controller: c, currencyCode: 'USD'),
          ),
        ),
        env,
      );
      return c;
    }

    testWidgets('no open shift: "Open a shift to pay cash" and cash cannot be chosen', (t) async {
      await mount(t, make(session: null));
      expect(find.byKey(const Key('paNoShift')), findsOneWidget);
      expect(find.text('Open a shift to pay cash'), findsOneWidget);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('paCash'))).onSelected, isNull);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('paBank'))).selected, isTrue);
    });

    for (final env in _Env.values) {
      testWidgets('${env.name}: open shift: cash is the default; paying the full balance records it and closes with true', (t) async {
        final c = await mount(t, make(), env);
        expect(find.byKey(const Key('paNoShift')), findsNothing);
        expect(c.method.value, 'cash');
        await tapKey(t, 'paFull');
        await typeKey(t, 'paReference', 'slip 4');
        when(
          () => repo.paySupplier('st1', 's1', amountMinor: 5000, method: 'cash', requestId: 'pay-1', reference: 'slip 4', sessionId: 'sess1', approverToken: null),
        ).thenAnswer((_) async => (success: true, message: null, code: null, result: SupplierPaymentResult(amountMinor: 5000, method: 'cash', balanceMinor: 0, cur: usd)));
        await tapKey(t, 'paConfirm');
        expect(c.result.value!.balanceMinor, 0);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('EXCEEDS_BALANCE and POS_OWNER_REQUIRED are shown in plain words', (t) async {
      final c = await mount(t, make(session: null));
      await typeKey(t, 'paAmount', '900');
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'EXCEEDS_BALANCE', result: null));
      await tapKey(t, 'paConfirm');
      expect(find.text('That is more than is owed to this supplier.'), findsOneWidget);
      when(
        () => repo.paySupplier(
          any(),
          any(),
          amountMinor: any(named: 'amountMinor'),
          method: any(named: 'method'),
          requestId: any(named: 'requestId'),
          reference: any(named: 'reference'),
          sessionId: any(named: 'sessionId'),
          approverToken: any(named: 'approverToken'),
        ),
      ).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED', result: null));
      await tapKey(t, 'paConfirm');
      expect(find.textContaining('store owner must do this'), findsOneWidget);
      expect(c.busy.value, isFalse);
    });

    testWidgets('the confirm button needs a valid amount; at exponent 0 decimals are refused', (t) async {
      await mount(t, make(session: null, exponent: 0));
      expect(t.widget<AppButton>(find.byKey(const Key('paConfirm'))).onPressed, isNull);
      await typeKey(t, 'paAmount', '5.5');
      expect(t.widget<AppButton>(find.byKey(const Key('paConfirm'))).onPressed, isNull);
      await typeKey(t, 'paAmount', '5');
      expect(t.widget<AppButton>(find.byKey(const Key('paConfirm'))).onPressed, isNotNull);
    });

    testWidgets('offline: says Needs internet and cannot confirm', (t) async {
      offline();
      await mount(t, make(session: null));
      await typeKey(t, 'paAmount', '5');
      expect(find.byKey(const Key('paOffline')), findsOneWidget);
      expect(t.widget<AppButton>(find.byKey(const Key('paConfirm'))).onPressed, isNull);
    });
  });

  // ── payables ───────────────────────────────────────────────────────────────────────────────────
  group('PayablesView', () {
    PayablesController put() => Get.put(PayablesController(repository: repo, storeId: 'st1'));

    for (final env in _Env.values) {
      testWidgets('${env.name}: totals with aging and each supplier\'s balance and buckets', (t) async {
        when(() => repo.getPayables('st1')).thenAnswer((_) async => payables());
        await pump(t, PayablesView(controller: put()), env);
        expect(find.byKey(const Key('payablesTotal')), findsOneWidget);
        expect(find.text(r'$80.00'), findsOneWidget);
        expect(find.byKey(const Key('payable_s1')), findsOneWidget);
        expect(find.byKey(const Key('payable_s2')), findsOneWidget);
        expect(find.byKey(const Key('agingCurrent')), findsWidgets);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('nothing owed', (t) async {
      when(() => repo.getPayables('st1')).thenAnswer((_) async => Payables(totals: aging(balance: 0, current: 0, d30: 0, d60: 0), suppliers: const [], cur: usd));
      await pump(t, PayablesView(controller: put()));
      expect(find.text('Nothing owed'), findsOneWidget);
    });

    testWidgets('loading, error (forbidden for a cashier), offline, and no currency means no money', (t) async {
      final comp = Completer<Payables?>();
      when(() => repo.getPayables('st1')).thenAnswer((_) => comp.future);
      await pump(t, PayablesView(controller: put()));
      expect(find.byKey(const Key('supplyLoading')), findsOneWidget);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      comp.complete(null);
      await t.pump();
      await t.pump();
      expect(find.text('Your role is not allowed to do this.'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, PayablesView(controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });

    testWidgets('a response with no currency shows no money', (t) async {
      when(() => repo.getPayables('st1')).thenAnswer((_) async => payables(cur: null));
      await pump(t, PayablesView(controller: put()));
      expect(find.byKey(const Key('payablesTotal')), findsNothing);
      expect(find.byKey(const Key('payable_s1')), findsOneWidget);
    });
  });

  // ── ledger ─────────────────────────────────────────────────────────────────────────────────────
  group('SupplierLedgerView', () {
    SupplierLedgerController put() => Get.put(
      SupplierLedgerController(supplierId: 's1', repository: repo, storeId: 'st1'),
      tag: 's1',
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: entries with the running balance, newest first, and the Pay button', (t) async {
        when(() => repo.getSupplierLedger('st1', 's1')).thenAnswer((_) async => ledger());
        await pump(t, SupplierLedgerView(supplierId: 's1', controller: put()), env);
        expect(find.byKey(const Key('ledger_e2')), findsOneWidget);
        expect(find.byKey(const Key('ledgerBalance_e2')), findsOneWidget);
        expect(find.text(r'Balance $50.00'), findsOneWidget);
        expect(find.text(r'Balance $60.00'), findsOneWidget);
        expect(find.text('Payment'), findsOneWidget);
        expect(find.text('Goods received'), findsOneWidget);
        expect(find.byKey(const Key('ledgerPay')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('Pay opens the pay sheet', (t) async {
      when(() => repo.getSupplierLedger('st1', 's1')).thenAnswer((_) async => ledger());
      await pump(t, SupplierLedgerView(supplierId: 's1', controller: put()));
      await tapKey(t, 'ledgerPay');
      expect(find.byKey(const Key('paAmount')), findsOneWidget);
    });

    testWidgets('empty ledger, error, loading and offline', (t) async {
      when(() => repo.getSupplierLedger('st1', 's1')).thenAnswer((_) async => SupplierLedger(supplier: supplier(), aging: const Aging(), entries: const [], cur: usd));
      await pump(t, SupplierLedgerView(supplierId: 's1', controller: put()));
      expect(find.text('No entries yet'), findsOneWidget);
    });

    testWidgets('error', (t) async {
      when(() => repo.getSupplierLedger('st1', 's1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('SUPPLIER_NOT_FOUND');
      await pump(t, SupplierLedgerView(supplierId: 's1', controller: put()));
      expect(find.text('That supplier was not found.'), findsOneWidget);
    });

    testWidgets('offline: Needs internet', (t) async {
      offline();
      await pump(t, SupplierLedgerView(supplierId: 's1', controller: put()));
      expect(find.byKey(const Key('supplyNeedsInternet')), findsOneWidget);
    });
  });
}

/// (typedef kept loose so the approval type of the controller is not repeated in the tests)
typedef PosRepositoryLike = Object;
