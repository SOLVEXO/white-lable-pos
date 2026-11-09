// REAL end-to-end for G2.7 on the iOS simulator against the dev stack:
//   till A (register 1) rings a cash sale while the API is DOWN → queued with its OFF- receipt number → API back → synced
//   till B (a SECOND register / device) finds that sale by the OFF- number printed on the receipt (Orders search, store-wide) and returns it
//   → a credit note is issued against the synced invoice and the sale keeps its OFF- number as a lookup reference.
// Run:  (solvexo-api) DEV_REBUILD=1 E2E_QR_TTL=10 bash dev/up.sh && npm run dev:seed   then   tool/run_real_e2e.sh integration_test/g27_offline_return_other_till_test.dart
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, register1, register2;

  setUpAll(() async {
    SoundUtil.enabled = false;
    ReasonPicker.testOverride = (_) async => const PosReasonChoice('customer_changed_mind', 'e2e second till');
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    register1 = s.registerId;
    // a second register (idempotent by name)
    Future<List<Map>> registers() async {
      final r = await owner.get('/api/store/my-stores');
      final store = (r.data['data'] as List).cast<Map>().firstWhere((e) => e['_id'] == storeId);
      return (store['registers'] as List).cast<Map>();
    }

    var regs = await registers();
    if (!regs.any((r) => r['name'] == 'G27 second till')) {
      final add = await owner.post('/api/pos/registers/$storeId', {'name': 'G27 second till', 'defaultFloatCash': 50});
      expect(add.statusCode, anyOf(200, 201), reason: '${add.data}');
      regs = await registers();
    }
    register2 = regs.firstWhere((r) => r['name'] == 'G27 second till')['_id'] as String;
    expect(register2, isNot(register1));
    await owner.revokeAllDevices(storeId);
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<void> app(WidgetTester tester) => tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));

  testWidgets('a sale rung up offline on till A is found by its OFF- receipt number on till B and returned there', (tester) async {
    // ── till A: offline sale ──
    final a = await Till.boot(storeId: storeId, registerId: register1);
    expect(await a.setUpDevice(name: 'g27 till A'), DeviceSetupResult.ok);
    await a.pinLogin(managerEmail, managerPin);
    await a.closeAnyOpenShift();
    final sessionA = await a.openShift(openingCash: 100);
    final line = await a.line('DEV-LATTE', 1);
    final key = 'e2e-g27-off-${DateTime.now().millisecondsSinceEpoch}';
    await Control.stopApi();
    try {
      final q = await a.repo.createSale(storeId: storeId, sessionId: sessionA.id, registerId: register1, employeeId: a.employee!.id, items: [line], clientCreatedAt: DateTime.now(), paymentMethod: 'cash', amountTendered: 10, status: 'completed', idempotencyKey: key);
      expect(q.queued, isTrue, reason: 'API down → queued on the device');
    } finally {
      await Control.startApi();
    }
    final off = await a.sync.provisionalNumberFor(key);
    expect(off, startsWith('OFF-'), reason: 'the number printed on the customer\'s first receipt');
    await a.sync.syncNow(ignoreBackoff: true);
    await eventually(() async => a.sync.unresolvedCount.value == 0, reason: 'queue drained');
    await a.closeAnyOpenShift();
    await a.dispose();
    await owner.revokeAllDevices(storeId);

    // ── till B: another register, another device ──
    final b = await Till.boot(storeId: storeId, registerId: register2);
    expect(await b.setUpDevice(name: 'g27 till B'), DeviceSetupResult.ok);
    await b.pinLogin(managerEmail, managerPin);
    await app(tester); // after Till.boot (it resets GetX)
    await b.closeAnyOpenShift();
    final sessionB = await b.openShift(openingCash: 50);

    final orders = PosOrdersController(posRepository: b.repo);
    Get.put(orders);
    await orders.searchByReceipt(off!);
    expect(orders.sales, hasLength(1), reason: 'found by the OFF- number, store-wide');
    final found = orders.sales.single;
    expect(found.registerId, register1, reason: 'it was sold on the OTHER till');
    expect(found.sessionId, isNot(sessionB.id));
    expect(found.invoice?.number, startsWith('INV-'));
    // the lowercase / spaced version a cashier types still finds it
    await orders.searchByReceipt('  ${off.toLowerCase()} ');
    expect(orders.sales.single.id, found.id);
    // and the invoice number works too
    await orders.searchByReceipt(found.invoice!.number);
    expect(orders.sales.single.id, found.id);

    final c = PosReturnController(repository: b.repo, saleId: found.id);
    Get.put(c);
    await c.load();
    expect(await c.confirm(all: true), isTrue, reason: c.error.value ?? '');
    final docs = (await b.repo.getSaleDocuments(found.id))!;
    expect(docs.creditNotes.single.invoiceNumber, found.invoice!.number);
    expect(docs.creditNotes.single.number, startsWith('CN-'));
    print('returned $off at till B → ${docs.creditNotes.single.number} against ${found.invoice!.number}');

    await b.closeAnyOpenShift();
    await b.dispose();
  });
}
