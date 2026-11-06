// Screenshot pass for the G2.5 / G2.6 screens on the iOS simulator (real rendering, real fonts), light AND dark in one run.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_dashboard_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/modules/pos/views/dashboard_pulse.dart';
import 'package:solvexo_pos/app/modules/pos_catalog/controllers/pos_catalog_controller.dart';
import 'package:solvexo_pos/app/modules/pos_catalog/views/pos_catalog_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/controllers/pos_documents_controller.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/credit_note_view.dart';
import 'package:solvexo_pos/app/modules/pos_documents/views/tax_invoice_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/views/pos_kyb_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_complete_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_view.dart';
import 'package:solvexo_pos/app/modules/pos_tax_profile/pos_tax_profile.dart';
import 'package:solvexo_pos/core/design/design.dart';

import '../test/g24_screens_test.dart' show FakeKyb;
import '../test/g25_returns_documents_test.dart' show invoiceSale, note;
import '../test/g26_dashboard_catalog_test.dart' show dash;
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
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    testWidgets('returns + documents ($tn)', (t) async {
      Get.reset();
      ReasonPicker.testOverride = (_) async => const PosReasonChoice('wrong_item', '');
      final repo = MockPosRepository();
      final sale2 = invoiceSale(extraLine: true);
      when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => sale2);
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.lastErrorReasons).thenReturn(const []);
      when(() => repo.lastCreditNote).thenReturn({'id': 'cn1', 'number': 'CN-000004', 'totalMinor': 990});
      final c = PosReturnController(repository: repo, saleId: 'sale-1');
      Get.put(c);
      await c.load();
      await show(t, PosReturnView(controller: c));
      c.setQty('i1', 1);
      await shot(t, 'g25_01_return_items', tn);
      c.setRestock('i1', false);
      c.receiptPresented.value = false;
      await shot(t, 'g25_02_return_not_restocked_no_receipt', tn);
      c.result.value = {'number': 'CN-000004'};
      c.resultAmount = 12.5;
      c.resultInstructions.assignAll(['Card: refund \$7.50 on the card machine', 'Cash: take \$5.00 from the drawer']);
      await show(t, PosReturnCompleteView(c: c));
      await shot(t, 'g25_03_return_complete', tn);

      final docRepo = MockPosRepository();
      when(() => docRepo.getSaleById('sale-1')).thenAnswer((_) async => sale2);
      when(() => docRepo.getSaleDocuments('sale-1')).thenAnswer((_) async => PosSaleDocuments(saleNumber: 'POS-00007', status: 'partially_refunded', creditNotes: [note(), note(number: 'CN-000002', total: 500, restock: false)]));
      final d = PosDocumentsController(repository: docRepo, saleId: 'sale-1');
      Get.put(d, tag: 'doc');
      await d.load();
      await show(t, TaxInvoiceView(controller: d));
      await shot(t, 'g25_04_tax_invoice', tn);
      await show(t, CreditNoteView(controller: d, number: 'CN-000001'));
      await shot(t, 'g25_05_credit_note', tn);
      Get.reset();
    });

    testWidgets('dashboard, catalog, tax profile, held coupon, KYB pdf ($tn)', (t) async {
      Get.reset();
      await show(t, Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: DashboardPulse(d: PosDashboard.fromJson(dash()))))));
      await shot(t, 'g25_06_dashboard_manager', tn);
      await show(t, Scaffold(body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: DashboardPulse(d: PosDashboard.fromJson(dash(role: 'cashier', shift: true)))))));
      await shot(t, 'g25_07_dashboard_cashier_shift', tn);

      final repo = MockPosRepository();
      const variant = PosProductVariant(variantId: 'v1', sku: 'TEA-1', barcode: '8964000012345', hsCode: '09024090', price: 10, stock: 8, isDefault: true);
      const product = PosProductModel(productId: 'p1', name: 'Tea', type: 'physical', categoryId: 'c1', variants: [variant]);
      const coffee = PosProductModel(productId: 'p2', name: 'Coffee beans', type: 'physical', categoryId: 'c1', variants: [PosProductVariant(variantId: 'v2', sku: 'COF-1', barcode: '8964000099999', price: 24, stock: 3, isDefault: true)]);
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer((_) async => (items: [product, coffee], total: 2, totalPages: 1, hasMore: false));
      final cc = PosCatalogController(repository: repo, storeId: 'store-1');
      Get.put(cc);
      await show(t, PosCatalogView(controller: cc));
      await shot(t, 'g25_08_catalog_list', tn);
      final cats = MockCategoryRepository();
      when(() => cats.getCategories()).thenAnswer((_) async => null);
      final ic = PosCatalogItemController(product: product, variant: variant, repository: repo, categories: cats, storeId: 'store-1', isManager: false);
      Get.put(ic, tag: 'v1');
      await show(t, PosCatalogItemView(product: product, variant: variant, controller: ic));
      await shot(t, 'g25_09_catalog_item', tn);

      final srepo = MockPosRepository();
      when(() => srepo.getPosSettings('store-1')).thenAnswer((_) async => const PosSettingsModel(storeId: 'store-1', taxRate: 0.1, taxNtn: '1234567-8', taxStrn: '3277876123456', taxLegalName: 'Test Traders (Pvt) Ltd', taxRegisteredAddress: '12 Mall Road, Lahore', cashierReturnsEnabled: true, returnApprovalAboveMinor: 500000, returnApprovalAfterDays: 7));
      final tp = PosTaxProfileController(repository: srepo, storeId: 'store-1');
      Get.put(tp);
      await show(t, PosTaxProfileView(controller: tp));
      await shot(t, 'g25_10_store_tax_profile', tn);

      final h = SaleHarness();
      h.putController(taxRate: 0.1);
      h.addLine(h.products[0], qty: 2);
      h.c.heldCouponNotice.value = 'The coupon SAVE10 can no longer be used — This coupon has expired. The total is now \$22.00.';
      await show(t, Scaffold(body: SafeArea(child: CartPanel(c: h.c))));
      await shot(t, 'g25_11_held_coupon_notice', tn);

      Get.reset();
      final kyb = FakeKyb()..current = const KybView(status: 'draft', requiredDocuments: ['owner_cnic', 'bank_proof'], optionalDocuments: ['address_proof'], missingDocuments: ['bank_proof'], documents: [KybDocumentInfo(id: 'd1', type: 'owner_cnic', fileName: 'cnic.jpg')]);
      final kc = PosKybController(repository: kyb, storeId: 's1', lockWatcher: (_) => null);
      Get.put(kc);
      await show(t, PosKybView(controller: kc));
      await t.scrollUntilVisible(find.byKey(const Key('kybPdf_bank_proof')), 300, scrollable: find.byType(Scrollable).first);
      await shot(t, 'g25_12_kyb_pdf_button', tn);
      Get.reset();
    });
  }
}
