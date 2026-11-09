// G3.2 elsewhere on the till: the Home "Expiring soon" row (managers / owners only), the lot flags in Needs attention in plain words,
// the lots on an order's lines, and the "Store credit" tender label on the documents.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/inventory_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos/controllers/pos_home_tab_controller.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_home_tab_view.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/controllers/pos_needs_attention_controller.dart';
import 'package:solvexo_pos/app/modules/pos_needs_attention/views/pos_needs_attention_view.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/controllers/pos_sale_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/views/pos_sale_detail_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';
import 'package:solvexo_pos/utils/tax_document_pdf.dart';

import 'support/fake_payments.dart';
import 'support/sale_harness.dart' show MockPosRepository;

class _MockInventoryRepository extends Mock implements InventoryRepository {}

class _MockSync extends Mock implements PendingSaleSyncService {}

enum _Env { phone, tablet, dark }

Map<String, dynamic> _dashboard({Map<String, dynamic>? expiring}) => {
  'role': 'manager',
  'scope': 'store',
  'currency': 'USD',
  'currencyExponent': 2,
  'summary': {},
  if (expiring != null) 'expiring': expiring,
};

PosSaleModel _flaggedSale(List<Map<String, dynamic>> flags) => PosSaleModel.fromJson({
  '_id': 's1',
  'saleNumber': 'S-0042',
  'storeId': 'st1',
  'sessionId': 'se',
  'registerId': 'r',
  'employeeId': 'e',
  'items': [],
  'discount': 0,
  'tax': 0,
  'subtotal': 4.0,
  'total': 4.0,
  'paymentMethod': 'cash',
  'customerName': 'Walk-in',
  'notes': '',
  'status': 'completed',
  'createdAt': '2026-11-09T10:00:00.000Z',
  'currency': 'USD',
  'currencyExponent': 2,
  'needsReview': true,
  'flags': flags,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Get.testMode = true;
  late MockPosRepository pos;

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1', 'pos_session_id': 'se', 'pos_employee_name': 'Mia', 'pos_employee_role': 'manager'});
    Get.reset();
    pos = MockPosRepository();
  });
  tearDown(Get.reset);

  for (final env in _Env.values) {
    final size = env == _Env.tablet ? const Size(834, 1194) : const Size(390, 1200);
    final theme = env == _Env.dark ? AppTheme.dark : AppTheme.light;

    group('Home "Expiring soon" (${env.name})', () {
      Future<void> mountHome(WidgetTester t, PosAccess access, Map<String, dynamic>? dashboard) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final inv = _MockInventoryRepository();
        when(() => pos.getDashboard(any())).thenAnswer((_) async => dashboard);
        when(() => pos.getSessionReport(any())).thenAnswer((_) async => null);
        when(() => pos.getDailyReport(any())).thenAnswer((_) async => null);
        when(
          () => pos.getRangeReport(
            any(),
            from: any(named: 'from'),
            to: any(named: 'to'),
          ),
        ).thenAnswer((_) async => null);
        when(() => inv.getLowStockSummary(any())).thenAnswer((_) async => null);
        final c = PosHomeTabController(posRepository: pos, inventoryRepository: inv, paymentsRepository: FakePaymentsRepo(), accessOverride: access);
        Get.put<PosHomeTabController>(c);
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: PosHomeTabView(controller: c),
          ),
        );
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      testWidgets('a manager sees expired · 7 days · 30 days and it opens the Expiring list', (t) async {
        await mountHome(t, PosAccess.manager, _dashboard(expiring: {'expiredLots': 1, 'expiringIn7Days': 2, 'expiringIn30Days': 4}));
        expect(find.byKey(const Key('homeAttention-expiring'), skipOffstage: false), findsOneWidget);
        expect(find.text('1 expired · 2 in 7 days · 4 in 30 days', skipOffstage: false), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('a cashier (the server sends no expiring block) and an all-zero manager see nothing', (t) async {
        await mountHome(t, PosAccess.cashier, _dashboard());
        expect(find.byKey(const Key('homeAttention-expiring')), findsNothing);
        Get.reset();
        await mountHome(t, PosAccess.manager, _dashboard(expiring: {'expiredLots': 0, 'expiringIn7Days': 0, 'expiringIn30Days': 0}));
        expect(find.byKey(const Key('homeAttention-expiring')), findsNothing);
      });
    });
  }

  group('Needs attention: lot flags in plain words', () {
    testWidgets('an offline sale sold from an expired lot, and one short of lot stock', (t) async {
      final sync = _MockSync();
      when(() => sync.items).thenReturn(<PendingSaleRecord>[].obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>());
      when(() => sync.refreshCounts()).thenAnswer((_) async {});
      when(() => pos.getSalesNeedingReview(any())).thenAnswer(
        (_) async => [
          _flaggedSale([
            {'type': 'expired_lot_sold_offline', 'detail': {}},
            {'type': 'lots_short', 'detail': {}},
          ]),
        ],
      );
      t.view.physicalSize = const Size(600, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final c = PosNeedsAttentionController(syncService: sync, posRepository: pos, paymentsRepository: FakePaymentsRepo());
      Get.put<PosNeedsAttentionController>(c);
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(
            theme: AppTheme.light,
            home: PosNeedsAttentionView(controller: c),
          ),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.textContaining('Sold from an expired lot while offline'), findsOneWidget);
      expect(find.textContaining('Not enough lot stock recorded'), findsOneWidget);
    });
  });

  group('order detail', () {
    testWidgets('a sold line shows its lots ("Lot B-12 ×3") and is marked when any of it was expired', (t) async {
      Get.put<ThermalPrinterService>(ThermalPrinterService());
      final sale = PosSaleModel.fromJson({
        '_id': 's1',
        'saleNumber': 'S-0042',
        'storeId': 'st1',
        'sessionId': 'se',
        'registerId': 'r',
        'employeeId': 'e',
        'discount': 0,
        'tax': 0,
        'subtotal': 24.0,
        'total': 24.0,
        'paymentMethod': 'cash',
        'customerName': 'Walk-in',
        'notes': '',
        'status': 'completed',
        'createdAt': '2026-11-09T10:00:00.000Z',
        'currency': 'USD',
        'currencyExponent': 2,
        'items': [
          {
            '_id': 'i1',
            'productId': 'p',
            'name': 'Yogurt',
            'qty': 6,
            'price': 4.0,
            'lineTotal': 24.0,
            'soldExpired': true,
            'lots': [
              {'lotId': 'l1', 'lotNumber': 'B-12', 'qty': 3, 'expired': true},
              {'lotId': 'l2', 'lotNumber': 'B-13', 'qty': 3},
            ],
          },
        ],
        'payments': [
          {'method': 'store_credit', 'amount': 24.0},
        ],
        'loyalty': {'earnedPoints': 2, 'redeemedPoints': 0, 'redeemValueMinor': 0},
      });
      when(() => pos.getSaleById(any())).thenAnswer((_) async => sale);
      when(() => pos.getPosSettings(any())).thenAnswer((_) async => null);
      final c = PosSaleDetailController(posRepository: pos);
      Get.put<PosSaleDetailController>(c);
      c.sale.value = sale; // onInit found no sale id (no route arguments here): hand it the sale
      c.isLoading.value = false;
      t.view.physicalSize = const Size(600, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ResponsiveSizer(
          builder: (_, __, ___) => GetMaterialApp(theme: AppTheme.light, home: PosSaleDetailView()),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Lot B-12 ×3 · Lot B-13 ×3'), findsOneWidget);
      expect(find.text('Sold from an expired lot'), findsOneWidget);
      expect(find.text('Store credit'), findsOneWidget);
      expect(find.text('Earned 2 points'), findsOneWidget);
    });
  });

  group('"Store credit" on the documents', () {
    test('receipt tender labels and the refund instruction', () {
      expect(ReceiptData.methodLabel('store_credit'), 'Store credit');
      expect(ReceiptData.refundHow('store_credit'), 'to store credit');
    });

    test('the credit-note PDF renders with a store-credit tender', () async {
      final note = PosCreditNote.fromJson({
        '_id': 'cn1',
        'number': 'CN-000001',
        'invoiceNumber': 'INV-000007',
        'kind': 'return',
        'scope': 'partial',
        'currency': 'USD',
        'currencyExponent': 2,
        'netMinor': 900,
        'taxMinor': 90,
        'totalMinor': 990,
        'createdAt': '2026-11-06T11:00:00.000Z',
        'seller': {'legalName': 'Test Traders Ltd'},
        'tenders': [
          {'method': 'store_credit', 'amountMinor': 990},
        ],
        'lines': [
          {'name': 'Tea', 'sku': 'TEA', 'qty': 1, 'netMinor': 900, 'taxMinor': 90, 'totalMinor': 990, 'restock': true},
        ],
      });
      final bytes = await TaxDocumentPdf.creditNote(note: note);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
