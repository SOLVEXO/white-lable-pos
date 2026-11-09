// G3.1 inventory screens: phone, tablet (>= 700 px) and dark, no overflow, the key elements, and the role-hidden ones absent for a cashier.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_adjust_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_count_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_limits_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_movements_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_adjust_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_count_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_limits_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_movements_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_overview_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_stock_list_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'support/inventory_fixtures.dart';
import 'support/sale_harness.dart';

const _phone = Size(390, 844);
const _tablet = Size(834, 1194);

enum _Env { phone, tablet, dark }

void main() {
  late MockPosRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    Get.testMode = true;
    Get.reset();
    repo = MockPosRepository();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  Future<void> pump(WidgetTester t, Widget w, _Env env) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(theme: env == _Env.dark ? AppTheme.dark : AppTheme.light, home: w),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  void stubStock(List<InvRow> rows, {bool hasMore = false}) => when(
    () => repo.getInventoryStock(
      any(),
      search: any(named: 'search'),
      filter: any(named: 'filter'),
      page: any(named: 'page'),
      limit: any(named: 'limit'),
    ),
  ).thenAnswer((_) async => rowsPage(rows, hasMore: hasMore));

  for (final env in _Env.values) {
    group('screens (${env.name})', () {
      testWidgets('overview: manager sees tiles, value, open-count banner and every action', (t) async {
        when(() => repo.getInventoryOverview(any())).thenAnswer((_) async => overview(openCount: true));
        await pump(
          t,
          InvOverviewView(
            controller: Get.put(InvOverviewController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        for (final k in [
          'invTileSkus',
          'invTileLow',
          'invTileOut',
          'invTileExpired',
          'invTileExp7',
          'invTileExp30',
          'invTileValue',
          'invOpenCountBanner',
          'invContinueCount',
          'invNoCostNote',
          'invRowStock',
          'invRowLow',
          'invRowMovements',
          'invRowCount',
          'invRowLimits',
        ]) {
          await t.scrollUntilVisible(find.byKey(Key(k)), 100, scrollable: find.byType(Scrollable).first);
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('\$12,345.00'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('overview: a cashier sees quantities only (no value, history, limits; count row only when one is open)', (t) async {
        when(() => repo.getInventoryOverview(any())).thenAnswer((_) async => overview(role: 'cashier'));
        await pump(
          t,
          InvOverviewView(
            controller: Get.put(InvOverviewController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        expect(find.byKey(const Key('invTileSkus')), findsOneWidget);
        expect(find.byKey(const Key('invRowStock')), findsOneWidget);
        for (final k in ['invTileValue', 'invRowMovements', 'invRowLimits', 'invRowCount', 'invOpenCountBanner', 'invNoCostNote']) {
          expect(find.byKey(Key(k)), findsNothing, reason: k);
        }
        expect(t.takeException(), isNull);
      });

      testWidgets('overview: a cashier can continue an open count', (t) async {
        when(() => repo.getInventoryOverview(any())).thenAnswer((_) async => overview(role: 'cashier', openCount: true));
        await pump(
          t,
          InvOverviewView(
            controller: Get.put(InvOverviewController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        expect(find.byKey(const Key('invContinueCount')), findsOneWidget);
        expect(find.byKey(const Key('invRowCount')), findsOneWidget);
        expect(find.byKey(const Key('invRowMovements')), findsNothing);
      });

      testWidgets('stock list: rows with Low / Out badges, cost only for managers, filter chips', (t) async {
        stubStock([row(id: 'a', name: 'Dev Latte'), row(id: 'b', name: 'Dev Croissant', stock: 2, low: true), row(id: 'c', name: 'Dev Beans', stock: 0, out: true)]);
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1'),
              tag: 'x',
            ),
          ),
          env,
        );
        expect(find.byKey(const Key('invRow_a')), findsOneWidget);
        expect(find.text('Low'), findsWidgets);
        expect(find.text('Out'), findsWidgets);
        expect(find.byKey(const Key('invRowCost_a')), findsOneWidget);
        for (final f in ['all', 'low', 'out']) {
          expect(find.byKey(Key('invFilter_$f')), findsOneWidget);
        }
        expect(t.takeException(), isNull);
      });

      testWidgets('stock list: a cashier row shows no cost or value', (t) async {
        stubStock([row(id: 'a', manager: false)]);
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1'),
              tag: 'x',
            ),
          ),
          env,
        );
        expect(find.byKey(const Key('invRow_a')), findsOneWidget);
        expect(find.byKey(const Key('invRowCost_a')), findsNothing);
      });

      testWidgets('low stock screen has no filter chips; empty and error states are explained', (t) async {
        stubStock([]);
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1', lowOnly: true),
              tag: 'low',
            ),
          ),
          env,
        );
        expect(find.text('Low stock'), findsOneWidget);
        expect(find.byKey(const Key('invFilter_all')), findsNothing);
        expect(find.text('Nothing is low'), findsOneWidget);
        Get.reset();
        when(
          () => repo.getInventoryStock(
            any(),
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => null);
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1'),
              tag: 'y',
            ),
          ),
          env,
        );
        expect(find.text('Try again'), findsOneWidget);
      });

      testWidgets('detail (manager): stock, committed / damaged, locations, lots with expiry badges, movements, ledger note, Adjust', (t) async {
        when(() => repo.getInventoryVariant(any(), any())).thenAnswer((_) async => detail());
        final c = Get.put(
          InvDetailController(variantId: 'v1', repository: repo, storeId: 's1', role: 'manager'),
          tag: 'v1',
        );
        await pump(t, InvDetailView(variantId: 'v1', controller: c, now: DateTime(2026, 11, 9)), env);
        expect(find.byKey(const Key('invDetailStock')), findsOneWidget);
        expect(find.text('20 on hand'), findsOneWidget);
        expect(find.byKey(const Key('invDetailCommitted')), findsOneWidget);
        expect(find.byKey(const Key('invDetailCost')), findsOneWidget);
        expect(find.byKey(const Key('invAdjustButton')), findsOneWidget);
        for (final k in ['invLoc_l1', 'invLot_lot1', 'invLot_lot2', 'invLot_lot3', 'movement_m1', 'invLedgerNote']) {
          await t.scrollUntilVisible(find.byKey(Key(k)), 100, scrollable: find.byType(Scrollable).first);
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('Expired'), findsOneWidget); // 5 Nov
        expect(find.text('Expires in 3 d'), findsOneWidget); // 12 Nov: within 7 days
        expect(find.textContaining('History starts'), findsOneWidget);
        expect(find.text('Marked damaged'), findsOneWidget);
        expect(find.text('−2'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('detail (cashier): no cost, no movements section', (t) async {
        when(() => repo.getInventoryVariant(any(), any())).thenAnswer((_) async => detail(manager: false));
        final c = Get.put(
          InvDetailController(variantId: 'v1', repository: repo, storeId: 's1', role: 'cashier'),
          tag: 'v1',
        );
        await pump(t, InvDetailView(variantId: 'v1', controller: c), env);
        expect(find.byKey(const Key('invDetailStock')), findsOneWidget);
        expect(find.byKey(const Key('invDetailCost')), findsNothing);
        expect(find.byKey(const Key('invDetailValue')), findsNothing);
        expect(find.text('Recent movements'), findsNothing);
        expect(find.byKey(const Key('invAdjustButton')), findsOneWidget);
      });

      testWidgets('detail: history note says so when nothing is recorded; unlimited items have no Adjust', (t) async {
        when(() => repo.getInventoryVariant(any(), any())).thenAnswer((_) async => detail(withLots: false, withMoves: false, noLedger: true, unlimited: true));
        final c = Get.put(
          InvDetailController(variantId: 'v1', repository: repo, storeId: 's1', role: 'manager'),
          tag: 'v1',
        );
        await pump(t, InvDetailView(variantId: 'v1', controller: c), env);
        await t.scrollUntilVisible(find.byKey(const Key('invNoMovements')), 100, scrollable: find.byType(Scrollable).first);
        expect(find.text('No movements recorded yet'), findsOneWidget);
        expect(find.byKey(const Key('invAdjustButton')), findsNothing);
        expect(find.text('Unlimited stock'), findsWidgets);
      });

      testWidgets('adjust sheet: stepper and typed number agree, reason chips, note label follows the reason, confirm needs a change and a reason', (t) async {
        final c = InvAdjustController(variantId: 'v1', currentStock: 20, repository: repo, storeId: 's1');
        await pump(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InvAdjustSheet(variantId: 'v1', currentStock: 20, productName: 'Dev Latte', controller: c),
              ),
            ),
          ),
          env,
        );
        expect(t.widget<AppButton>(find.byKey(const Key('invAdjustConfirm'))).onPressed, isNull);
        await t.tap(find.byIcon(Icons.remove_rounded));
        await t.pump();
        expect(c.delta.value, -1);
        expect(t.widget<TextField>(find.descendant(of: find.byKey(const Key('invAdjustDelta')), matching: find.byType(TextField))).controller!.text, '-1');
        await t.enterText(find.descendant(of: find.byKey(const Key('invAdjustDelta')), matching: find.byType(TextField)), '-7');
        await t.pump();
        expect(c.delta.value, -7);
        expect(find.text('Note (optional)'), findsOneWidget);
        await t.tap(find.byKey(const Key('invReason_other')));
        await t.pump();
        expect(find.text('Note (required)'), findsOneWidget);
        expect(find.byKey(const Key('invAdjustPreview')), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('invAdjustConfirm'))).onPressed, isNotNull);
        expect(t.takeException(), isNull);
      });

      testWidgets('adjust sheet: approval needed but not given shows the plain message', (t) async {
        when(
          () => repo.adjustInventory(
            any(),
            any(),
            delta: any(named: 'delta'),
            reason: any(named: 'reason'),
            note: any(named: 'note'),
            locationId: any(named: 'locationId'),
            approverToken: any(named: 'approverToken'),
          ),
        ).thenAnswer((_) async => (success: false, message: null, code: 'POS_APPROVAL_REQUIRED', data: null));
        final c = InvAdjustController(variantId: 'v1', currentStock: 20, repository: repo, storeId: 's1', approval: ({required reason, repository}) async => null);
        c.setDelta(-9);
        c.pickReason('correction');
        await pump(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: InvAdjustSheet(variantId: 'v1', currentStock: 20, controller: c),
            ),
          ),
          env,
        );
        await t.tap(find.byKey(const Key('invAdjustConfirm')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.byKey(const Key('invAdjustError')), findsOneWidget);
        expect(find.text('A manager must approve this change.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('movement history: type chips, rows with signed qty, cost only when present; a cashier gets "Managers only"', (t) async {
        when(
          () => repo.getInventoryMovements(
            any(),
            variantId: any(named: 'variantId'),
            type: any(named: 'type'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => InvPage(
            items: [
              movement(),
              movement(id: 'm2', type: 'return', qty: 1, manager: false),
            ],
            total: 2,
            page: 1,
            hasMore: false,
          ),
        );
        await pump(
          t,
          InvMovementsView(
            controller: Get.put(InvMovementsController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        expect(find.byKey(const Key('invType_sale')), findsOneWidget);
        expect(find.byKey(const Key('movement_m1')), findsOneWidget);
        expect(find.text('−2'), findsOneWidget);
        expect(find.text('+1'), findsOneWidget);
        expect(find.textContaining('Unit cost'), findsOneWidget); // only the row that had a cost
        Get.reset();
        when(
          () => repo.getInventoryMovements(
            any(),
            variantId: any(named: 'variantId'),
            type: any(named: 'type'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => null);
        when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
        await pump(
          t,
          InvMovementsView(
            controller: Get.put(InvMovementsController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        expect(find.text('Managers only'), findsOneWidget);
      });

      testWidgets('approval limits: label, value (money / number) and default', (t) async {
        when(() => repo.getInventoryLimits(any())).thenAnswer(
          (_) async => (
            exponent: 2,
            limits: [
              const InvLimit(key: 'q', label: 'Units a cashier may adjust', kind: 'qty', value: 5, defaultValue: 5),
              const InvLimit(key: 'm', label: 'Value a cashier may adjust', kind: 'minor', value: 5000, defaultValue: 2000),
            ],
          ),
        );
        await pump(
          t,
          InvLimitsView(
            controller: Get.put(InvLimitsController(repository: repo, storeId: 's1')),
          ),
          env,
        );
        expect(find.text('Units a cashier may adjust'), findsOneWidget);
        expect(find.text('\$50.00'), findsOneWidget);
        expect(find.text('Default \$20.00'), findsOneWidget);
        expect(find.text('Default 5'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      group('count screen', () {
        void stubOpen({InvCount? c}) {
          when(() => repo.listInventoryCounts(any())).thenAnswer((_) async => [c ?? count()]);
          when(() => repo.getInventoryCount(any(), any())).thenAnswer((_) async => c ?? count());
        }

        testWidgets('counting: progress, scan, manual field, lines, and Finish / Cancel for a manager', (t) async {
          stubOpen();
          await pump(
            t,
            InvCountView(
              controller: Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager')),
            ),
            env,
          );
          expect(find.text('1 of 3 counted'), findsOneWidget);
          for (final k in ['invScanButton', 'invCodeField', 'invFindButton', 'invFinishCount', 'invCancelCount']) {
            expect(find.byKey(Key(k)), findsOneWidget, reason: k);
          }
          await t.scrollUntilVisible(find.byKey(const Key('invCountLine_i3')), 100, scrollable: find.byType(Scrollable).first);
          expect(find.text('Not counted'), findsWidgets);
          expect(t.takeException(), isNull);
        });

        testWidgets('counting as a cashier: may count but has no Finish / Cancel', (t) async {
          stubOpen();
          await pump(
            t,
            InvCountView(
              controller: Get.put(InvCountController(repository: repo, storeId: 's1', role: 'cashier')),
            ),
            env,
          );
          expect(find.byKey(const Key('invScanButton')), findsOneWidget);
          expect(find.byKey(const Key('invFinishCount')), findsNothing);
          expect(find.byKey(const Key('invCancelCount')), findsNothing);
        });

        testWidgets('scan -> line with a pre-filled stepper -> save; an unknown code says "not on this count"', (t) async {
          stubOpen();
          when(() => repo.findInventoryCountItem(any(), any(), '1000000000011')).thenAnswer((_) async => (found: true, item: count().items[0]));
          when(() => repo.findInventoryCountItem(any(), any(), 'nope')).thenAnswer((_) async => (found: false, item: null));
          when(() => repo.enterInventoryCount(any(), any(), 'i1', 18)).thenAnswer((_) async => (success: true, message: null, code: null, count: count(item2Counted: true)));
          final c = Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager'));
          await pump(t, InvCountView(controller: c, scanner: () async => '1000000000011'), env);
          await t.tap(find.byKey(const Key('invScanButton')));
          await t.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('invCountEntry')), findsOneWidget);
          expect(c.qty.value, 18);
          await t.tap(find.byKey(const Key('invCountSave')));
          await t.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('invCountSaved')), findsOneWidget);
          expect(find.text('2 of 3 counted'), findsOneWidget);
          await t.enterText(find.descendant(of: find.byKey(const Key('invCodeField')), matching: find.byType(TextField)), 'nope');
          await t.tap(find.byKey(const Key('invFindButton')));
          await t.pump(const Duration(milliseconds: 300));
          expect(find.byKey(const Key('invNotOnCount')), findsOneWidget);
          expect(t.takeException(), isNull);
        });

        testWidgets('tap a line in the list to edit its count', (t) async {
          stubOpen();
          final c = Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager'));
          await pump(t, InvCountView(controller: c), env);
          await t.scrollUntilVisible(find.byKey(const Key('invCountLine_i1')), 100, scrollable: find.byType(Scrollable).first);
          await t.tap(find.byKey(const Key('invCountLine_i1')));
          await t.pump(const Duration(milliseconds: 300));
          expect(c.current.value!.id, 'i1');
          expect(c.qty.value, 18);
        });

        testWidgets('offline: "Needs internet" and no counting controls', (t) async {
          stubOpen();
          await pump(
            t,
            InvCountView(
              controller: Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager')),
              offline: true,
            ),
            env,
          );
          expect(find.text('Needs internet'), findsOneWidget);
          expect(find.byKey(const Key('invScanButton')), findsNothing);
        });

        testWidgets('no open count: a manager can start; a cashier is told to ask a manager', (t) async {
          when(() => repo.listInventoryCounts(any())).thenAnswer((_) async => []);
          await pump(
            t,
            InvCountView(
              controller: Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager')),
            ),
            env,
          );
          expect(find.byKey(const Key('invStartCount')), findsOneWidget);
          Get.reset();
          await pump(
            t,
            InvCountView(
              controller: Get.put(InvCountController(repository: repo, storeId: 's1', role: 'cashier')),
            ),
            env,
          );
          expect(find.byKey(const Key('invStartCount')), findsNothing);
          expect(find.text('Ask a manager to start a stock count.'), findsOneWidget);
        });

        testWidgets('variance review: differing lines (counted vs system), the uncounted warning, then Finish shows the result', (t) async {
          final cnt = count(item2Counted: true);
          stubOpen(c: cnt);
          when(() => repo.finishInventoryCount(any(), any())).thenAnswer((_) async => (success: true, message: null, code: null, result: const InvCountResult(applied: 1, skipped: [])));
          final c = Get.put(InvCountController(repository: repo, storeId: 's1', role: 'manager'));
          await pump(t, InvCountView(controller: c), env);
          await t.tap(find.byKey(const Key('invFinishCount')));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const Key('invVariance_i1')), findsOneWidget);
          expect(find.byKey(const Key('invVariance_i2')), findsNothing); // 8 = 8
          expect(find.text('System 20  →  Counted 18'), findsOneWidget);
          expect(find.textContaining('left as they are'), findsOneWidget);
          await t.tap(find.byKey(const Key('invVarianceConfirm')));
          await t.pump(const Duration(milliseconds: 400));
          await t.pump(const Duration(milliseconds: 400));
          expect(find.byKey(const Key('invCountResult')), findsOneWidget);
          expect(find.textContaining('1 item adjusted'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      });
    });
  }
}
