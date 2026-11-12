// Screenshot pass for the G5.2–G5.7 screens on the iOS simulator — mocked repositories, real rendering, light AND dark (phone): product page,
// send receipt, payments setup, integrations (with an API key), receipt designer with a logo, role presets.
// Run: SIM_DEVICE_ID=<udid> tool/shoot.sh integration_test/g52_g57_screens_shots_test.dart docs/pos-blueprint/g5_7_screenshots/phone x
// ignore_for_file: avoid_print
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_page_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/roles_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/roles_view.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/product_page_controller.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/product_page_view.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/controllers/pos_integrations_controller.dart';
import 'package:solvexo_pos/app/modules/pos_integrations/views/pos_integrations_view.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/controllers/pos_payments_setup_controller.dart';
import 'package:solvexo_pos/app/modules/pos_payments_setup/views/pos_payments_setup_view.dart';
import 'package:solvexo_pos/app/modules/pos_sale_detail/widgets/send_receipt_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/receipt_logo.dart';

class _Repo extends Mock implements PosRepository {}

ConnectorsStatus _status() => ConnectorsStatus.fromJson({
      'flags': {'emailReceipts': true, 'smsReceipts': false, 'cardExternalTerminal': true, 'fiscal': false, 'raastDisabled': false},
      'cardGateway': {'provider': null, 'testMode': false, 'configured': false},
      'fiscal': {'provider': 'mock', 'testMode': true, 'configured': true},
      'raast': {'kybStatus': 'verified', 'enabled': true, 'providerKey': 'mock', 'testMode': true},
    });

