// Screenshot pass for the G4.2 – G4.6 screens on the iOS simulator — real rendering, real fonts, mocked repositories, light AND dark (phone):
// roles & permissions, activity log + integrity, settings hub + receipt designer / notifications / security / backup & sync, a store day's sales,
// the modifier sheet and price-book picker at checkout, products & pricing (hub, modifier groups, price books, new product, categories, import),
// the open shift (last close + notes & coins), transfers, expiring lots, draft PO.
// ignore_for_file: avoid_print
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/components/denomination_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/roles_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/controllers/store_settings_controller.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/roles_view.dart';
import 'package:solvexo_pos/app/modules/pos_admin/views/settings_hub_views.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/controllers/pos_audit_log_controller.dart';
import 'package:solvexo_pos/app/modules/pos_audit_log/views/pos_audit_log_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/categories_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/csv_import_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/modifier_groups_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/new_product_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/price_books_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_modifier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/price_book_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/views/pos_open_register_view.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/day_orders_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/day_orders_view.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/controllers/transfers_controller.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/draft_po_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/expiry_view.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/transfers_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class _Repo extends Mock implements PosRepository {}

// ── fixtures (PKR, exponent 2) ───────────────────────────────────────────────
PermissionMatrix _matrix() => PermissionMatrix.fromJson({
  'version': 4,
  'canEdit': true,
  'actions': [
    {
      'action': 'customers.refund',
      'label': 'Refund a sale',
      'roles': ['manager', 'owner'],
      'defaultRoles': ['manager', 'owner'],
      'approval': [
        {'limit': 'refund', 'limitLabel': 'Refund limit (PKR 5,000)', 'defaultApprover': 'manager', 'approver': 'manager', 'enabled': true},
      ],
    },
    {'action': 'inventory.adjust', 'label': 'Adjust stock', 'changed': true, 'roles': ['cashier', 'manager', 'owner'], 'defaultRoles': ['manager', 'owner']},
    {'action': 'cash.out', 'label': 'Cash out of the drawer', 'roles': ['cashier', 'manager', 'owner'], 'defaultRoles': ['cashier', 'manager', 'owner']},
    {'action': 'settings.permissions.edit', 'label': 'Change permissions', 'pinned': true, 'roles': ['owner'], 'defaultRoles': ['owner']},
  ],
});

StoreSettings _settings() => StoreSettings.fromJson({
  'receipt': {'showLogo': true, 'defaultPaperWidth': 80, 'header': 'Thank you for shopping!', 'footer': 'Exchange within 7 days with receipt', 'promoText': '10% off on Fridays'},
  'alerts': {'lowStock': true, 'largeRefund': true, 'sealFailure': true, 'unsyncedSales': false},
  'security': {'autoLockMinutes': 5, 'lockOnBackground': true},
  'profile': {'businessName': 'Karachi Mart', 'businessAddress': 'Shop 12, Tariq Road, Karachi', 'businessTaxId': '7654321-0'},
  'timeZone': 'Asia/Karachi',
  'canEdit': true,
});

ModifierGroups _groups() => ModifierGroups.fromJson({
  'currency': 'PKR',
  'currencyExponent': 2,
  'groups': [
    {
      'id': 'gSize',
      'name': 'Size',
      'minSelect': 1,
      'maxSelect': 1,
      'productIds': ['p1'],
      'options': [
        {'id': 'reg', 'name': 'Regular', 'priceDeltaMinor': 0},
        {'id': 'lg', 'name': 'Large', 'priceDeltaMinor': 15000},
      ],
    },
    {
      'id': 'gAdd',
      'name': 'Add-ons',
      'minSelect': 0,
      'maxSelect': 2,
      'productIds': ['p1'],
      'options': [
        {'id': 'shot', 'name': 'Extra shot', 'priceDeltaMinor': 8000},
        {'id': 'oat', 'name': 'Oat milk', 'priceDeltaMinor': 12000},
        {'id': 'cream', 'name': 'Whipped cream', 'priceDeltaMinor': 5000, 'active': false},
      ],
    },
  ],
});

