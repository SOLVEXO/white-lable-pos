// Screenshot pass for the G2.4 screens on the iOS simulator (real rendering, real fonts), light AND dark in one run.
// Prints `SHOT <name>_<theme>`; tool/shoot.sh turns each into a simulator screenshot. Run once per device (phone, tablet).
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/components/reason_picker_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/kyb_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/views/pos_home_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/category_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/coupon_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/custom_item_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/discount_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_detail_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/controllers/pos_kyb_controller.dart';
import 'package:solvexo_pos/app/modules/pos_kyb/views/pos_kyb_view.dart';
import 'package:solvexo_pos/app/modules/pos_offline/controllers/pos_offline_controller.dart';
import 'package:solvexo_pos/app/modules/pos_offline/views/pos_offline_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

import '../test/support/sale_harness.dart';
import '../test/g24_screens_test.dart' show FakeKyb, MockSync;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Frames keep being pumped while we wait, so a sheet that is still sliding in (or a keyboard) has settled when the script captures.
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

    testWidgets('sale screen + sheets ($tn)', (t) async {
      Get.reset();
      final h = SaleHarness();
      h.products = [product('a', price: 12, name: 'Latte'), multiVariant('m'), product('b', price: 4.5, name: 'Croissant'), product('c', price: 7.5, name: 'Beans 250g', category: 'c2')];
      h.putController(manager: true, taxRate: 0.1);
      final c = h.c;
      await t.pumpWidget(GetMaterialApp(debugShowCheckedModeBanner: false, theme: theme, initialRoute: Routes.posHome, getPages: [GetPage(name: Routes.posHome, page: () => PosHomeView())]));
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
      await shot(t, 'g24_01_sale_screen', tn);

      // recent searches
      await c.rememberSearch('latte');
      await c.rememberSearch('beans');
      await t.tap(find.byType(TextField).first);
      await t.pump(const Duration(milliseconds: 500));
      await shot(t, 'g24_02_recent_searches', tn);
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await t.pump(const Duration(milliseconds: 800));

      // a cart with a custom item and a coupon
      h.addLine(h.products[0], qty: 2);
      c.addCustomItem(name: 'Gift wrapping', price: 4, taxCategory: 'exempt', note: 'red ribbon');
      c.appliedCoupon.value = const PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
      await t.pump(const Duration(milliseconds: 600));
      final pill = find.byKey(const Key('phoneCartSheet'));
      if (pill.evaluate().isNotEmpty) {
        await t.tap(pill);
        await t.pump(const Duration(milliseconds: 700));
      }
      await shot(t, 'g24_03_cart_custom_coupon', tn);
      if (pill.evaluate().isNotEmpty) {
        await t.tap(pill);
        await t.pump(const Duration(milliseconds: 700));
      }

      Future<void> sheet(String name, Future<void> Function() open) async {
        open();
        await t.pump(const Duration(milliseconds: 300));
        await shot(t, name, tn);
        FocusManager.instance.primaryFocus?.unfocus();
        Get.back();
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
      }

      c.appliedCoupon.value = null;
      await sheet('g24_04_custom_item_sheet', () => CustomItemSheet.open(c));
      await sheet('g24_05_coupon_sheet', () => CouponSheet.open(c));
      await sheet('g24_06_discount_sheet', () => DiscountSheet.open(c));
      await sheet('g24_07_product_detail_sheet', () => ProductDetailSheet.open(c, h.products[1]));
      await sheet('g24_08_categories_sheet', () => CategorySheet.open(c));
      await sheet('g24_09_manager_approval_sheet', () => ManagerApproval.request(reason: 'A manager must approve the custom item on this sale.', repository: h.repo));
      await sheet('g24_10_reason_picker', () => ReasonPicker.ask(PosReasonKind.refund));
      Get.reset();
    });

    testWidgets('success + offline + KYB screens ($tn)', (t) async {
      Get.reset();
      final h = SaleHarness();
      h.putController();
      when(() => h.repo.getReceiptLink(any())).thenAnswer((_) async => 'https://api.solvexo.dev/r/Zk3n9QhV2mXb7TqLw5RcYd8PfAeJ1uGs');
      final r = ReceiptData.fromSale(
        sale(total: 9.9, items: [
          const PosSaleItemModel(saleItemId: '1', productId: 'a', name: 'Latte', qty: 2, price: 5, lineTotal: 10),
        ]),
        null,
        isCopy: false,
      );
      h.c.lastOutcome.value = SaleOutcome.completed;
      h.c.lastReceipt.value = r;
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: SaleSuccessView(c: h.c, repository: h.repo)));
      await t.pump(const Duration(milliseconds: 1500));
      await shot(t, 'g24_11_success_receipt_qr', tn);
      Get.reset();

      // offline mode
      final net = NetworkStatusService()..isOnline.value = false;
      final sync = MockSync();
      when(() => sync.pendingCount).thenReturn(3.obs);
      when(() => sync.failedCount).thenReturn(1.obs);
      when(() => sync.isSyncing).thenReturn(false.obs);
      when(() => sync.lastSuccessfulSync).thenReturn(Rxn<DateTime>(DateTime(2026, 11, 6, 9, 42)));
      await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: PosOfflineView(controller: PosOfflineController(network: net, sync: sync))));
      await t.pump(const Duration(milliseconds: 800));
      await shot(t, 'g24_12_offline_mode', tn);

      // KYB: draft / rejected / in review
      Future<void> kyb(String name, KybView v) async {
        Get.reset();
        final repo = FakeKyb()..current = v;
        final c = PosKybController(repository: repo, storeId: 's1', lockWatcher: (_) => null);
        Get.put<PosKybController>(c);
        await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: PosKybView(key: ValueKey(name), controller: c)));
        await t.pump(const Duration(milliseconds: 900));
        await shot(t, name, tn);
      }

      await kyb('g24_13_kyb_draft', const KybView(status: 'draft', requiredDocuments: ['owner_cnic', 'bank_proof'], optionalDocuments: ['address_proof'], missingDocuments: ['bank_proof'], documents: [KybDocumentInfo(id: 'd1', type: 'owner_cnic', fileName: 'cnic.jpg')], legalBusinessName: 'Dev Coffee Traders', cnicMasked: '•••••••••1234'));
      await kyb('g24_14_kyb_rejected', const KybView(status: 'rejected', rejectionReason: 'The CNIC photo is unreadable — please upload it again.', requiredDocuments: ['owner_cnic', 'bank_proof'], missingDocuments: []));
      await kyb('g24_15_kyb_in_review', const KybView(status: 'submitted', requiredDocuments: ['owner_cnic', 'bank_proof'], missingDocuments: [], documents: [KybDocumentInfo(id: 'd1', type: 'owner_cnic', fileName: 'cnic.jpg'), KybDocumentInfo(id: 'd2', type: 'bank_proof', fileName: 'bank.jpg')]));
      Get.reset();
    });
  }
}
