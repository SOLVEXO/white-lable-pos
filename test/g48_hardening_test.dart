// G4.8 on the till: reprints recorded through the gate (a manager PIN when the store requires it; offline rules), "REPRINT #n" and the receipt
// designer's QR / barcode / points on the thermal and PDF receipt, the two new security switches, and "costs hidden" shown as a notice — never zeros.
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/reprint_gate.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_overview_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_view.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/payables_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/payables_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/receipt_escpos_builder.dart';
import 'package:solvexo_pos/utils/receipt_pdf_builder.dart';

import 'support/g40_fixtures.dart';
import 'support/inventory_fixtures.dart';

class _Repo extends Mock implements PosRepository {}

typedef _Rep = ({bool success, String? code, String? message, int? reprintNumber, String? kind});
typedef _SetRes = ({bool success, String? code, String? message, StoreSettings? settings});

PosSaleModel _sale({int earned = 12, int redeemed = 0}) => PosSaleModel.fromJson({
  '_id': 's1',
  'saleNumber': 'S-1042',
  'storeId': 'st1',
  'sessionId': 'x',
  'registerId': 'r',
  'employeeId': 'e',
  'items': [],
  'discount': 0,
  'tax': 0,
  'subtotal': 10.0,
  'total': 10.0,
  'paymentMethod': 'cash',
  'customerName': 'Walk-in',
  'notes': '',
  'status': 'completed',
  'createdAt': '2026-11-10T10:00:00.000Z',
  'currency': 'PKR',
  'currencyExponent': 2,
  'loyalty': {'earnedPoints': earned, 'redeemedPoints': redeemed},
});

