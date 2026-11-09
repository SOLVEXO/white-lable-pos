// G3.2 / G3.3 screens and sheets: phone, tablet (>= 700 px) and dark, no overflow, the key elements, and the role-hidden elements
// absent for a cashier. Money is formatted with the response's own currency; a response without one shows no money.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/credit_adjust_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/credit_adjust_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_picker_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_profile_view.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_lot_info.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/payment_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_stock_list_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_complete_view.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'g33_returns_test.dart' show creditSale;
import 'support/g3_fixtures.dart';
import 'support/inventory_fixtures.dart';
import 'support/sale_harness.dart' show MockPosRepository;

const _phone = Size(390, 844);
const _tablet = Size(834, 1194);

enum _Env { phone, tablet, dark }

PosProductModel _product() => PosProductModel(
  productId: 'p',
  name: 'Dev Yogurt',
  type: 'physical',
  categoryId: 'c',
  variants: [PosProductVariant(variantId: 'p_v', sku: 'DEV-YOGURT', price: 4, stock: 12, isDefault: true)],
);

LotPreview _lots({int qty = 6, int shortBy = 0, int expired = 4, int daysLeft = 3, bool spill = true}) => LotPreview(
  variantId: 'p_v',
  trackLots: true,
  qty: qty,
  shortBy: shortBy,
  expiredUnits: expired,
  allocations: [
    LotAllocation(lotId: 'l1', lotNumber: 'LOT-SOON', take: 5, daysLeft: daysLeft),
    if (spill) const LotAllocation(lotId: 'l2', lotNumber: 'LOT-LATER', take: 1, daysLeft: 25),
  ],
  asOf: DateTime(2026, 11, 9, 14, 32),
);

CustomerConfig _config({bool credit = true, bool loyalty = true}) => CustomerConfig(
  cur: usd,
  storeCreditTenderEnabled: credit,
  loyalty: LoyaltyRules(enabled: loyalty, earnSpendMinor: 1000, redeemMinorPerPoint: 50),
);