LogoBitmap _logo() {
  const w = 180, h = 90;
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = x - 90, dy = y - 45;
      final l = (dx * dx + dy * dy < 1600) ? (40 + (x * 2) % 180) : 255; // a shaded disc → shows the dithering
      final i = (y * w + x) * 4;
      rgba[i] = l;
      rgba[i + 1] = l;
      rgba[i + 2] = l;
      rgba[i + 3] = 255;
    }
  }
  return ReceiptLogo.dither(rgba, w, h);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});

  Future<void> shot(WidgetTester t, String name, String theme) async {
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    print('SHOT ${name}_$theme');
    for (var i = 0; i < 40; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  for (final dark in [false, true]) {
    final tn = dark ? 'dark' : 'light';
    late _Repo repo;
    setUp(() async {
      Get.testMode = true;
      Get.reset();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'PKR', exponent: 2);
      Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = true);
      repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getConnectors(any())).thenAnswer((_) async => _status());
    });

    Future<void> app(WidgetTester t, Widget w) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: dark ? AppTheme.dark : AppTheme.light, home: w)));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    testWidgets('$tn: product page', (t) async {
      when(() => repo.getProductPage('st1', 'p1')).thenAnswer((_) async => ProductPage.fromJson({
            'currency': 'PKR', 'currencyExponent': 2, 'canEdit': true,
            'product': {
              'id': 'p1', 'name': 'Green tea 100g', 'description': 'Loose leaf, from Swat', 'status': 'active', 'categoryName': 'Tea', 'images': [],
              'variants': [
                {'id': 'v1', 'sku': 'TEA-100', 'options': [{'name': 'Size', 'value': '100g'}], 'priceMinor': 45000, 'costMinor': 30000, 'stock': 12, 'reorderPoint': 4},
                {'id': 'v2', 'sku': 'TEA-250', 'options': [{'name': 'Size', 'value': '250g'}], 'priceMinor': 99000, 'costMinor': 64000, 'stock': 3, 'reorderPoint': 4},
              ],
              'stockByLocation': [{'locationId': 'l1', 'name': 'Tariq Road', 'stock': 8}, {'locationId': 'l2', 'name': 'Clifton', 'stock': 7}],
            },
          }));
      final c = ProductPageController(productId: 'p1', repository: repo, storeId: 'st1');
      await app(t, ProductPageView(productId: 'p1', controller: c));
      await shot(t, 'g52_01_product_page', tn);
    });

    testWidgets('$tn: send receipt', (t) async {
      when(() => repo.getReceiptChannels('st1')).thenAnswer((_) async => (email: true, sms: true));
      await app(t, Scaffold(appBar: AppBar(title: const Text('Send receipt')), body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SendReceiptSheet(storeId: 'st1', saleId: 's1', link: 'https://solvexo.store/r/s/karachi-mart/pos-1', message: 'Karachi Mart: your receipt (PKR 1,250.00)', customerPhone: '+92 300 1234567', customerEmail: 'ayesha@shop.pk', repository: repo))));
      await shot(t, 'g53_01_send_receipt', tn);
    });

    testWidgets('$tn: payments setup', (t) async {
      final c = PosPaymentsSetupController(repo: repo, storeId: 'st1');
      await t.runAsync(c.load);
      await app(t, PosPaymentsSetupView(controller: c));
      await shot(t, 'g54_01_payments_setup', tn);
    });

    testWidgets('$tn: integrations', (t) async {
      when(() => repo.getApiKeys(any())).thenAnswer((_) async => StoreApiKeys.fromJson({
            'keys': [
              {'id': 'k1', 'name': 'Accountant (Xero import)', 'prefix': 'Ab12Cd34Ef56', 'scopes': ['accounting:read'], 'status': 'active', 'expiresAt': '2027-02-10T00:00:00.000Z', 'lastUsedAt': '2026-11-11T09:00:00.000Z'},
              {'id': 'k2', 'name': 'Old BI sheet', 'prefix': 'Zz98Yy76Xx54', 'scopes': ['sales:read', 'inventory:read'], 'status': 'revoked', 'expiresAt': '2026-12-01T00:00:00.000Z'},
            ],
            'scopes': ['sales:read', 'inventory:read', 'accounting:read'],
            'ratePerMinute': 60,
          }));
      final c = PosIntegrationsController(repo: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 12));
      await t.runAsync(c.load);
      await app(t, PosIntegrationsView(controller: c));
      await shot(t, 'g57_01_integrations', tn);
      await t.drag(find.byType(ListView).first, const Offset(0, -900));
      await shot(t, 'g57_02_integrations_keys', tn);
    });

    testWidgets('$tn: receipt designer with a logo', (t) async {
      when(() => repo.getStoreSettings('st1')).thenAnswer((_) async => StoreSettings.fromJson({
            'receipt': {'showLogo': true, 'showQr': true, 'defaultPaperWidth': 80, 'logoUrl': 'https://cdn.example/logo.png', 'header': 'Thank you for shopping'},
            'security': {}, 'profile': {'businessName': 'Karachi Mart', 'businessAddress': 'Tariq Road', 'businessTaxId': '1234567-8'}, 'canEdit': true,
          }));
      final c = StoreSettingsController(repository: repo, storeId: 'st1');
      final bmp = _logo();
      c.logoLoader = (_, __) async => bmp;
      Get.put(c);
      await t.runAsync(c.load);
      await app(t, ReceiptDesignerView(controller: c));
      await shot(t, 'g56_01_receipt_logo', tn);
    });

    testWidgets('$tn: role presets', (t) async {
      when(() => repo.getPermissionMatrix('st1')).thenAnswer((_) async => PermissionMatrix.fromJson({
            'version': 3, 'canEdit': true,
            'actions': [
              {'action': 'inventory.adjust', 'label': 'Adjust stock', 'roles': ['cashier', 'manager', 'owner'], 'defaultRoles': ['cashier', 'manager', 'owner']},
              {'action': 'catalog.import', 'label': 'Import the catalog', 'roles': ['manager', 'owner'], 'defaultRoles': ['manager', 'owner']},
            ],
            'presets': [
              {'key': 'standard', 'label': 'Standard', 'summary': 'The documented defaults: cashiers sell, managers run the shop, the owner controls money settings.', 'status': 'proposed'},
              {'key': 'small_shop', 'label': 'Small shop', 'summary': 'Cashiers may also edit customers, run stock counts and receive goods without a purchase order.', 'status': 'proposed'},
              {'key': 'strict', 'label': 'Strict (owner away)', 'summary': 'Cashiers cannot adjust stock, record expenses or refund to store credit; managers cannot import, pay suppliers or adjust credit.', 'status': 'proposed'},
            ],
          }));
      final c = Get.put(RolesController(repository: repo, storeId: 'st1'), tag: 'shots-$tn');
      await app(t, RolesView(controller: c));
      await t.tap(find.byKey(const Key('permPresets')));
      await shot(t, 'g56_02_role_presets', tn);
    });
  }
}
