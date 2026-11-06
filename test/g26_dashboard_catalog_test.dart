// G2.6 on the till: the Home business pulse (role-based, from the server), POS catalog edits (manager approval, server errors, stock as a
// movement), the owner's store tax profile, KYB documents as PDF.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_dashboard_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/modules/pos/views/dashboard_pulse.dart';
import 'package:solvexo_pos/app/modules/pos_catalog/controllers/pos_catalog_controller.dart';
import 'package:solvexo_pos/app/modules/pos_catalog/views/pos_catalog_view.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';
import 'package:solvexo_pos/app/modules/pos_tax_profile/pos_tax_profile.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'g24_screens_test.dart' show FakeKyb;
import 'support/sale_harness.dart';

MockCategoryRepository _noCats() {
  final c = MockCategoryRepository();
  when(() => c.getCategories()).thenAnswer((_) async => null);
  return c;
}

Map<String, dynamic> dash({String role = 'manager', bool shift = false, bool attention = true}) => {
      'role': role,
      'scope': shift ? 'shift' : 'store',
      'currency': 'USD',
      'currencyExponent': 2,
      'summary': {'totalRevenue': 120.5, 'netRevenue': 110.5, 'totalTransactions': 9, 'avgTransactionValue': 13.39, 'refundsTotal': 10.0, 'refundsCount': 1},
      'byPaymentMethod': {
        'cash': {'count': 5, 'total': 60.0},
        'card': {'count': 3, 'total': 50.5},
        'other': {'count': 0, 'total': 0},
        'raast_qr': {'count': 1, 'total': 10.0},
      },
      'topProducts': [
        {'productId': 'p1', 'name': 'Latte', 'qty': 12, 'revenue': 60.0},
        {'productId': 'custom', 'name': 'Custom item', 'qty': 2, 'revenue': 20.0},
      ],
      'lowStock': shift ? null : {'count': 2, 'items': [{'name': 'Beans', 'stock': 2}, {'name': 'Milk', 'stock': 6}]},
      'shifts': [
        {'sessionId': 's1', 'employeeName': 'Cal Cashier', 'openedAt': '2026-11-06T08:00:00.000Z', 'totalSales': 110.5, 'totalTransactions': 9}
      ],
      'needsAttention': shift || !attention ? null : {'salesNeedingReview': 1, 'digitalPayments': 2, 'total': 3},
    };

PosEmployeeModel manager() => PosEmployeeModel(id: 'm1', storeId: 'store-1', sellerId: 's', name: 'Mia', email: 'mia@x.pk', role: 'manager', shiftIds: const [], status: 'active', createdAt: DateTime(2026));

