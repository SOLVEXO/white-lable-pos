// Screenshot pass for the G3.1 inventory screens on the iOS simulator (real rendering, real fonts), light AND dark in one run.
//   SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g31_screens_shots_test.dart <outdir> <suffix>
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
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

import '../test/support/inventory_fixtures.dart';
import '../test/support/sale_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 16; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    final theme = dark ? AppTheme.dark : AppTheme.light;
    Future<void> show(WidgetTester t, Widget w) async {
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: w,
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 600));
    }

    MockPosRepository fresh() {
      Get.reset();
      final repo = MockPosRepository();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.lastErrorReasons).thenReturn(const []);
      return repo;
    }

    testWidgets('overview + list + limits ($tn)', (t) async {
      var repo = fresh();
      when(
        () => repo.getInventoryOverview(any()),
      ).thenAnswer((_) async => overview(openCount: true));
      await show(
        t,
        InvOverviewView(
          controller: Get.put(
            InvOverviewController(repository: repo, storeId: 's1'),
          ),
        ),
      );
      await shot(t, 'g31_01_overview_manager', tn);

      repo = fresh();
      when(
        () => repo.getInventoryOverview(any()),
      ).thenAnswer((_) async => overview(role: 'cashier', openCount: true));
      await show(
        t,
        InvOverviewView(
          controller: Get.put(
            InvOverviewController(repository: repo, storeId: 's1'),
          ),
        ),
      );
      await shot(t, 'g31_02_overview_cashier', tn);

      repo = fresh();
      when(
        () => repo.getInventoryStock(
          any(),
          search: any(named: 'search'),
          filter: any(named: 'filter'),
          page: any(named: 'page'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer(
        (_) async => rowsPage([
          row(id: 'a', name: 'Dev Latte (limited stock)', stock: 18),
          row(id: 'b', name: 'Dev Croissant (low stock)', stock: 2, low: true),
          row(id: 'c', name: 'Dev Beans 1kg', stock: 0, out: true),
          row(id: 'd', name: 'Dev Refill (unlimited)', unlimited: true),
          row(id: 'e', name: 'Oat milk', stock: 40),
        ]),
      );
      await show(
        t,
        InvStockListView(
          controller: Get.put(
            InvStockListController(repository: repo, storeId: 's1'),
            tag: 'shot',
          ),
        ),
      );
      await shot(t, 'g31_03_stock_list', tn);

      repo = fresh();
      when(() => repo.getInventoryLimits(any())).thenAnswer(
        (_) async => (
          cur: const InvCur('USD', 2),
          limits: [
            const InvLimit(
              key: 'stockAdjustQty',
              label: 'Stock change a cashier may make (units)',
              kind: 'qty',
              value: 5,
              defaultValue: 5,
            ),
            const InvLimit(
              key: 'stockAdjustValueMinor',
              label: 'Stock change a cashier may make (value)',
              kind: 'minor',
              value: 2000,
              defaultValue: 2000,
            ),
            const InvLimit(
              key: 'cashOutMinor',
              label: 'Cash out above',
              kind: 'minor',
              value: 10000,
              defaultValue: 10000,
            ),
          ],
        ),
      );
      await show(
        t,
        InvLimitsView(
          controller: Get.put(
            InvLimitsController(repository: repo, storeId: 's1'),
          ),
        ),
      );
      await shot(t, 'g31_10_approval_limits', tn);
    });

    testWidgets('detail + adjust + approval ($tn)', (t) async {
      final repo = fresh();
      when(
        () => repo.getInventoryVariant(any(), any()),
      ).thenAnswer((_) async => detail(ledger: DateTime.utc(2026, 11, 1)));
      final dc = Get.put(
        InvDetailController(
          variantId: 'v1',
          repository: repo,
          storeId: 's1',
          role: 'manager',
        ),
        tag: 'v1',
      );
      await show(
        t,
        InvDetailView(
          variantId: 'v1',
          controller: dc,
          now: DateTime(2026, 11, 9),
        ),
      );
      await shot(t, 'g31_04_item_detail', tn);
      await t.drag(
        find.byKey(const Key('invDetailList')),
        const Offset(0, -700),
      );
      await shot(t, 'g31_05_item_lots_movements', tn);
      await t.drag(
        find.byKey(const Key('invDetailList')),
        const Offset(0, 1400),
      );
      await t.pump(const Duration(milliseconds: 300));

      final adj = InvAdjustController(
        variantId: 'v1',
        currentStock: 20,
        repository: repo,
        storeId: 's1',
        approval: ({required reason, repository}) async => null,
      );
      adj.setDelta(-3);
      adj.pickReason('correction');
      AppBottomSheet.showGet<bool>(
        InvAdjustSheet(
          variantId: 'v1',
          currentStock: 20,
          productName: 'Dev Latte',
          controller: adj,
        ),
        title: 'Adjust stock',
      );
      await t.pump(const Duration(milliseconds: 700));
      await shot(t, 'g31_06_adjust_sheet', tn);

      // the server wants a manager: above the cashier's limit
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
      ).thenAnswer(
        (_) async => (
          success: false,
          message: null,
          code: 'POS_APPROVAL_REQUIRED',
          data: null,
        ),
      );
      adj.setDelta(-9);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('invAdjustConfirm')));
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, 'g31_07_adjust_approval_needed', tn);
      Get.back<void>();
      await t.pump(const Duration(milliseconds: 500));

      // …and the real approval sheet that the till raises for it
      ManagerApproval.request(
        reason: 'This stock change needs a manager\'s approval.',
        repository: repo,
      );
      await t.pump(const Duration(milliseconds: 700));
      await shot(t, 'g31_08_manager_approval_sheet', tn);
    });

    testWidgets('count + variance + movements ($tn)', (t) async {
      var repo = fresh();
      when(
        () => repo.listInventoryCounts(any()),
      ).thenAnswer((_) async => [count(item2Counted: true)]);
      when(
        () => repo.getInventoryCount(any(), any()),
      ).thenAnswer((_) async => count(item2Counted: true));
      when(() => repo.findInventoryCountItem(any(), any(), any())).thenAnswer(
        (_) async => (found: true, item: count(item2Counted: true).items[2]),
      );
      final cc = Get.put(
        InvCountController(repository: repo, storeId: 's1', role: 'manager'),
      );
      await show(t, InvCountView(controller: cc));
      await shot(t, 'g31_09_count_progress', tn);
      await cc.find('1000000000035');
      cc.setQty(1);
      await shot(t, 'g31_09b_count_entry', tn);
      cc.clearCurrent();
      AppBottomSheet.showGet<bool>(
        InvVarianceReview(count: count(item2Counted: true)),
        title: 'Review before finishing',
        scrollable: false,
      );
      await t.pump(const Duration(milliseconds: 700));
      await shot(t, 'g31_09c_variance_review', tn);

      repo = fresh();
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
          cur: const InvCur('USD', 2),
          items: [
            movement(id: 'm1'),
            movement(
              id: 'm2',
              type: 'adjustment',
              qty: 0,
              damaged: 1,
              reason: 'damaged',
              note: 'dropped a tray',
            ),
            movement(id: 'm3', type: 'return', qty: 1),
            movement(
              id: 'm4',
              type: 'adjustment',
              qty: -4,
              reason: 'correction',
              note: 'Stock count #A1B2C3',
            ),
            movement(id: 'm5', type: 'receive', qty: 24),
          ],
          total: 5,
          page: 1,
          hasMore: false,
        ),
      );
      await show(
        t,
        InvMovementsView(
          controller: Get.put(
            InvMovementsController(repository: repo, storeId: 's1'),
          ),
        ),
      );
      await shot(t, 'g31_11_movement_history', tn);
    });
  }
}
