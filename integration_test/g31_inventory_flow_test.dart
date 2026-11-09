// REAL end-to-end for G3.1 Inventory on the iOS simulator against the dev stack (real repositories, real API, the real manager-approval sheet):
//   manager sells 2 DEV-LATTE → overview / stock list / detail show the lower stock → movement history has the sale row (type sale, qty −2)
//   cashier adjusts −2 (allowed, no approval) → cashier adjusts −9 → the server asks for approval → the REAL ManagerApproval sheet → success → movements show both
//   manager starts a count, finds DEV-LATTE by barcode, enters a count, reviews the variance and finishes → stock equals the counted number
//   a cashier cannot start a count (error) and gets 403 on the movement history, and sees no cost / value
// Run:  (solvexo-api) npm run dev:stack:up && npm run dev:seed   then   SIM_DEVICE=<udid> tool/run_real_e2e.sh integration_test/g31_inventory_flow_test.dart
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_adjust_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_count_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_movements_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_detail_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_overview_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_stock_list_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

const _latteBarcode = '1000000000011'; // solvexo-api/dev/seed.ts

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    SoundUtil.enabled = false;
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'g31 inventory probe'), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> app(WidgetTester tester, [Widget? home]) => tester.pumpWidget(
    ResponsiveSizer(
      builder: (_, __, ___) => GetMaterialApp(
        theme: AppTheme.light,
        home: home ?? const Scaffold(body: SizedBox.shrink()),
      ),
    ),
  );

  testWidgets('G3.1 inventory: sale → stock + ledger → cashier adjust (limit + real approval) → count by scan → finish; role limits', (tester) async {
    await app(tester);
    var t = await till(managerEmail, managerPin);
    final latteVariantId = (await t.variantsBySku())['DEV-LATTE']!.variantId;
    await owner.topUp(storeId, latteVariantId, await t.stockOf('DEV-LATTE'), 100);
    // a count left open by an earlier run would block starting one
    final stale = await t.repo.listInventoryCounts(storeId);
    for (final c in stale ?? <InvCount>[]) {
      if (c.isOpen) await t.repo.cancelInventoryCount(storeId, c.id);
    }

    // ── 1. manager sells 2 DEV-LATTE ──
    final session = await t.openShift(openingCash: 100);
    final before = await t.stockOf('DEV-LATTE');
    final sold = await t.repo.createSale(
      storeId: storeId,
      sessionId: session.id,
      registerId: registerId,
      employeeId: t.employee!.id,
      items: [await t.line('DEV-LATTE', 2)],
      clientTotal: 11.0,
      paymentMethod: 'cash',
      amountTendered: 20,
      status: 'completed',
    );
    expect(sold.success, isTrue, reason: sold.message ?? '');

    // ── 2. overview / stock / detail through the real screens ──
    final ov = Get.put(InvOverviewController(repository: t.repo, storeId: storeId));
    await app(tester, InvOverviewView(controller: ov));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(ov.overview.value, isNotNull, reason: ov.error.value ?? '');
    expect(ov.role, 'manager');
    expect(ov.overview.value!.stockValueMinor, isNotNull);
    expect(find.byKey(const Key('invTileValue')), findsOneWidget);
    expect(tester.takeException(), isNull);
    print('overview: ${ov.overview.value!.skuCount} SKUs, low ${ov.overview.value!.lowStockCount}, out ${ov.overview.value!.outOfStockCount}, value minor ${ov.overview.value!.stockValueMinor}');

    final list = Get.put(
      InvStockListController(repository: t.repo, storeId: storeId),
      tag: 'e2e',
    );
    await app(tester, InvStockListView(controller: list));
    await pumpFor(tester, const Duration(seconds: 2));
    list.query = 'DEV-LATTE';
    await list.reload();
    await pumpFor(tester, const Duration(seconds: 1));
    final latteRow = list.items.firstWhere((r) => r.sku == 'DEV-LATTE');
    expect(latteRow.stock, before - 2, reason: 'stock list shows the lower stock');
    // (the dev seed records no cost, so the cost fields are legitimately absent; the manager-only overview fields are the role proof)
    expect(ov.overview.value!.variantsWithoutCost, isNotNull, reason: 'manager-only overview field');
    expect(find.byKey(Key('invRow_${latteRow.variantId}')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final dc = Get.put(
      InvDetailController(variantId: latteRow.variantId, repository: t.repo, storeId: storeId),
      tag: 'e2e',
    );
    await app(tester, InvDetailView(variantId: latteRow.variantId, controller: dc));
    await pumpFor(tester, const Duration(seconds: 3));
    expect(dc.detail.value, isNotNull, reason: dc.error.value ?? '');
    expect(dc.detail.value!.row.stock, before - 2);
    expect(find.byKey(const Key('invDetailStock')), findsOneWidget);
    expect(dc.detail.value!.recentMovements.any((m) => m.type == 'sale' && m.qtyDelta == -2), isTrue, reason: 'recent movements carry the sale');
    expect(tester.takeException(), isNull);

    // ── 3. movements: the sale row ──
    final mv = InvMovementsController(repository: t.repo, storeId: storeId, variantId: latteRow.variantId);
    await mv.reload();
    final saleRow = mv.items.firstWhere((m) => m.type == 'sale');
    expect(saleRow.qtyDelta, -2);
    expect(saleRow.typeLabel, 'Sale');
    print('movements: ${mv.items.map((m) => '${m.type}:${m.qtyDelta}').join(', ')}');
    await t.closeAnyOpenShift();
    await t.dispose();

    // ── 4. cashier: adjust −2 allowed, −9 needs approval (the real sheet) ──
    t = await till(cashierEmail, cashierPin);
    await app(tester); // after Till.boot (it resets GetX), so the sheet has a navigator
    final afterSale = await t.stockOf('DEV-LATTE');
    final a1 = InvAdjustController(variantId: latteVariantId, currentStock: afterSale, repository: t.repo, storeId: storeId);
    a1.setDelta(-2);
    a1.pickReason('correction');
    expect(await a1.submit(), isTrue, reason: a1.error.value ?? '');
    expect(await t.stockOf('DEV-LATTE'), afterSale - 2);

    final a2 = InvAdjustController(variantId: latteVariantId, currentStock: afterSale - 2, repository: t.repo, storeId: storeId);
    a2.setDelta(-9);
    a2.pickReason('correction');
    final done = a2.submit();
    await pumpFor(tester, const Duration(seconds: 3));
    expect(find.byKey(const Key('approverEmail')), findsOneWidget, reason: 'the server asked for a manager: the approval sheet is up');
    await tester.enterText(find.byKey(const Key('approverEmail')), managerEmail);
    for (final d in managerPin.split('')) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await pumpFor(tester, const Duration(seconds: 3));
    expect(await done, isTrue, reason: a2.error.value ?? '');
    expect(await t.stockOf('DEV-LATTE'), afterSale - 11);

    // role limits for the cashier
    final cashierOv = InvOverviewController(repository: t.repo, storeId: storeId);
    await cashierOv.load();
    expect(cashierOv.role, 'cashier');
    expect(cashierOv.overview.value!.stockValueMinor, isNull, reason: 'no value for a cashier');
    final cashierList = InvStockListController(repository: t.repo, storeId: storeId);
    await cashierList.reload();
    expect(cashierList.items.every((r) => r.costMinor == null && r.valueMinor == null), isTrue, reason: 'no cost for a cashier');
    final cashierMoves = InvMovementsController(repository: t.repo, storeId: storeId);
    await cashierMoves.reload();
    expect(cashierMoves.forbidden.value, isTrue, reason: '403 POS_ACTION_FORBIDDEN on the history');
    expect(t.repo.lastErrorCode, 'POS_ACTION_FORBIDDEN');
    // the till hides Start for a cashier; this asks the server anyway: it refuses
    final started = await t.repo.startInventoryCount(storeId);
    expect(started.success, isFalse);
    expect(started.code, 'POS_ACTION_FORBIDDEN');
    await t.dispose();

    // ── 5. manager: history shows both adjustments; count by scan; finish ──
    t = await till(managerEmail, managerPin);
    final mv2 = InvMovementsController(repository: t.repo, storeId: storeId, variantId: latteVariantId);
    await mv2.reload();
    final adj = mv2.items.where((m) => m.type == 'adjustment').map((m) => m.qtyDelta).toList();
    expect(adj, containsAll([-2, -9]));

    final cc = Get.put(InvCountController(repository: t.repo, storeId: storeId)); // onInit: role guess from the PIN session + load
    await eventually(() async => !cc.loading.value, reason: 'count screen loaded');
    expect(cc.role.value, 'manager');
    expect(await cc.start(), isTrue, reason: cc.error.value ?? '');
    expect(cc.count.value!.items.isNotEmpty, isTrue);
    expect(await cc.find(_latteBarcode), isTrue, reason: 'DEV-LATTE found by its barcode');
    final line = cc.current.value!;
    expect(line.sku, 'DEV-LATTE');
    final counted = line.systemQty - 4;
    cc.setQty(counted);
    expect(await cc.saveCurrent(), isTrue, reason: cc.error.value ?? '');
    expect(cc.count.value!.variances.map((v) => v.sku), ['DEV-LATTE']);
    expect(await cc.find('0000-not-on-this-count'), isFalse);
    expect(cc.notOnCount.value, isTrue);
    expect(await cc.finish(), isTrue, reason: cc.error.value ?? '');
    expect(cc.result.value!.applied, 1);
    expect(await t.stockOf('DEV-LATTE'), counted, reason: 'stock equals the counted number');
    final mv3 = InvMovementsController(repository: t.repo, storeId: storeId, variantId: latteVariantId);
    await mv3.reload();
    print('ledger after count: ${mv3.items.map((m) => '${m.type}:${m.qtyDelta}:${m.note ?? m.reason}').join(' | ')}');
    // NOTE (backend, reported): the count variance is written as movement type 'adjustment' (reason correction, note 'Stock count #…'), never 'count'.
    expect(mv3.items.any((m) => (m.note ?? '').startsWith('Stock count #') && m.qtyDelta == -4), isTrue, reason: 'the count variance is in the ledger');
    print('count finished: ${cc.result.value!.applied} applied, skipped ${cc.result.value!.skipped}');

    // limits (manager, read-only)
    final lim = await t.repo.getInventoryLimits(storeId);
    expect(lim, isNotNull);
    expect(lim!.limits, isNotEmpty);
    print('limits: ${lim.limits.map((l) => '${l.key}=${l.value}').join(', ')}');

    // ── cleanup: no open shift, stock restored ──
    await t.closeAnyOpenShift();
    await owner.topUp(storeId, latteVariantId, await t.stockOf('DEV-LATTE'), 100);
    await t.dispose();
  });
}