void main() {
  SaleHarness.setUpAllShared();
  setUp(() => SharedPreferences.setMockInitialValues({'store_id': 'store-1'}));
  tearDown(Get.reset);

  Future<void> pump(WidgetTester t, Widget w, {Size size = const Size(390, 1400), ThemeData? theme}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(theme: theme ?? AppTheme.light, home: w)));
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  group('Home dashboard', () {
    test('the model reads the server\'s answer: summary, tender mix (empty tenders dropped), top products, low stock, attention, shifts', () {
      final d = PosDashboard.fromJson(dash());
      expect([d.role, d.isShiftScope, d.orders, d.netRevenue, d.average, d.refunds], ['manager', false, 9, 110.5, 13.39, 10.0]);
      expect(d.paymentMix.map((e) => e.method), ['cash', 'card', 'raast_qr']);
      expect(d.topProducts.first.name, 'Latte');
      expect([d.lowStockCount, d.lowStock.length, d.attentionTotal, d.showsAttention], [2, 2, 3, true]);
      expect(d.shifts.single.employeeName, 'Cal Cashier');
    });

    testWidgets('a manager sees the store pulse: tiles, attention, top products, payment mix, low stock, shift', (t) async {
      var attention = 0;
      await pump(t, Scaffold(body: SingleChildScrollView(child: DashboardPulse(d: PosDashboard.fromJson(dash()), onAttention: () => attention++))));
      expect(find.text('Today'), findsOneWidget);
      for (final k in ['pulseSales', 'pulseOrders', 'pulseAverage', 'pulseRefunds']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(t.widget<Text>(find.byKey(const Key('pulseOrders'))).data, '9');
      expect(find.byKey(const Key('pulseAttention')), findsOneWidget);
      expect(find.text('3 items need attention'), findsOneWidget);
      await t.tap(find.byKey(const Key('pulseAttention')));
      expect(attention, 1);
      expect(find.byKey(const Key('pulseTop')), findsOneWidget);
      expect(find.text('Latte'), findsOneWidget);
      expect(find.byKey(const Key('pulseMix')), findsOneWidget);
      expect(find.text('Raast'), findsOneWidget);
      expect(find.byKey(const Key('pulseLowStock')), findsOneWidget);
      expect(find.text('2 left'), findsOneWidget);
      expect(find.byKey(const Key('pulseShift')), findsOneWidget);
      expect(find.textContaining('Cal Cashier'), findsOneWidget);
    });

    testWidgets('a cashier gets "Your shift so far" and NOTHING store-wide (no attention, no low stock)', (t) async {
      await pump(t, Scaffold(body: SingleChildScrollView(child: DashboardPulse(d: PosDashboard.fromJson(dash(role: 'cashier', shift: true))))));
      expect(find.text('Your shift so far'), findsOneWidget);
      expect(find.byKey(const Key('pulseAttention')), findsNothing);
      expect(find.byKey(const Key('pulseLowStock')), findsNothing);
      expect(find.byKey(const Key('pulseShift')), findsOneWidget);
    });

    testWidgets('an empty day and no open shift: zeros and "No shift is open"; nothing needs attention shows no banner', (t) async {
      final j = dash(attention: false)
        ..['summary'] = {'totalRevenue': 0, 'netRevenue': 0, 'totalTransactions': 0, 'avgTransactionValue': 0, 'refundsTotal': 0, 'refundsCount': 0}
        ..['byPaymentMethod'] = <String, dynamic>{}
        ..['topProducts'] = <dynamic>[]
        ..['shifts'] = <dynamic>[]
        ..['lowStock'] = null;
      await pump(t, Scaffold(body: SingleChildScrollView(child: DashboardPulse(d: PosDashboard.fromJson(j)))));
      expect(t.widget<Text>(find.byKey(const Key('pulseOrders'))).data, '0');
      expect(find.byKey(const Key('pulseNoShift')), findsOneWidget);
      expect(find.byKey(const Key('pulseAttention')), findsNothing);
      expect(find.byKey(const Key('pulseTop')), findsNothing);
    });

    testWidgets('tablet + dark render', (t) async {
      await pump(t, Scaffold(body: SingleChildScrollView(child: DashboardPulse(d: PosDashboard.fromJson(dash())))), size: const Size(1100, 1000), theme: AppTheme.dark);
      expect(find.byKey(const Key('dashboardPulse')), findsOneWidget);
    });
  });

  group('POS catalog edit', () {
    late MockPosRepository repo;
    const variant = PosProductVariant(variantId: 'v1', sku: 'TEA-1', barcode: '111', hsCode: '09024090', price: 10, stock: 8, isDefault: true);
    const product = PosProductModel(productId: 'p1', name: 'Tea', type: 'physical', categoryId: 'c1', variants: [variant]);

    PosCatalogItemController make({bool manager = true}) {
      repo = MockPosRepository();
      final cats = MockCategoryRepository();
      when(() => cats.getCategories()).thenAnswer((_) async => null);
      final c = PosCatalogItemController(product: product, variant: variant, repository: repo, categories: cats, storeId: 'store-1', isManager: manager);
      Get.put(c, tag: 'v1');
      return c;
    }

    void stubUpdate(({bool success, String? message, String? code, Map<String, dynamic>? data}) Function(Invocation) f) {
      when(() => repo.updateCatalogVariant(any(), any(), any(), approverToken: any(named: 'approverToken'))).thenAnswer((i) async => f(i));
    }

    const ok = (success: true, message: null, code: null, data: <String, dynamic>{});

    test('only what CHANGED is sent (price, barcode cleared as null, HS code), and a manager needs no approval', () async {
      final c = make();
      c.onInit();
      stubUpdate((_) => ok);
      c.price.text = '12.5';
      c.barcode.text = '';
      c.hsCode.text = '21011100';
      expect(c.hasChanges, isTrue);
      expect(await c.save(), isTrue);
      final sent = verify(() => repo.updateCatalogVariant('store-1', 'v1', captureAny(), approverToken: captureAny(named: 'approverToken'))).captured;
      expect(sent[0], {'price': 12.5, 'barcode': null, 'hsCode': '21011100'});
      expect(sent[1], isNull);
    });

    test('nothing changed → nothing is sent', () async {
      final c = make();
      c.onInit();
      expect(await c.save(), isFalse);
      expect(c.info.value, 'Nothing to save.');
      verifyNever(() => repo.updateCatalogVariant(any(), any(), any(), approverToken: any(named: 'approverToken')));
    });

    test('a server refusal (barcode in use, price precision) is shown as the server said it, and nothing is claimed saved', () async {
      final c = make();
      c.onInit();
      stubUpdate((_) => (success: false, message: 'Barcode 222 is already used by COF-1 in this store', code: 'BARCODE_IN_USE', data: null));
      c.barcode.text = '222';
      expect(await c.save(), isFalse);
      expect(c.error.value, contains('already used by COF-1'));
    });

    test('an invalid price text is refused locally', () async {
      final c = make();
      c.onInit();
      c.price.text = '12.5.3';
      expect(await c.save(), isFalse);
      expect(c.error.value, 'Enter a valid price.');
    });

    test('double tap on Save is ONE request', () async {
      final c = make();
      c.onInit();
      final gate = Completer<({bool success, String? message, String? code, Map<String, dynamic>? data})>();
      when(() => repo.updateCatalogVariant(any(), any(), any(), approverToken: any(named: 'approverToken'))).thenAnswer((_) => gate.future);
      c.price.text = '11';
      final a = c.save();
      await Future<void>.delayed(Duration.zero);
      expect(await c.save(), isFalse);
      gate.complete(ok);
      expect(await a, isTrue);
      verify(() => repo.updateCatalogVariant(any(), any(), any(), approverToken: any(named: 'approverToken'))).called(1);
    });

    test('stock is a movement: delta + reason (+ note); the new on-hand shows; zero or text is refused', () async {
      final c = make();
      c.onInit();
      when(() => repo.adjustCatalogStock(any(), any(), delta: any(named: 'delta'), reason: any(named: 'reason'), note: any(named: 'note'), approverToken: any(named: 'approverToken'))).thenAnswer((_) async => (success: true, message: null, code: null, data: {'before': 8, 'after': 5}));
      c.stockDelta.text = '0';
      expect(await c.adjustStock(), isFalse);
      c.stockDelta.text = 'abc';
      expect(await c.adjustStock(), isFalse);
      c.stockDelta.text = '-3';
      c.stockReason.value = 'damaged';
      c.stockNote.text = 'dropped';
      expect(await c.adjustStock(), isTrue);
      expect(c.stock.value, 5);
      verify(() => repo.adjustCatalogStock('store-1', 'v1', delta: -3, reason: 'damaged', note: 'dropped', approverToken: null)).called(1);
      expect(c.stockDelta.text, isEmpty);
    });

    testWidgets('a non-manager is asked for a manager PIN on each save; the manager\'s token is what is sent; cancelling sends nothing', (t) async {
      final c = make(manager: false);
      c.onInit();
      await pump(t, const Scaffold(body: SizedBox.shrink()), size: const Size(800, 1400));
      stubUpdate((_) => ok);
      when(() => repo.pinLogin(storeId: any(named: 'storeId'), email: any(named: 'email'), pin: any(named: 'pin'))).thenAnswer((_) async => (success: true, employee: manager(), activeSession: null, employeeToken: 'mgr', message: null));
      c.price.text = '11';
      final saving = c.save();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(find.byKey(const Key('approverEmail')), findsOneWidget);
      await t.enterText(find.byKey(const Key('approverEmail')), 'mia@x.pk');
      for (final d in ['1', '1', '1', '1']) {
        await t.tap(find.text(d).last);
        await t.pump();
      }
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(await saving, isTrue);
      verify(() => repo.updateCatalogVariant('store-1', 'v1', any(), approverToken: 'mgr')).called(1);
      // cancelled approval
      c.price.text = '12';
      final again = c.save();
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      await t.tap(find.byKey(const Key('approverCancel')));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 300));
      }
      expect(await again, isFalse);
      verifyNever(() => repo.updateCatalogVariant('store-1', 'v1', any(), approverToken: null));
    });

    testWidgets('the item screen shows price / barcode / HS / category / stock fields, the approval note for a non-manager, and the unlimited-stock case', (t) async {
      final c = make(manager: false);
      await pump(t, PosCatalogItemView(product: product, variant: variant, controller: c));
      for (final k in ['catalogPrice', 'catalogBarcode', 'catalogHs', 'catalogSave', 'catalogDelta', 'catalogAdjust', 'catalogApprovalNote']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(t.widget<Text>(find.byKey(const Key('catalogStock'))).data, '8 on hand');
      Get.reset();
      const unl = PosProductVariant(variantId: 'v2', sku: 'U', price: 1, stock: 0, unlimitedStock: true, isDefault: true);
      final c2 = PosCatalogItemController(product: const PosProductModel(productId: 'p2', name: 'Refill', type: 'physical', categoryId: '', variants: [unl]), variant: unl, repository: MockPosRepository(), categories: _noCats(), storeId: 'store-1', isManager: true);
      Get.put(c2, tag: 'v2');
      await pump(t, PosCatalogItemView(product: const PosProductModel(productId: 'p2', name: 'Refill', type: 'physical', categoryId: '', variants: [unl]), variant: unl, controller: c2));
      expect(find.byKey(const Key('catalogAdjust')), findsNothing);
      expect(find.text('This item has unlimited stock.'), findsOneWidget);
    });

    testWidgets('the catalog list shows items with SKU, barcode, price and stock; an empty search says so', (t) async {
      final r = MockPosRepository();
      when(() => r.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => (items: [product], total: 1, totalPages: 1, hasMore: false));
      final c = PosCatalogController(repository: r, storeId: 'store-1');
      Get.put(c);
      await pump(t, PosCatalogView(controller: c));
      expect(find.byKey(const Key('catalogItem_v1')), findsOneWidget);
      expect(find.textContaining('TEA-1 · 111'), findsOneWidget);
      when(() => r.searchProducts(storeId: any(named: 'storeId'), q: any(named: 'q'))).thenAnswer((_) async => <PosProductModel>[]);
      await c.search('zzz');
      await t.pump();
      expect(find.text('No items found'), findsOneWidget);
    });
  });

  group('store tax profile (owner)', () {
    late MockPosRepository repo;
    PosTaxProfileController make({PosSettingsModel? s}) {
      repo = MockPosRepository();
      when(() => repo.getPosSettings('store-1')).thenAnswer((_) async => s ?? const PosSettingsModel(storeId: 'store-1', taxRate: 0.1, taxNtn: '1234567-8', taxStrn: '3277876', taxLegalName: 'Test Traders', taxRegisteredAddress: '12 Mall Road', defaultTaxCategory: 'exempt', cashierReturnsEnabled: true, returnApprovalAboveMinor: 500000, returnApprovalAfterDays: 7));
      final c = PosTaxProfileController(repository: repo, storeId: 'store-1');
      Get.put(c);
      return c;
    }

    testWidgets('the saved profile and return policy fill the form (amount shown in major units)', (t) async {
      final c = make();
      await pump(t, PosTaxProfileView(controller: c));
      expect(c.ntn.text, '1234567-8');
      expect(c.legalName.text, 'Test Traders');
      expect(c.defaultCategory.value, 'exempt');
      expect(c.cashierReturns.value, isTrue);
      expect(c.amountLimit.text, '5000');
      expect(c.daysLimit.text, '7');
      expect(find.byKey(const Key('taxSave')), findsOneWidget);
    });

    test('save sends the profile, the category and the policy (amount in MINOR units; empty = null = no limit), once', () async {
      final c = make();
      await c.load();
      c.ntn.text = '7654321-0';
      c.strn.text = '';
      c.amountLimit.text = '25.50';
      c.daysLimit.text = '';
      c.cashierReturns.value = false;
      when(() => repo.updatePosSettings('store-1', any())).thenAnswer((_) async => const PosSettingsModel(storeId: 'store-1', taxRate: 0.1));
      expect(await c.save(), isTrue);
      final sent = verify(() => repo.updatePosSettings('store-1', captureAny())).captured.single as Map<String, dynamic>;
      expect(sent, {
        'taxNtn': '7654321-0',
        'taxStrn': null,
        'taxLegalName': 'Test Traders',
        'taxRegisteredAddress': '12 Mall Road',
        'defaultTaxCategory': 'exempt',
        'cashierReturnsEnabled': false,
        'returnApprovalAboveMinor': 2550,
        'returnApprovalAfterDays': null,
      });
    });

    test('bad numbers are refused before anything is sent; a server refusal (bad NTN) is explained', () async {
      final c = make();
      await c.load();
      c.amountLimit.text = 'abc';
      expect(await c.save(), isFalse);
      expect(c.error.value, contains('valid amount limit'));
      c.amountLimit.text = '';
      c.daysLimit.text = '1.5';
      expect(await c.save(), isFalse);
      expect(c.error.value, contains('whole number'));
      c.daysLimit.text = '';
      when(() => repo.updatePosSettings('store-1', any())).thenAnswer((_) async => null);
      expect(await c.save(), isFalse);
      expect(c.error.value, contains('NTN'));
    });

    test('a double tap on Save is one request', () async {
      final c = make();
      await c.load();
      final gate = Completer<PosSettingsModel?>();
      when(() => repo.updatePosSettings('store-1', any())).thenAnswer((_) => gate.future);
      final a = c.save();
      await Future<void>.delayed(Duration.zero);
      expect(await c.save(), isFalse);
      gate.complete(const PosSettingsModel(storeId: 'store-1', taxRate: 0));
      expect(await a, isTrue);
      verify(() => repo.updatePosSettings('store-1', any())).called(1);
    });

    testWidgets('tablet + dark render', (t) async {
      await pump(t, PosTaxProfileView(controller: make()), size: const Size(1100, 1000), theme: AppTheme.dark);
      expect(find.byKey(const Key('taxNtn')), findsOneWidget);
    });
  });

  group('KYB: a PDF from the device (same privacy rules as a photo)', () {
    test('the PDF is uploaded and its temporary copy is DELETED afterwards', () async {
      final repo = FakeKyb();
      final file = File('${Directory.systemTemp.path}/kyb_pdf_${DateTime.now().microsecondsSinceEpoch}.pdf')..writeAsBytesSync([0x25, 0x50, 0x44, 0x46]);
      final c = PosKybController(repository: repo, storeId: 's1', lockWatcher: (_) => null, pdfPicker: () async => file);
      await c.pickPdfAndUpload('bank_proof');
      expect(repo.uploaded.single, startsWith('bank_proof:'));
      expect(file.existsSync(), isFalse);
      expect(c.uploadingType.value, isNull);
    });

    test('cancelling the picker uploads nothing; a refused upload shows the server\'s message and the copy is still deleted', () async {
      final repo = FakeKyb();
      final c = PosKybController(repository: repo, storeId: 's1', lockWatcher: (_) => null, pdfPicker: () async => null);
      await c.pickPdfAndUpload('bank_proof');
      expect(repo.uploaded, isEmpty);
    });
  });

  test('the KYB view model keeps working with the document list used by the PDF button', () {
    expect(const KybDocumentInfo(id: 'd', type: 'bank_proof', fileName: 'a.pdf').fileName, 'a.pdf');
  });
}