PriceBooks _books() => PriceBooks.fromJson({
  'currency': 'PKR',
  'currencyExponent': 2,
  'books': [
    {'id': 'wh', 'name': 'Wholesale', 'inForce': true, 'note': 'Trade customers', 'entries': [{'variantId': 'v1', 'priceMinor': 40000}, {'variantId': 'v2', 'priceMinor': 120000}]},
    {'id': 'eid', 'name': 'Eid offer', 'active': true, 'inForce': false, 'startsAt': '2027-03-28T19:00:00Z', 'endsAt': '2027-04-02T19:00:00Z', 'entries': [{'variantId': 'v1', 'priceMinor': 45000}]},
  ],
});

PosProductModel _latte() => PosProductModel(productId: 'p1', name: 'Latte', type: 'physical', categoryId: '', variants: const [PosProductVariant(variantId: 'v1', sku: 'LAT', price: 550, stock: 99, unlimitedStock: true, isDefault: true)]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerFallbackValue(<String, dynamic>{});

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
      await t.pumpWidget(const SizedBox()); // an empty frame first, or a second GetMaterialApp in the same test keeps showing the first screen
      await t.pumpWidget(ResponsiveSizer(builder: (_, __, ___) => GetMaterialApp(key: UniqueKey(), debugShowCheckedModeBanner: false, theme: theme, home: w)));
      await t.pump(const Duration(milliseconds: 600));
    }

    Future<void> tap(WidgetTester t, String key) async {
      await t.tap(find.byKey(Key(key)));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 150));
      }
    }

    _Repo fresh() {
      Get.reset();
      StoreDay.forget();
      SharedPreferences.setMockInitialValues({'store_id': 'st1'});
      Money.configure(currency: 'PKR', exponent: 2);
      final repo = _Repo();
      when(() => repo.lastErrorCode).thenReturn(null);
      when(() => repo.getStoreTimeZone('st1')).thenAnswer((_) async => StoreTimeZone.fromJson({'timeZone': 'Asia/Karachi', 'today': '2026-11-11', 'canEdit': true}));
      when(() => repo.getEmployees('st1')).thenAnswer(
        (_) async => [
          PosEmployeeModel(id: 'e1', storeId: 'st1', sellerId: 's', name: 'Ayesha', email: 'a@x', role: 'cashier', shiftIds: const [], status: 'active', createdAt: DateTime(2026)),
          PosEmployeeModel(id: 'e2', storeId: 'st1', sellerId: 's', name: 'Bilal', email: 'b@x', role: 'manager', shiftIds: const [], status: 'active', createdAt: DateTime(2026)),
        ],
      );
      return repo;
    }

    T put<T>(T c) => Get.put(c, tag: '${T}_${DateTime.now().microsecondsSinceEpoch}');

    testWidgets('G4.2–G4.4 phone ($tn)', (t) async {
      // roles & permissions
      var repo = fresh();
      when(() => repo.getPermissionMatrix('st1')).thenAnswer((_) async => _matrix());
      final roles = put(RolesController(repository: repo, storeId: 'st1'));
      await show(t, RolesView(controller: roles));
      await shot(t, 'g42_01_roles', tn);
      roles.toggleRole(roles.matrix.value!.actions.first, PermRole.cashier);
      await shot(t, 'g42_02_roles_edited', tn);

      // activity log + integrity (one day changed)
      repo = fresh();
      when(
        () => repo.getAuditLogsFiltered('st1', page: any(named: 'page'), limit: any(named: 'limit'), employeeId: any(named: 'employeeId'), targetType: any(named: 'targetType'), from: any(named: 'from'), to: any(named: 'to')),
      ).thenAnswer(
        (_) async => (
          items: [
            for (final (i, a, e, ty) in [(1, 'sale_refunded', 'e2', 'sale'), (2, 'permissions_changed', null, 'permission'), (3, 'cash_out', 'e1', 'cash'), (4, 'store_settings_changed', null, 'settings'), (5, 'session_closed', 'e1', 'session')])
              PosAuditLogModel.fromJson({'_id': 'l$i', 'storeId': 'st1', 'employeeId': e, 'action': a, 'targetType': ty, 'createdAt': '2026-11-10T0$i:30:00.000Z'}),
          ],
          total: 5,
          totalPages: 1,
          hasMore: false,
        ),
      );
      when(() => repo.verifyAuditSeals('st1', from: any(named: 'from'), to: any(named: 'to'))).thenAnswer(
        (_) async => AuditVerify.fromJson({
          'ok': false,
          'days': 6,
          'results': [
            {
              'day': '2026-11-08',
              'status': 'changed',
              'changedParts': [
                {'part': 'refunds', 'sealedCount': 4, 'nowCount': 3},
              ],
            },
          ],
        }),
      );
      final audit = put(PosAuditLogController(posRepository: repo, storeId: 'st1', clock: () => DateTime(2026, 11, 11, 12)));
      await show(t, PosAuditLogView(controller: audit));
      await shot(t, 'g43_01_activity_log', tn);
      await tap(t, 'auditCheck');
      await shot(t, 'g43_02_integrity_changed', tn);

      // settings hub and its screens
      repo = fresh();
      when(() => repo.getStoreSettings('st1')).thenAnswer((_) async => _settings());
      when(() => repo.getSyncStatus('st1')).thenAnswer(
        (_) async => SyncStatus.fromJson({
          'serverTime': DateTime.now().toUtc().toIso8601String(),
          'timeZone': 'Asia/Karachi',
          'devices': [
            {'id': 'd1', 'name': 'Front till', 'platform': 'ios', 'appVersion': '1.6.0', 'lastSeenAt': DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String()},
            {'id': 'd2', 'name': 'Back office tablet', 'platform': 'android', 'appVersion': '1.6.0', 'lastSeenAt': DateTime.now().toUtc().subtract(const Duration(hours: 5)).toIso8601String()},
          ],
          'lastSeal': {'day': '2026-11-10', 'sealedAt': DateTime.now().toUtc().subtract(const Duration(hours: 9)).toIso8601String(), 'records': 312},
        }),
      );
      final st = put(StoreSettingsController(repository: repo, storeId: 'st1', queues: () => const LocalQueues(sales: 2, cash: 1), applyLock: (_, __) async {}));
      await show(t, SettingsHubView(controller: st));
      await shot(t, 'g44_01_settings_hub', tn);
      await show(t, ReceiptDesignerView(controller: st));
      await shot(t, 'g44_02_receipt_designer', tn);
      await show(t, AlertSettingsView(controller: st));
      await shot(t, 'g44_03_notifications', tn);
      await show(t, SecuritySettingsView(controller: st));
      await shot(t, 'g44_04_security', tn);
      await show(t, BackupSyncView(controller: st));
      await shot(t, 'g44_05_backup_sync', tn);

      // a store day's sales (from a day of the sales report)
      repo = fresh();
      when(() => repo.getSalesForDay('st1', '2026-11-10', page: any(named: 'page'))).thenAnswer(
        (_) async => (
          items: [
            for (final (i, n, tot, pm) in [(1, 'S-1042', 2340.0, 'cash'), (2, 'S-1041', 890.0, 'card'), (3, 'S-1040', 15600.0, 'raast_qr')])
              PosSaleModel.fromJson({'_id': 's$i', 'saleNumber': n, 'storeId': 'st1', 'sessionId': 'x', 'registerId': 'r', 'employeeId': 'e1', 'employeeName': 'Ayesha', 'items': [], 'discount': 0, 'tax': 0, 'subtotal': tot, 'total': tot, 'paymentMethod': pm, 'customerName': 'Walk-in', 'notes': '', 'status': 'completed', 'createdAt': '2026-11-10T1$i:05:00.000Z', 'currency': 'PKR', 'currencyExponent': 2}),
          ],
          total: 3,
          totalPages: 1,
          hasMore: false,
        ),
      );
      await show(t, DayOrdersView(date: '2026-11-10', controller: put(DayOrdersController(date: '2026-11-10', repository: repo, storeId: 'st1'))));
      await shot(t, 'g41_01_day_orders', tn);
    });

    testWidgets('G4.5 phone ($tn)', (t) async {
      // checkout: the modifier sheet and the price book picker
      var repo = fresh();
      final home = PosHomeController(posRepository: repo);
      home.priceBooks.assignAll(_books().books);
      final latte = _latte();
      await show(t, Scaffold(body: PosModifierSheet(product: latte, variant: latte.defaultVariant!, groups: _groups().of('p1'), controller: home)));
      await tap(t, 'mod_gSize_lg');
      await tap(t, 'mod_gAdd_shot');
      await shot(t, 'g45_01_modifier_sheet', tn);
      await show(t, Scaffold(body: Align(alignment: Alignment.bottomCenter, child: PriceBookSheet(c: home))));
      await shot(t, 'g45_02_price_book_picker', tn);

      // products & pricing admin
      repo = fresh();
      when(() => repo.getModifierGroups('st1', all: any(named: 'all'))).thenAnswer((_) async => _groups());
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => _books());
      when(() => repo.getProducts(any(), page: any(named: 'page'), limit: any(named: 'limit'))).thenAnswer(
        (_) async => (items: [_latte(), PosProductModel(productId: 'p2', name: 'Basmati rice 5kg', type: 'physical', categoryId: '', variants: const [PosProductVariant(variantId: 'v2', sku: 'RICE5', price: 1500, stock: 40, isDefault: true)])], total: 2, totalPages: 1, hasMore: false),
      );
      when(() => repo.getCatalogCategories('st1')).thenAnswer(
        (_) async => [for (final (i, n, c) in [(1, 'Hot drinks', 12), (2, 'Groceries', 148), (3, 'Bakery', 23), (4, 'Seasonal', 0)]) CatalogCategory(id: 'c$i', name: n, products: c)],
      );
      await show(t, const CatalogAdminHubView());
      await shot(t, 'g45_03_products_pricing_hub', tn);
      final mods = put(ModifierGroupsController(repository: repo, storeId: 'st1'));
      await show(t, ModifierGroupsView(controller: mods));
      await shot(t, 'g45_04_modifier_groups', tn);
      await show(t, ModifierGroupEditorView(controller: mods, group: _groups().groups.first));
      await shot(t, 'g45_05_modifier_group_editor', tn);
      final books = put(PriceBooksController(repository: repo, storeId: 'st1', clock: () => DateTime.utc(2026, 11, 11, 12)));
      await show(t, PriceBooksView(controller: books));
      await shot(t, 'g45_06_price_books', tn);
      await show(t, PriceBookEditorView(controller: books, book: _books().books.first));
      await shot(t, 'g45_07_price_book_editor', tn);
      await show(t, NewProductView(controller: put(NewProductController(repository: repo, storeId: 'st1'))));
      await shot(t, 'g45_08_new_product', tn);
      await show(t, CatalogCategoriesView(controller: put(CatalogCategoriesController(repository: repo, storeId: 'st1'))));
      await shot(t, 'g45_09_categories', tn);
      when(() => repo.importCatalogCsv('st1', kind: any(named: 'kind'), csv: any(named: 'csv'))).thenAnswer(
        (_) async => (
          success: true,
          code: null,
          message: null,
          data: ImportReport.fromJson({
            'total': 42,
            'created': 30,
            'updated': 9,
            'skipped': 1,
            'failedCount': 2,
            'failed': [
              {'row': 14, 'error': 'Price is required'},
              {'row': 31, 'error': 'SKU "RICE5" is already used'},
            ],
          }),
        ),
      );
      final imp = put(CsvImportController(repository: repo, storeId: 'st1'));
      await show(t, CsvImportView(controller: imp));
      await t.enterText(find.byKey(const Key('importText')), 'name,price,sku\nLatte,550,LAT\n');
      await tap(t, 'importSubmit');
      await shot(t, 'g45_10_csv_import_report', tn);
    });

    testWidgets('G4.6 phone ($tn)', (t) async {
      // open shift: the last close and the notes & coins counter
      var repo = fresh();
      when(() => repo.getLastClose('st1', 'r1')).thenAnswer(
        (_) async => LastClose.fromJson({
          'currency': 'PKR',
          'currencyExponent': 2,
          'lastClose': {'closedAt': '2026-11-10T17:05:00Z', 'closedByName': 'Bilal', 'countedMinor': 4980000, 'expectedMinor': 5000000, 'varianceMinor': -20000},
        }),
      );
      final open = PosOpenRegisterController(posRepository: repo)
        ..employee = PosEmployeeModel(id: 'e1', storeId: 'st1', sellerId: 's', name: 'Ayesha', email: 'a@x', role: 'cashier', shiftIds: const ['sh1'], status: 'active', createdAt: DateTime(2026))
        ..registerId = 'r1'
        ..registerName = 'Front counter'
        ..storeId = 'st1';
      Get.put(open);
      await show(t, PosOpenRegisterView());
      await shot(t, 'g46_01_open_shift_last_close', tn);
      await show(t, const Scaffold(body: Align(alignment: Alignment.bottomCenter, child: DenominationSheet(currency: 'PKR', exponent: 2, title: 'Count the float', initial: [(valueMinor: 500000, count: 1), (valueMinor: 100000, count: 4), (valueMinor: 50000, count: 2), (valueMinor: 10000, count: 5)]))));
      await shot(t, 'g46_02_notes_and_coins', tn);

      // transfers
      repo = fresh();
      when(() => repo.getTransfers('st1', status: 'all')).thenAnswer(
        (_) async => [
          for (final (i, s, q, r) in [(1, 'in_transit', 24, 0), (2, 'partially_received', 10, 6), (3, 'received', 5, 5)])
            StockTransfer.fromJson({'_id': 't$i', 'productName': ['Basmati rice 5kg', 'Cooking oil 1L', 'Milk 1L'][i - 1], 'fromLocationName': 'Main shop', 'toLocationName': 'Warehouse', 'quantity': q, 'receivedQuantity': r, 'status': s, 'createdAt': '2026-11-10T09:00:00Z', 'transferredByName': 'Bilal'}),
        ],
      );
      await show(t, TransfersView(controller: put(TransfersController(repository: repo, storeId: 'st1', locations: (_) async => [for (final (id, n) in [('m', 'Main shop'), ('w', 'Warehouse')]) StoreLocationModel(id: id, storeId: 'st1', sellerId: 's', name: n, status: 'active', createdAt: DateTime(2026))]))));
      await shot(t, 'g46_03_transfers', tn);
      await tap(t, 'transferNew');
      await shot(t, 'g46_04_send_stock', tn);

      // expiring lots
      repo = fresh();
      when(() => repo.getExpiry('st1')).thenAnswer(
        (_) async => ExpiryBuckets.fromJson({
          'currency': 'PKR',
          'currencyExponent': 2,
          'expired': [
            {'lotId': 'l1', 'lotNumber': 'B-17', 'variantId': 'v1', 'sku': 'MILK-1', 'productName': 'Milk 1L', 'expiryDate': '2026-11-08T00:00:00Z', 'remaining': 6, 'daysLeft': -3, 'valueMinor': 120000},
          ],
          'within7': [
            {'lotId': 'l2', 'lotNumber': 'Y-02', 'variantId': 'v2', 'productName': 'Yogurt 500g', 'expiryDate': '2026-11-14T00:00:00Z', 'remaining': 12, 'daysLeft': 3, 'valueMinor': 96000},
          ],
          'within30': [
            {'lotId': 'l3', 'lotNumber': 'C-88', 'variantId': 'v3', 'productName': 'Cheese slices', 'expiryDate': '2026-12-01T00:00:00Z', 'remaining': 20, 'daysLeft': 20, 'valueMinor': 340000},
          ],
        }),
      );
      await show(t, ExpiryView(controller: put(ExpiryController(repository: repo, storeId: 'st1'))));
      await shot(t, 'g46_05_expiring_lots', tn);
      await tap(t, 'writeOff_l1');
      await shot(t, 'g46_06_write_off', tn);

      // low stock → draft PO
      repo = fresh();
      when(() => repo.getSuppliers('st1')).thenAnswer((_) async => SupplierList.fromJson({'suppliers': [for (final (i, n) in [(1, 'Rice traders'), (2, 'Dairy fresh'), (3, 'Karachi oil mills')]) {'_id': 'sup$i', 'name': n, 'status': 'active'}]}));
      await show(t, Scaffold(body: Align(alignment: Alignment.bottomCenter, child: DraftPoSheet(repository: repo, storeId: 'st1'))));
      await shot(t, 'g46_07_draft_po', tn);
    });
  }
}