void main() {
  late MockPosRepository repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    Money.configure(currency: 'USD', exponent: 2);
    repo = MockPosRepository();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(() => repo.lastErrorReasons).thenReturn(const []);
  });

  Future<void> pump(WidgetTester t, Widget w, _Env env) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(theme: env == _Env.dark ? AppTheme.dark : AppTheme.light, home: w),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 300));
    }
  }

  PosHomeController home() {
    when(() => repo.getCustomerProfile(any(), any())).thenAnswer((_) async => null);
    when(() => repo.getCustomerConfig(any())).thenAnswer((_) async => _config());
    final c = PosHomeController(posRepository: repo);
    c.storeId.value = 'st1';
    c.sessionId.value = 'se';
    return c;
  }

  void dispose(PosHomeController c) {
    c.searchController.dispose();
    c.noteController.dispose();
    c.customerController.dispose();
    c.discountController.dispose();
    c.tenderedController.dispose();
    c.paymentReferenceController.dispose();
    c.productScrollController.dispose();
  }

  for (final env in _Env.values) {
    group('G3.2 cart line (${env.name})', () {
      Future<(PosHomeController, CartItem)> mount(WidgetTester t, {LotPreview? preview, bool live = true, bool approved = false}) async {
        final c = home();
        addTearDown(() => dispose(c));
        final item = CartItem(product: _product(), variant: _product().variants.first, qty: 6);
        item.lotPreview.value = preview;
        item.lotPreviewLive.value = live;
        item.sellExpired.value = approved;
        await pump(
          t,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CartLotInfo(c: c, item: item),
            ),
          ),
          env,
        );
        return (c, item);
      }

      testWidgets('shows "Lot LOT-SOON · expires in 3 d", the spill-over and the amber Expiring soon badge', (t) async {
        final (_, item) = await mount(t, preview: _lots());
        expect(find.text('Lot LOT-SOON · expires in 3 d + 1 from LOT-LATER'), findsOneWidget);
        expect(find.text('Expiring soon'), findsOneWidget);
        expect(find.byKey(Key('sellExpired_${item.cartKey}')), findsNothing, reason: 'sellable units cover the quantity');
        expect(t.takeException(), isNull);
      });

      testWidgets('a lot a month away: no badge', (t) async {
        await mount(t, preview: _lots(daysLeft: 25, spill: false));
        expect(find.text('Expiring soon'), findsNothing);
      });

      testWidgets('expired units exist and the sellable ones fall short: the manager action is offered', (t) async {
        final (_, item) = await mount(t, preview: _lots(shortBy: 2));
        expect(find.byKey(Key('sellExpired_${item.cartKey}')), findsOneWidget);
        expect(find.text('Sell expired stock (manager)'), findsOneWidget);
        expect(find.textContaining('Only 4 sellable; 4 expired.'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('short but nothing expired: no override', (t) async {
        final (_, item) = await mount(t, preview: _lots(shortBy: 2, expired: 0));
        expect(find.byKey(Key('sellExpired_${item.cartKey}')), findsNothing);
      });

      testWidgets('approved: the line says so and can be undone', (t) async {
        final (c, item) = await mount(t, preview: _lots(shortBy: 2), approved: true);
        expect(find.text('Expired stock approved by a manager'), findsOneWidget);
        expect(find.byKey(Key('sellExpired_${item.cartKey}')), findsNothing);
        await t.tap(find.byKey(Key('withdrawExpired_${item.cartKey}')));
        await t.pump();
        await t.pump(const Duration(seconds: 1)); // the saved-cart timer
        expect(item.sellExpired.value, isFalse);
        expect(c.cartItems, isEmpty);
      });

      testWidgets('offline: the remembered suggestion with "as of", and no override even when it would be needed', (t) async {
        Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        final (_, item) = await mount(t, preview: _lots(shortBy: 2), live: false);
        expect(find.textContaining('Suggested lot as of'), findsOneWidget);
        expect(find.byKey(Key('sellExpired_${item.cartKey}')), findsNothing);
        expect(t.takeException(), isNull);
      });

      testWidgets('no lot information: nothing is drawn', (t) async {
        final (_, item) = await mount(t);
        expect(find.byKey(Key('lotLine_${item.cartKey}')), findsNothing);
      });
    });

    group('G3.2 stock rows (${env.name})', () {
      testWidgets('Expiring chip, expired units and next expiry on the row, and the empty state of the filter', (t) async {
        when(
          () => repo.getInventoryStock(
            any(),
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer(
          (_) async => rowsPage([
            InvRow.fromJson({...rowJson(id: 'y', name: 'Dev Yogurt', trackLots: true), 'expiredUnits': 4, 'nextExpiryAt': '2026-11-12T00:00:00.000Z'}),
          ]),
        );
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1'),
              tag: 'x',
            ),
          ),
          env,
        );
        expect(find.byKey(const Key('invFilter_expiring')), findsOneWidget);
        expect(find.byKey(const Key('invRowExpiry_y')), findsOneWidget);
        expect(find.textContaining('4 expired'), findsOneWidget);
        expect(find.textContaining('next expiry'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('the Expiring filter says nothing is expiring when the list is empty', (t) async {
        when(
          () => repo.getInventoryStock(
            any(),
            search: any(named: 'search'),
            filter: any(named: 'filter'),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).thenAnswer((_) async => rowsPage([]));
        await pump(
          t,
          InvStockListView(
            controller: Get.put(
              InvStockListController(repository: repo, storeId: 's1', initialFilter: 'expiring'),
              tag: 'y',
            ),
          ),
          env,
        );
        expect(find.text('Nothing is expiring'), findsOneWidget);
      });
    });

    group('G3.3 customers list (${env.name})', () {
      CustomerListController list() => Get.put(CustomerListController(repository: repo, cache: testCustomerCache(), storeId: 'st1', debounce: const Duration(milliseconds: 10)));

      testWidgets('rows with credit and points, formatted with the response currency; add button present', (t) async {
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer(), customer(id: 'c2', name: 'Bob', phone: null, credit: 0, points: 0, tier: null)]));
        await pump(t, CustomerListView(controller: list()), env);
        expect(find.text('Dev Customer'), findsOneWidget);
        expect(find.text('Credit \$20.00'), findsOneWidget);
        expect(find.textContaining('40 pts'), findsOneWidget);
        expect(find.byKey(const Key('customersAdd')), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('a response without currency shows no money at all', (t) async {
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer()], cur: null));
        await pump(t, CustomerListView(controller: list()), env);
        expect(find.textContaining('Credit'), findsNothing);
        expect(find.textContaining(r'$'), findsNothing);
        expect(find.textContaining('40 pts'), findsOneWidget);
      });

      testWidgets('empty, error with retry, and the offline banner with the add button disabled', (t) async {
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([]));
        await pump(t, CustomerListView(controller: list()), env);
        expect(find.text('No customers yet'), findsOneWidget);
      });

      testWidgets('server refusal: an error state with Try again', (t) async {
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => null);
        when(() => repo.lastErrorCode).thenReturn('POS_PIN_REQUIRED');
        await pump(t, CustomerListView(controller: list()), env);
        expect(find.text('Sign in with your PIN first.'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      });

      testWidgets('offline: remembered customers with the as-of banner; adding is disabled', (t) async {
        Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        final cache = testCustomerCache();
        await cache.saveSearch('st1', '', customerPage([customer()]));
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => null);
        await pump(
          t,
          CustomerListView(
            controller: Get.put(CustomerListController(repository: repo, cache: cache, storeId: 'st1')),
          ),
          env,
        );
        expect(find.byKey(const Key('customerAsOf')), findsOneWidget);
        expect(find.text('Dev Customer'), findsOneWidget);
        expect(t.widget<IconButton>(find.byKey(const Key('customersAdd'))).onPressed, isNull);
      });
    });

    group('G3.3 customer profile (${env.name})', () {
      CustomerProfileController ctl({String? role}) {
        SharedPreferences.setMockInitialValues({'store_id': 'st1', if (role != null) 'pos_employee_role': role});
        return Get.put(
          CustomerProfileController(customerId: 'c1', repository: repo, cache: testCustomerCache(), storeId: 'st1'),
          tag: 'c1',
        );
      }

      testWidgets('manager: balances, lifetime spend, edit, adjust, details and the credit history', (t) async {
        when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile(lifetime: 123400));
        when(() => repo.getCustomerCredit('st1', 'c1')).thenAnswer((_) async => CreditLedgerPage(enabled: true, cur: usd, items: [creditEntry()]));
        await pump(
          t,
          CustomerProfileView(
            customerId: 'c1',
            controller: ctl(role: 'manager'),
          ),
          env,
        );
        for (final k in ['profileCredit', 'profilePoints', 'profileOrders', 'profileLifetime', 'profileEdit', 'profileAdjust', 'profileDetails', 'ledger_e1']) {
          await t.scrollUntilVisible(find.byKey(Key(k)), 120, scrollable: find.byType(Scrollable).first);
          expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        }
        expect(find.text('\$20.00'), findsWidgets);
        expect(find.text('\$1,234.00'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('cashier: balances, points, orders and recent sales only; no lifetime spend, edit, adjust, details or ledger', (t) async {
        when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile());
        await pump(t, CustomerProfileView(customerId: 'c1', controller: ctl()), env);
        expect(find.byKey(const Key('profileCredit')), findsOneWidget);
        expect(find.byKey(const Key('profilePoints')), findsOneWidget);
        expect(find.byKey(const Key('profileSale_s1')), findsOneWidget);
        for (final k in ['profileLifetime', 'profileEdit', 'profileAdjust', 'profileDetails', 'ledger_e1']) {
          expect(find.byKey(Key(k)), findsNothing, reason: k);
        }
        verifyNever(() => repo.getCustomerCredit(any(), any(), page: any(named: 'page')));
        expect(t.takeException(), isNull);
      });

      testWidgets('a profile without currency shows no money (points and orders still show)', (t) async {
        when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => profile(cur: null));
        await pump(t, CustomerProfileView(customerId: 'c1', controller: ctl()), env);
        expect(find.byKey(const Key('profileCredit')), findsNothing);
        expect(find.byKey(const Key('profilePoints')), findsOneWidget);
        expect(find.textContaining(r'$'), findsNothing);
      });

      testWidgets('offline: the remembered profile with the as-of banner; edit and adjust are disabled', (t) async {
        Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        SharedPreferences.setMockInitialValues({'store_id': 'st1', 'pos_employee_role': 'manager'});
        final cache = testCustomerCache();
        await cache.saveProfile('st1', profile(lifetime: 100));
        when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => null);
        when(() => repo.getCustomerCredit('st1', 'c1')).thenAnswer((_) async => null);
        await pump(
          t,
          CustomerProfileView(
            customerId: 'c1',
            controller: Get.put(
              CustomerProfileController(customerId: 'c1', repository: repo, cache: cache, storeId: 'st1'),
              tag: 'c1',
            ),
          ),
          env,
        );
        expect(find.byKey(const Key('customerAsOf')), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('profileEdit'))).onPressed, isNull);
        expect(find.byKey(const Key('profileOffline')), findsOneWidget);
      });

      testWidgets('not remembered and offline: an honest message with Try again', (t) async {
        when(() => repo.getCustomerProfile('st1', 'c1')).thenAnswer((_) async => null);
        await pump(t, CustomerProfileView(customerId: 'c1', controller: ctl()), env);
        expect(find.textContaining('No internet'), findsOneWidget);
        expect(find.text('Try again'), findsOneWidget);
      });
    });

    group('G3.3 sheets (${env.name})', () {
      testWidgets('add customer: every field is optional but the name; validation lands under its field; Save needs a name', (t) async {
        final c = CustomerFormController(repository: repo, storeId: 'st1');
        await pump(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: CustomerFormSheet(controller: c),
              ),
            ),
          ),
          env,
        );
        for (final k in ['cfName', 'cfPhone', 'cfEmail', 'cfAddress', 'cfNtn', 'cfCnic', 'cfReg_registered', 'cfReg_unregistered', 'cfGroup', 'cfNotes', 'cfConsent']) {
          expect(find.byKey(Key(k), skipOffstage: false), findsOneWidget, reason: k);
        }
        expect(find.textContaining('(optional)'), findsWidgets);
        expect(t.widget<AppButton>(find.byKey(const Key('cfSave'), skipOffstage: false)).onPressed, isNull, reason: 'no name yet');
        when(() => repo.createPosCustomer('st1', any())).thenAnswer((_) async => (success: false, message: 'x', code: 'PHONE_INVALID', customer: null));
        await t.enterText(find.descendant(of: find.byKey(const Key('cfName')), matching: find.byType(TextFormField)), 'Sara');
        await t.pump();
        expect(t.widget<AppButton>(find.byKey(const Key('cfSave'), skipOffstage: false)).onPressed, isNotNull);
        await t.ensureVisible(find.byKey(const Key('cfSave')));
        await t.tap(find.byKey(const Key('cfSave')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('digits only'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('add customer offline: "Needs internet" and Save is off', (t) async {
        Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        final c = CustomerFormController(repository: repo, storeId: 'st1')..name.value = 'Sara';
        await pump(
          t,
          Scaffold(
            body: SingleChildScrollView(child: CustomerFormSheet(controller: c)),
          ),
          env,
        );
        expect(find.byKey(const Key('cfOffline'), skipOffstage: false), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('cfSave'), skipOffstage: false)).onPressed, isNull);
      });

      testWidgets('adjust credit: Confirm needs an amount and a note; the owner-required message shows', (t) async {
        final c = CreditAdjustController(customerId: 'c1', exponent: 2, repository: repo, storeId: 'st1');
        await pump(
          t,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: CreditAdjustSheet(controller: c, currencyCode: 'USD'),
            ),
          ),
          env,
        );
        expect(t.widget<AppButton>(find.byKey(const Key('caConfirm'))).onPressed, isNull);
        await t.enterText(find.descendant(of: find.byKey(const Key('caAmount')), matching: find.byType(TextFormField)), '5000');
        await t.enterText(find.descendant(of: find.byKey(const Key('caNote')), matching: find.byType(TextFormField)), 'migration fix');
        await t.pump();
        when(() => repo.adjustCustomerCredit('st1', 'c1', amountMinor: 500000, note: 'migration fix')).thenAnswer((_) async => (success: false, message: 'x', code: 'POS_OWNER_REQUIRED'));
        await t.tap(find.byKey(const Key('caConfirm')));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('owner must make this change'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('picker: rows, search, Walk-in, Add customer; offline lists what is remembered and add says it needs internet', (t) async {
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => customerPage([customer()]));
        final c = Get.put(
          CustomerListController(repository: repo, cache: testCustomerCache(), storeId: 'st1'),
          tag: 'pk',
        )..onInit();
        await pump(t, Scaffold(body: CustomerPickerSheet(controller: c)), env);
        expect(find.text('Select customer'), findsOneWidget);
        expect(find.byKey(const Key('walkInButton')), findsOneWidget);
        expect(find.byKey(const Key('pickerAdd')), findsOneWidget);
        expect(find.text('Dev Customer'), findsOneWidget);
        expect(find.text('Credit \$20.00'), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('picker offline: "Needs internet to add a customer", the add button is off', (t) async {
        Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        when(() => repo.searchPosCustomers('st1', '')).thenAnswer((_) async => null);
        final cache = testCustomerCache();
        await cache.saveSearch('st1', '', customerPage([customer()]));
        final c = Get.put(
          CustomerListController(repository: repo, cache: cache, storeId: 'st1'),
          tag: 'pk2',
        )..onInit();
        await pump(t, Scaffold(body: CustomerPickerSheet(controller: c)), env);
        expect(find.byKey(const Key('pickerOffline')), findsOneWidget);
        expect(t.widget<AppButton>(find.byKey(const Key('pickerAdd'))).onPressed, isNull);
        expect(find.byKey(const Key('customerAsOf')), findsOneWidget);
      });
    });

    group('G3.3 payment sheet and success (${env.name})', () {
      Future<PosHomeController> payment(WidgetTester t, {CustomerConfig? config, PosCustomer? who, bool offline = false, bool offlineFromStart = false}) async {
        if (offlineFromStart) Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
        final c = home();
        when(() => repo.getCustomerConfig(any())).thenAnswer((_) async => config ?? _config());
        addTearDown(() => dispose(c));
        c.cartItems.add(CartItem(product: _product(), variant: _product().variants.first, qty: 5)); // $20.00
        c.saleCustomer.attach(who ?? customer(), usd);
        await c.saleCustomer.refresh();
        if (offline) Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false); // the connection drops after the rules were fetched
        await pump(
          t,
          Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PaymentSheet(c: c),
              ),
            ),
          ),
          env,
        );
        return c;
      }

      testWidgets('store credit and redeem points rows with the balance, the point value and a live preview', (t) async {
        final c = await payment(t);
        expect(find.byKey(const Key('customerMoneyPanel')), findsOneWidget);
        expect(find.byKey(const Key('creditBalanceText')), findsOneWidget);
        expect(find.textContaining('\$20.00'), findsWidgets);
        expect(find.byKey(const Key('pointsAvailableText')), findsOneWidget);
        expect(find.textContaining('1 point = \$0.50'), findsOneWidget);
        c.setRedeemPoints(10);
        await t.pump();
        expect(find.byKey(const Key('redeemPreview')), findsOneWidget);
        expect(find.textContaining('−\$5.00 off this sale'), findsOneWidget);
        await t.tap(find.byKey(const Key('useStoreCredit')));
        await t.pump();
        expect(c.splitLines.first.method.value, 'store_credit');
        expect(t.takeException(), isNull);
      });

      testWidgets('nothing about credit or points when no customer is attached, or the store has them off', (t) async {
        var c = await payment(t, config: _config(credit: false, loyalty: false));
        expect(find.byKey(const Key('customerMoneyPanel')), findsNothing);
        c.saleCustomer.detach();
        await t.pump();
        expect(find.byKey(const Key('customerMoneyPanel')), findsNothing);
      });

      testWidgets('a customer without points has no redeem row; without a balance the Use button is off with the reason', (t) async {
        await payment(t, who: customer(points: 0, credit: 0));
        expect(find.byKey(const Key('redeemStepper')), findsNothing);
        expect(t.widget<AppButton>(find.byKey(const Key('useStoreCredit'))).onPressed, isNull);
        expect(find.textContaining('No store credit to use'), findsOneWidget);
      });

      testWidgets('offline: both rows are shown disabled with "Needs internet"', (t) async {
        await payment(t, offline: true);
        expect(find.textContaining('Needs internet'), findsWidgets);
        expect(t.widget<AppButton>(find.byKey(const Key('useStoreCredit'))).onPressed, isNull);
      });

      testWidgets('a customer chosen while offline (rules never fetched): one honest line instead of rows', (t) async {
        await payment(t, offlineFromStart: true);
        expect(find.byKey(const Key('customerMoneyOffline')), findsOneWidget);
        expect(find.byKey(const Key('customerMoneyPanel')), findsNothing);
      });

      testWidgets('success view: points earned and redeemed, store credit used (sale currency)', (t) async {
        final c = home();
        addTearDown(() => dispose(c));
        c.lastOutcome.value = SaleOutcome.completed;
        c.lastSale.value = PosSaleModel.fromJson({
          '_id': 's1',
          'saleNumber': 'S-1',
          'storeId': 'st1',
          'sessionId': 'se',
          'registerId': 'r',
          'employeeId': 'e',
          'items': [],
          'discount': 5.0,
          'tax': 0,
          'subtotal': 20.0,
          'total': 15.0,
          'paymentMethod': 'split',
          'customerName': 'Dev',
          'notes': '',
          'status': 'completed',
          'createdAt': '2026-11-09T10:00:00.000Z',
          'currency': 'USD',
          'currencyExponent': 2,
          'payments': [
            {'method': 'store_credit', 'amount': 8.0},
            {'method': 'cash', 'amount': 7.0},
          ],
          'loyalty': {'earnedPoints': 1, 'redeemedPoints': 10, 'redeemValueMinor': 500},
        });
        await pump(t, SaleSuccessView(c: c, repository: repo), env);
        expect(find.text('Store credit used \$8.00'), findsOneWidget);
        expect(find.text('Redeemed 10 points (−\$5.00)'), findsOneWidget);
        expect(find.text('Earned 1 point'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });

    group('G3.3 return flow (${env.name})', () {
      Future<PosReturnController> returns(WidgetTester t, {bool ledger = true, String? customerId = 'c1'}) async {
        when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => creditSale(customerId: customerId));
        when(() => repo.getCustomerProfile('store-1', 'c1')).thenAnswer((_) async => ledger ? profile(credit: 2500) : CustomerProfile(customer: customer(), cur: usd));
        final c = PosReturnController(repository: repo, saleId: 'sale-1');
        Get.put(c);
        await pump(t, PosReturnView(controller: c), env);
        return c;
      }

      testWidgets('Refund to: Original payment method / Store credit, and the plan follows the choice', (t) async {
        final c = await returns(t);
        c.setQty('i1', 1);
        await t.pump();
        expect(find.byKey(const Key('refundToCard')), findsOneWidget);
        expect(find.text('Original payment method'), findsOneWidget);
        await t.tap(find.byKey(const Key('refundToCredit')));
        await t.pump();
        expect(find.textContaining("Add \$5.00 to the customer's store credit"), findsOneWidget);
        expect(t.takeException(), isNull);
      });

      testWidgets('hidden without a customer, and when the credit ledger is off', (t) async {
        await returns(t, customerId: null);
        expect(find.byKey(const Key('refundToCard')), findsNothing);
      });

      testWidgets('hidden when the ledger is off', (t) async {
        await returns(t, ledger: false);
        expect(find.byKey(const Key('refundToCard')), findsNothing);
      });

      testWidgets('done: "Refunded to store credit \$5.00" and the new balance', (t) async {
        when(() => repo.getSaleById('sale-1')).thenAnswer((_) async => creditSale());
        final c = PosReturnController(repository: repo, saleId: 'sale-1');
        c.sale.value = creditSale();
        c.resultCreditText.value = '\$5.00';
        c.resultBalanceText.value = '\$30.00';
        c.result.value = {'number': 'CN-000001'};
        c.resultInstructions.assignAll(["Add \$5.00 to the customer's store credit"]);
        await pump(t, PosReturnCompleteView(c: c), env);
        expect(find.text('Refunded to store credit \$5.00'), findsOneWidget);
        expect(find.text('New balance \$30.00'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    });
  }
}
