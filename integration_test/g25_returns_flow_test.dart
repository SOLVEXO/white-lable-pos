// REAL end-to-end for G2.5 / G2.6 on the iOS simulator against the dev stack (real repositories, real API, mock payment provider):
//   1 sale → partial return of 2 lines WITH restock → credit note (number, linked to the invoice) → its PDF renders and its public page opens
//   2 Raast sale → return → the money goes back through the provider (refund events)
//   3 a cashier's return within the store's limits works; above them a manager's PIN (the real sheet) is needed and is recorded on the credit note
//   4 a catalog price + barcode edit by a manager is visible on the storefront API
// Run:  (solvexo-api) DEV_REBUILD=1 E2E_QR_TTL=10 bash dev/up.sh && npm run dev:seed   then   tool/run_real_e2e.sh integration_test/g25_returns_flow_test.dart
// ignore_for_file: avoid_print
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart' hide Response;
import 'package:integration_test/integration_test.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';
import 'package:solvexo_pos/config/app_env.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;
  final plain = Dio(BaseOptions(validateStatus: (_) => true, connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 30)));

  Future<void> resetPolicy() async => owner.patch('/api/pos/settings/$storeId', {'cashierReturnsEnabled': false, 'returnApprovalAboveMinor': null, 'returnApprovalAfterDays': null});

  setUpAll(() async {
    SoundUtil.enabled = false;
    ReasonPicker.testOverride = (_) async => const PosReasonChoice('customer_changed_mind', 'e2e');
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId);
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    await t.setUpDevice(name: 'g25 stock probe');
    await t.pinLogin(managerEmail, managerPin);
    final v = await t.variantsBySku();
    for (final sku in ['DEV-LATTE', 'DEV-BEANS']) {
      await owner.topUp(storeId, v[sku]!.variantId, v[sku]!.stock, 100);
    }
    await t.closeAnyOpenShift();
    await t.dispose();
    await resetPolicy();
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till(String email, String pin) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(), DeviceSetupResult.ok);
    await t.pinLogin(email, pin);
    return t;
  }

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> app(WidgetTester tester) => tester.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: const Scaffold(body: SizedBox.shrink()))));

  testWidgets('1 sale → partial return of 2 lines with restock → credit note: number, linked invoice, PDF, public page', (tester) async {
    await app(tester);
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final latte = await t.line('DEV-LATTE', 3);
    final beans = await t.line('DEV-BEANS', 2);
    final stockLatte = await t.stockOf('DEV-LATTE');
    final stockBeans = await t.stockOf('DEV-BEANS');
    // 3 × 5.00 + 2 × 24.00 = 63.00 + 10% tax = 69.30
    final sold = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [latte, beans], clientTotal: 69.3, paymentMethod: 'cash', amountTendered: 80, status: 'completed');
    expect(sold.success, isTrue, reason: sold.message ?? '');
    final sale = sold.sale!;
    expect(sale.invoice?.number, startsWith('INV-'), reason: 'every completed sale has a tax-invoice number');
    expect(await t.stockOf('DEV-LATTE'), stockLatte - 3);

    final c = PosReturnController(repository: t.repo, saleId: sale.id);
    Get.put(c);
    await c.load();
    final latteLine = sale.items.firstWhere((i) => i.sku == 'DEV-LATTE');
    final beansLine = sale.items.firstWhere((i) => i.sku == 'DEV-BEANS');
    c.setQty(latteLine.saleItemId!, 1);
    c.setQty(beansLine.saleItemId!, 1);
    final estimate = c.estimateMinor!;
    expect(await c.confirm(), isTrue, reason: c.error.value ?? '');
    final number = c.result.value!['number'] as String;
    expect(number, startsWith('CN-'));
    expect(c.result.value!['totalMinor'], estimate, reason: 'the till\'s estimate equals what the server credited');
    expect(await t.stockOf('DEV-LATTE'), stockLatte - 2, reason: 'restocked');
    expect(await t.stockOf('DEV-BEANS'), stockBeans - 1, reason: 'restocked');

    final docs = (await t.repo.getSaleDocuments(sale.id))!;
    expect(docs.creditNotes.single.number, number);
    expect(docs.creditNotes.single.invoiceNumber, sale.invoice!.number);
    expect(docs.creditNotes.single.lines.map((l) => l.restock), [true, true]);
    expect(docs.creditNotes.single.totalMinor, estimate);
    final pdf = await TaxDocumentPdf.creditNote(note: docs.creditNotes.single);
    expect(pdf.length, greaterThan(800));
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

    // the customer's page for the credit note (public, behind the receipt link)
    final link = await t.repo.getReceiptLink(sale.id);
    final page = await plain.get('${AppEnv.apiBaseUrl}${Uri.parse(link!).path}/credit-note/$number');
    expect(page.statusCode, 200);
    expect(page.data as String, contains(number));
    expect(page.data as String, contains(sale.invoice!.number));
    final inv = await plain.get('${AppEnv.apiBaseUrl}${Uri.parse(link).path}/invoice');
    expect(inv.statusCode, 200);
    expect(inv.data as String, contains(number));
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  testWidgets('2 Raast sale → return → refunded through the payment provider (refund events), credit note names Raast', (tester) async {
    await app(tester);
    final t = await till(managerEmail, managerPin);
    final session = await t.openShift(openingCash: 100);
    final line = await t.line('DEV-LATTE', 2);
    final key = 'e2e-g25-qr-${DateTime.now().millisecondsSinceEpoch}';
    final qr = RaastQrController(amountMinor: 1100, sessionId: session.id, saleAttemptKey: key, storeId: storeId, repository: PosPaymentsRepository(), store: PendingQrStore.instance, pollInterval: const Duration(milliseconds: 700));
    Get.put<RaastQrController>(qr, tag: key);
    await eventually(() async => qr.phase.value == QrPhase.waiting, reason: 'QR shown');
    await qr.simulatePaid();
    final paid = await qr.result;
    expect(paid.isConfirmed, isTrue);
    final intentId = paid.intent!.id;
    final sold = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0, paymentMethod: 'raast_qr', payments: [{'method': 'raast_qr', 'amount': 11.0, 'intentId': intentId}], idempotencyKey: key, status: 'completed');
    expect(sold.success, isTrue, reason: sold.message ?? '');
    await PendingQrStore.instance.clear();

    final c = PosReturnController(repository: t.repo, saleId: sold.sale!.id);
    Get.put(c);
    await c.load();
    c.setQty(sold.sale!.items.first.saleItemId!, 1);
    expect(await c.confirm(), isTrue, reason: c.error.value ?? '');
    final intent = ((await owner.get('/api/pos/payments/intents/$intentId?storeId=$storeId')).data['data'] as Map).cast<String, dynamic>();
    await eventually(() async => (((await owner.get('/api/pos/payments/intents/$intentId?storeId=$storeId')).data['data'] as Map)['refundedMinor'] ?? 0) == 550, reason: 'provider refund of half');
    print('raast intent after partial return: ${intent['refundStatus']} refunded ${intent['refundedMinor']}');
    final note = (await t.repo.getSaleDocuments(sold.sale!.id))!.creditNotes.single;
    expect(note.tenders.single.method, 'raast_qr');
    expect(note.tenders.single.amountMinor, 550);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  testWidgets('3 cashier return: within the store\'s limits it works; above them a manager\'s PIN (the real sheet) is needed and is recorded', (tester) async {
    await app(tester);
    final patched = await owner.patch('/api/pos/settings/$storeId', {'cashierReturnsEnabled': true, 'returnApprovalAboveMinor': 600, 'returnApprovalAfterDays': 7});
    expect(patched.statusCode, anyOf(200, 201), reason: '${patched.data}');
    try {
      final t = await till(cashierEmail, cashierPin);
      final session = await t.openShift(openingCash: 50);
      final one = await t.line('DEV-LATTE', 1);
      final two = await t.line('DEV-LATTE', 2);
      final small = (await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [one], clientTotal: 5.5, paymentMethod: 'card', status: 'completed')).sale!;
      final big = (await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [two], clientTotal: 11.0, paymentMethod: 'card', status: 'completed')).sale!;

      // within the limits (5.50 ≤ 6.00, today, receipt shown): the cashier does it alone
      final c1 = PosReturnController(repository: t.repo, saleId: small.id);
      Get.put(c1, tag: 'small');
      await c1.load();
      expect(await c1.confirm(all: true), isTrue, reason: c1.error.value ?? '');
      final n1 = (await t.repo.getSaleDocuments(small.id))!.creditNotes.single;
      expect([n1.approvedBy, n1.approvalReasons], [null, <String>[]]);

      // above the limit: the sheet asks for a manager; their PIN is used for THIS return
      final c2 = PosReturnController(repository: t.repo, saleId: big.id);
      Get.put(c2, tag: 'big');
      await c2.load();
      final done = c2.confirm(all: true);
      await pumpFor(tester, const Duration(seconds: 3));
      expect(find.byKey(const Key('approverEmail')), findsOneWidget, reason: 'manager approval sheet');
      expect(find.textContaining('above the limit'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('approverEmail')), managerEmail);
      for (final d in managerPin.split('')) {
        await tester.tap(find.text(d).last);
        await tester.pump();
      }
      await pumpFor(tester, const Duration(seconds: 3));
      expect(await done, isTrue, reason: c2.error.value ?? '');
      final n2 = (await t.repo.getSaleDocuments(big.id))!.creditNotes.single;
      expect(n2.approvedBy, isNotNull);
      expect(n2.approvalReasons, contains('amount_above_limit'));
      await t.closeAnyOpenShift();
      await t.dispose();
    } finally {
      await resetPolicy();
    }
  });

  testWidgets('4 a manager\'s catalog edit (price + barcode) is visible on the storefront API; a clash is refused; stock moves as a movement', (tester) async {
    await app(tester);
    final t = await till(managerEmail, managerPin);
    final v = (await t.variantsBySku())['DEV-LATTE']!;
    final newPrice = 5.25;
    final barcode = '9${DateTime.now().millisecondsSinceEpoch % 1000000000000}';
    try {
      final r = await t.repo.updateCatalogVariant(storeId, v.variantId, {'price': newPrice, 'barcode': barcode, 'hsCode': '09024090'});
      expect(r.success, isTrue, reason: r.message ?? '');
      final storefront = await plain.get('${AppEnv.apiBaseUrl}/api/products/getVariantById/${v.variantId}');
      expect(storefront.statusCode, 200, reason: '${storefront.data}');
      final data = ((storefront.data as Map)['data'] ?? storefront.data) as Map;
      expect(data['price'], newPrice);
      expect(data['barcode'], barcode);
      // the same barcode on another item of this store is refused
      final other = (await t.variantsBySku())['DEV-BEANS']!;
      final clash = await t.repo.updateCatalogVariant(storeId, other.variantId, {'barcode': barcode});
      expect(clash.success, isFalse);
      expect(clash.code, 'BARCODE_IN_USE');
      // a price with more decimals than the currency allows is refused
      final precision = await t.repo.updateCatalogVariant(storeId, v.variantId, {'price': 5.123});
      expect(precision.code, 'PRICE_PRECISION');
      // stock: a movement
      final before = await t.stockOf('DEV-LATTE');
      final s = await t.repo.adjustCatalogStock(storeId, v.variantId, delta: 3, reason: 'correction', note: 'e2e count');
      expect(s.success, isTrue, reason: s.message ?? '');
      expect(await t.stockOf('DEV-LATTE'), before + 3);
      // a cashier cannot (manager PIN required)
      await t.dispose();
      final cashier = await till(cashierEmail, cashierPin);
      final denied = await cashier.repo.updateCatalogVariant(storeId, v.variantId, {'price': 9});
      expect(denied.success, isFalse);
      await cashier.dispose();
    } finally {
      final back = await till(managerEmail, managerPin);
      await back.repo.updateCatalogVariant(storeId, v.variantId, {'price': 5, 'barcode': '1000000000011', 'hsCode': null});
      await back.dispose();
    }
  });
}