void main() {
  late _Repo repo;
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    StoreDay.forget();
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
  });

  // ── reprint gate ───────────────────────────────────────────────────────────────────────────
  group('reprint gate', () {
    void stub({String? approver, required _Rep Function() answer}) => when(
      () => repo.recordReprint('st1', documentType: any(named: 'documentType'), documentId: any(named: 'documentId'), approverToken: approver),
    ).thenAnswer((_) async => answer());

    test('online: recorded, the number comes back', () async {
      stub(answer: () => (success: true, code: null, message: null, reprintNumber: 3, kind: null));
      final go = await ReprintGate(repository: repo, askManager: (_) async => fail('no PIN asked')).record(storeId: 'st1', documentType: 'sale', documentId: 's1', requirePinCached: false);
      expect([go.ok, go.number], [true, 3]);
    });

    test('PIN required: a manager approves → recorded with their token; backing out stops it; a cashier\'s PIN is refused in words', () async {
      stub(answer: () => (success: false, code: 'POS_APPROVAL_REQUIRED', message: 'A manager must approve this reprint', reprintNumber: null, kind: null));
      stub(approver: 'mgr-token', answer: () => (success: true, code: null, message: null, reprintNumber: 1, kind: null));
      final go = await ReprintGate(repository: repo, askManager: (_) async => 'mgr-token').record(storeId: 'st1', documentType: 'invoice', documentId: 's1', requirePinCached: true);
      expect([go.ok, go.number], [true, 1]);
      final no = await ReprintGate(repository: repo, askManager: (_) async => null).record(storeId: 'st1', documentType: 'invoice', documentId: 's1', requirePinCached: true);
      expect([no.ok, no.message], [false, 'Reprint cancelled: a manager did not approve it.']);
      stub(approver: 'cashier-token', answer: () => (success: false, code: 'POS_APPROVAL_REQUIRED', message: 'x', reprintNumber: null, kind: null));
      final bad = await ReprintGate(repository: repo, askManager: (_) async => 'cashier-token').record(storeId: 'st1', documentType: 'invoice', documentId: 's1', requirePinCached: true);
      expect(bad.message, contains('not a manager'));
    });

    test('offline: a store that requires a PIN refuses; otherwise the till prints "COPY" (no number)', () async {
      stub(answer: () => (success: false, code: null, message: null, reprintNumber: null, kind: null));
      final strict = await ReprintGate(repository: repo, askManager: (_) async => 'x').record(storeId: 'st1', documentType: 'sale', documentId: 's1', requirePinCached: true);
      expect([strict.ok, strict.message], [false, contains('internet')]);
      final open = await ReprintGate(repository: repo, askManager: (_) async => 'x').record(storeId: 'st1', documentType: 'sale', documentId: 's1', requirePinCached: false);
      expect([open.ok, open.number], [true, null]);
    });
  });

  // ── the receipt ────────────────────────────────────────────────────────────────────────────
  group('receipt: REPRINT #n, QR, barcode, points', () {
    PosSettingsModel settings(Map<String, dynamic> receipt) => PosSettingsModel.fromJson({'storeId': 'st1', 'taxRate': 0, 'receiptOptions': receipt, 'securityPrefs': {'requirePinForReprint': true}});

    test('the settings carry the security rules (cached for offline)', () {
      final s = settings({});
      expect(s.requirePinForReprint, isTrue);
      expect(PosSettingsModel.fromJson(s.toCacheJson()).requirePinForReprint, isTrue);
    });

    test('switches on: the QR is the digital-receipt link, the barcode the receipt number, points of the sale; off: none', () {
      final on = ReceiptData.fromSale(_sale(redeemed: 5), settings({'showQr': true, 'showBarcode': true, 'showLoyaltyBalance': true}), receiptUrl: 'https://solvexo.app/r/abc');
      expect([on.qrPayload, on.barcodeData, on.pointsEarned, on.pointsRedeemed, on.qrWanted], ['https://solvexo.app/r/abc', 'S-1042', 12, 5, true]);
      final noUrl = ReceiptData.fromSale(_sale(), settings({'showQr': true}));
      expect([noUrl.qrPayload, noUrl.qrWanted], [null, true], reason: 'the link may arrive later (the success screen loads it)');
      final off = ReceiptData.fromSale(_sale(), settings({'showQr': false, 'showBarcode': false, 'showLoyaltyBalance': false}), receiptUrl: 'https://x');
      expect([off.qrPayload, off.barcodeData, off.pointsEarned], [null, null, null]);
      expect(receiptBarcode('S-1042\u{1F600}'), 'S-1042');
    });

    test('thermal: "REPRINT #3" instead of COPY, the points rows, a QR (GS ( k) and a Code 128 barcode (GS k); the PDF builds', () async {
      final d = ReceiptData.fromSale(_sale(), settings({'showQr': true, 'showBarcode': true}), receiptUrl: 'https://solvexo.app/r/abc', asciiSafeMoney: true).copyWith(reprintNumber: 3);
      final bytes = await ReceiptEscPosBuilder.build(data: d, paperSize: PaperSize.mm80);
      final text = String.fromCharCodes(bytes);
      expect(text, contains('REPRINT #3'));
      expect(text, isNot(contains('COPY')));
      expect(text, contains('Points earned'));
      bool has(List<int> seq) {
        for (var i = 0; i + seq.length <= bytes.length; i++) {
          var ok = true;
          for (var j = 0; j < seq.length && ok; j++) {
            ok = bytes[i + j] == seq[j];
          }
          if (ok) return true;
        }
        return false;
      }

      expect(has([0x1D, 0x28, 0x6B]), isTrue, reason: 'QR command');
      expect(has([0x1D, 0x6B]), isTrue, reason: 'barcode command');
      expect((await ReceiptPdfBuilder.build(data: d)).length, greaterThan(500));
      // not recorded (offline): COPY as before
      expect(String.fromCharCodes(await ReceiptEscPosBuilder.build(data: d.copyWith().let((x) => ReceiptData.fromJson({...x.toJson()..remove('reprintNumber')})))), contains('COPY'));
    });
  });

  // ── screens ────────────────────────────────────────────────────────────────────────────────
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester t, Widget w, {bool dark = false}) async {
    t.view.physicalSize = const Size(390, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), theme: dark ? AppTheme.dark : AppTheme.light, home: w)));
    await settle(t);
  }

  group('security switches', () {
    testWidgets('the owner turns on PIN-to-reprint and hide-costs; a manager sees them read only', (t) async {
      final s = StoreSettings.fromJson({'security': {'autoLockMinutes': 5}, 'canEdit': true});
      when(() => repo.getStoreSettings('st1')).thenAnswer((_) async => s);
      when(() => repo.updateStoreSettings('st1', any())).thenAnswer(
        (i) async => (success: true, code: null, message: null, settings: StoreSettings.fromJson({'security': (i.positionalArguments[1] as Map)['security'], 'canEdit': true})) as _SetRes,
      );
      final c = Get.put(StoreSettingsController(repository: repo, storeId: 'st1', applyLock: (_, __) async {}), tag: 'sec');
      await pump(t, SecuritySettingsView(controller: c));
      await t.tap(find.byKey(const Key('requirePinForReprint')));
      await settle(t);
      verify(() => repo.updateStoreSettings('st1', {'security': {'requirePinForReprint': true}})).called(1);
      expect(find.textContaining('need a manager'), findsWidgets);
      await t.tap(find.byKey(const Key('hideCostsFromManagers')));
      await settle(t);
      verify(() => repo.updateStoreSettings('st1', {'security': {'hideCostsFromManagers': true}})).called(1);
      Get.reset();
      when(() => repo.getStoreSettings('st1')).thenAnswer((_) async => StoreSettings.fromJson({'security': {'requirePinForReprint': true}, 'canEdit': false}));
      final m = Get.put(StoreSettingsController(repository: repo, storeId: 'st1', applyLock: (_, __) async {}), tag: 'sec2');
      await pump(t, SecuritySettingsView(controller: m));
      expect(t.widget<SwitchListTile>(find.descendant(of: find.byKey(const Key('requirePinForReprint')), matching: find.byType(SwitchListTile))).onChanged, isNull);
    });
  });

  group('costs hidden: a notice, never zeros', () {
    for (final dark in [false, true]) {
      testWidgets('${dark ? 'dark' : 'light'} profit report: the notice; no cost of goods / margin / after expenses; sales and expenses stay', (t) async {
        when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => zone(today: '2026-11-11'));
        when(() => repo.getEmployees('st1')).thenAnswer((_) async => []);
        when(() => repo.listRegisters('st1')).thenAnswer((_) async => []);
        registerFallbackValue(const ReportQuery(from: '', to: ''));
        registerFallbackValue(ReportKind.profit);
        final j = profitJson()..['costsHidden'] = true;
        (j['totals'] as Map).removeWhere((k, _) => ['costOfGoodsSoldMinor', 'grossMarginMinor', 'marginPercent', 'afterExpensesMinor', 'costCoveragePercent', 'costUnknownNetMinor', 'supplierPaymentsMinor', 'supplierPaymentsNote'].contains(k));
        when(() => repo.getBizReport('st1', any(), any(), sort: any(named: 'sort'), limit: any(named: 'limit'))).thenAnswer((_) async => parseBizReport(ReportKind.profit, j));
        final c = Get.put(ReportController(kind: ReportKind.profit, repository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 11, 12), canManage: true, storeName: () async => 'Dev Store'), tag: 'p$dark');
        await pump(t, ReportView(kind: ReportKind.profit, controller: c), dark: dark);
        expect(find.byKey(const Key('costsHidden')), findsOneWidget);
        expect(find.text('Cost of goods sold'), findsNothing);
        expect(find.byKey(const Key('profitGross')), findsNothing);
        expect(find.byKey(const Key('profitAfter')), findsNothing);
        expect(find.text('Net sales (ex tax)'), findsOneWidget);
        expect(find.text('Expenses'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('inventory overview: the notice where the stock value was', (t) async {
      final o = InvOverview.fromJson({...overviewJsonFrom(overview()), 'costsHidden': true}..remove('stockValueMinor'));
      when(() => repo.getInventoryOverview(any())).thenAnswer((_) async => o);
      await pump(t, InvOverviewView(controller: Get.put(InvOverviewController(repository: repo, storeId: 's1'))));
      expect(find.byKey(const Key('costsHidden')), findsOneWidget);
      expect(find.byKey(const Key('invTileValue')), findsNothing);
    });

    testWidgets('payables: supplier names and the notice — no zero amounts', (t) async {
      when(() => repo.getPayables('st1')).thenAnswer(
        (_) async => Payables.fromJson({'currency': 'USD', 'currencyExponent': 2, 'costsHidden': true, 'totals': {}, 'suppliers': [{'supplierId': 'a', 'supplierName': 'Rice traders'}]}),
      );
      await pump(t, PayablesView(controller: Get.put(PayablesController(repository: repo, storeId: 'st1'))));
      expect(find.byKey(const Key('costsHidden')), findsOneWidget);
      expect(find.text('Rice traders'), findsOneWidget);
      expect(find.byKey(const Key('payablesTotals')), findsNothing);
    });
  });
}

/// the overview fixture as server JSON again (so a test can drop fields and add `costsHidden`)
Map<String, dynamic> overviewJsonFrom(InvOverview o) => {
  'role': o.role,
  'skuCount': o.skuCount,
  'lowStockCount': o.lowStockCount,
  'outOfStockCount': o.outOfStockCount,
  'expiredLots': o.expiredLots,
  'expiringIn7Days': o.expiringIn7Days,
  'expiringIn30Days': o.expiringIn30Days,
  'stockValueMinor': o.stockValueMinor,
  'currency': 'USD',
  'currencyExponent': 2,
};

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
