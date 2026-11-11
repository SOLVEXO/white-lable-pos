// G4.5 products & pricing admin: the hub, modifier groups, price books (+ assign to a customer), new product (+ add / archive variant),
// categories and CSV import. Controllers and screens over a mocked repository; phone, tablet and dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:responsive_sizer/responsive_sizer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_common.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/controllers/catalog_admin_controllers.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/catalog_admin_hub_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/categories_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/csv_import_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/modifier_groups_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/new_product_view.dart';
import 'package:solvexo_pos/app/modules/pos_catalog_admin/views/price_books_view.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _Repo extends Mock implements PosRepository {}

const _phone = Size(390, 1600);
const _tablet = Size(1024, 1366);

enum _Env { phone, tablet, dark }

typedef _ModRes = ({bool success, String? code, String? message, ModifierGroup? data});
typedef _BookRes = ({bool success, String? code, String? message, PriceBook? data});
typedef _AssignRes = ({bool success, String? code, String? message, String? data});
typedef _CatRes = ({bool success, String? code, String? message, List<CatalogCategory>? data});
typedef _ProdRes = ({bool success, String? code, String? message, CatalogProduct? data});
typedef _ImpRes = ({bool success, String? code, String? message, ImportReport? data});

ModifierGroups _groups({String currency = 'PKR', int exp = 2, List<Map<String, dynamic>>? groups}) => ModifierGroups.fromJson({
  'currency': currency,
  'currencyExponent': exp,
  'groups':
      groups ??
      [
        {
          'id': 'g1',
          'name': 'Size',
          'minSelect': 1,
          'maxSelect': 1,
          'productIds': ['p1'],
          'options': [
            {'id': 'o1', 'name': 'Small', 'priceDeltaMinor': -50},
            {'id': 'o2', 'name': 'Large', 'priceDeltaMinor': 150},
          ],
        },
        {
          'id': 'g2',
          'name': 'Extras',
          'minSelect': 0,
          'maxSelect': 2,
          'active': false,
          'options': [
            {'id': 'o3', 'name': 'Cheese', 'priceDeltaMinor': 100, 'active': false},
          ],
        },
      ],
});

PosProductModel _product(String id, String name, List<(String, String, double)> variants) => PosProductModel.fromJson({
  'productId': id,
  'name': name,
  'categoryId': '',
  'variants': [
    for (final v in variants)
      {
        'variantId': v.$1,
        'sku': 'SKU-${v.$1}',
        'price': v.$3,
        'stock': 5,
        'options': [
          if (v.$2.isNotEmpty) {'name': 'Size', 'value': v.$2},
        ],
      },
  ],
});

final _tea = _product('p1', 'Tea', [('v1', 'Small', 2.0), ('v2', 'Large', 3.5)]);
final _cake = _product('p2', 'Cake', [('v3', '', 4.0)]);

PriceBooks _books() => PriceBooks.fromJson({
  'currency': 'PKR',
  'currencyExponent': 2,
  'books': [
    {
      'id': 'b1',
      'name': 'Wholesale',
      'inForce': true,
      'entries': [
        {'variantId': 'v1', 'priceMinor': 180},
      ],
    },
    {'id': 'b2', 'name': 'Christmas', 'inForce': false, 'startsAt': '2026-12-20T00:00:00.000Z', 'endsAt': '2026-12-27T00:00:00.000Z'},
    {'id': 'b3', 'name': 'Summer', 'inForce': false, 'startsAt': '2026-06-01T00:00:00.000Z', 'endsAt': '2026-09-01T00:00:00.000Z'},
    {'id': 'b4', 'name': 'Staff', 'active': false, 'inForce': false},
  ],
});

List<CatalogCategory> _cats([List<(String, String, int)>? rows]) => [
  for (final r in rows ?? [('c1', 'Drinks', 3), ('c2', 'Bakery', 0)]) CatalogCategory.fromJson({'id': r.$1, 'name': r.$2, 'products': r.$3}),
];

CatalogProduct _made({List<Map<String, dynamic>>? variants}) => CatalogProduct.fromJson({
  'currency': 'PKR',
  'currencyExponent': 2,
  'product': {
    'id': 'np1',
    'name': 'Juice',
    'categoryId': 'c1',
    'status': 'active',
    'variants':
        variants ??
        [
          {
            'id': 'nv1',
            'sku': 'J-1',
            'priceMinor': 25000,
            'costMinor': 12000,
            'stock': 4,
            'options': [
              {'name': 'Size', 'value': 'Small'},
            ],
          },
          {
            'id': 'nv2',
            'sku': 'J-2',
            'priceMinor': 40000,
            'stock': 0,
            'options': [
              {'name': 'Size', 'value': 'Large'},
            ],
          },
        ],
  },
});

PosCustomer _customer(String id, String name) => PosCustomer.fromJson({'id': id, 'kind': 'pos', 'name': name, 'phone': '0300-1234567'});

void main() {
  late _Repo repo;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    Get.testMode = true;
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(const ModifierGroup(id: '', name: ''));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'store_id': 'st1'});
    Get.reset();
    repo = _Repo();
    when(() => repo.lastErrorCode).thenReturn(null);
    when(
      () => repo.getProducts(
        any(),
        page: any(named: 'page'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => (items: [_tea, _cake], total: 2, totalPages: 1, hasMore: false));
    when(
      () => repo.searchProducts(
        storeId: any(named: 'storeId'),
        q: any(named: 'q'),
      ),
    ).thenAnswer((_) async => [_tea, _cake]);
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pump(WidgetTester t, Widget w, [_Env env = _Env.phone]) async {
    t.view.physicalSize = env == _Env.tablet ? _tablet : _phone;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ResponsiveSizer(
        builder: (_, __, ___) => GetMaterialApp(
          key: UniqueKey(),
          theme: env == _Env.dark ? AppTheme.dark : AppTheme.light,
          getPages: [
            GetPage(
              name: Routes.posCatalogNewProduct,
              page: () => const Scaffold(body: Text('NEWPRODUCT')),
            ),
            GetPage(
              name: Routes.posCatalogCategories,
              page: () => const Scaffold(body: Text('CATEGORIES')),
            ),
            GetPage(
              name: Routes.posCatalogImport,
              page: () => const Scaffold(body: Text('IMPORT')),
            ),
            GetPage(
              name: Routes.posModifierGroups,
              page: () => const Scaffold(body: Text('MODIFIERS')),
            ),
            GetPage(
              name: Routes.posPriceBooks,
              page: () => const Scaffold(body: Text('PRICEBOOKS')),
            ),
          ],
          home: w,
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tapKey(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump(); // lay out at the new scroll offset before tapping
    await t.tap(f);
    await settle(t);
  }

  Future<void> typeKey(WidgetTester t, String key, String text) async {
    final f = find.byKey(Key(key));
    await t.ensureVisible(f);
    await t.pump();
    await t.enterText(f, text);
    await t.pump();
  }

  void offline() => Get.put<NetworkStatusService>(NetworkStatusService()..isOnline.value = false);
  String tag() => 't${DateTime.now().microsecondsSinceEpoch}';

  // ── helpers ──────────────────────────────────────────────────────────────────────────────
  group('money input and book states', () {
    test('major → minor at the response exponent; ± allowed; too many decimals or junk refused', () {
      expect(catParseMajor('12.5', 2), 1250);
      expect(catParseMajor('-0.50', 2), -50);
      expect(catParseMajor('+1', 2), 100);
      expect(catParseMajor('1,250.75', 2), 125075);
      expect(catParseMajor('1.234', 3), 1234);
      expect(catParseMajor('150', 0), 150);
      expect(catParseMajor('1.5', 0), isNull);
      expect(catParseMajor('1.555', 2), isNull);
      expect(catParseMajor('abc', 2), isNull);
      expect(catParseMajor('', 2), isNull);
      expect(catParseMajor('.', 2), isNull);
      expect(catMajorText(-50, 2), '-0.50');
      expect(catMajorText(1234, 3), '1.234');
    });

    test('in force / scheduled / ended / off', () {
      final now = DateTime.utc(2026, 11, 10, 12);
      final b = _books().books;
      expect([for (final x in b) BookState.of(x, now)], [BookState.inForce, BookState.scheduled, BookState.ended, BookState.off]);
    });
  });

  // ── hub ──────────────────────────────────────────────────────────────────────────────────
  group('hub', () {
    for (final env in _Env.values) {
      testWidgets('${env.name}: every screen is listed and opens', (t) async {
        await pump(t, const CatalogAdminHubView(), env);
        for (final k in ['hubNewProduct', 'hubCategories', 'hubImport', 'hubModifiers', 'hubPriceBooks']) {
          expect(find.byKey(Key(k)), findsOneWidget);
        }
        expect(t.takeException(), isNull);
        await tapKey(t, 'hubPriceBooks');
        expect(find.text('PRICEBOOKS'), findsOneWidget);
      });
    }
  });

  // ── modifier groups ──────────────────────────────────────────────────────────────────────
  group('modifier groups', () {
    ModifierGroupsController ctl() => Get.put(
      ModifierGroupsController(repository: repo, storeId: 'st1'),
      tag: tag(),
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: every group (inactive too) with its rule and signed price changes', (t) async {
        when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups());
        await pump(t, ModifierGroupsView(controller: ctl()), env);
        verify(() => repo.getModifierGroups('st1', all: true)).called(1);
        expect(find.byKey(const Key('mod_g1')), findsOneWidget);
        expect(find.byKey(const Key('mod_g2')), findsOneWidget);
        expect(find.text('Off'), findsOneWidget);
        expect(find.textContaining('Choose 1'), findsOneWidget);
        expect(find.textContaining('Small -Rs0.50'), findsOneWidget);
        expect(find.textContaining('Large +Rs1.50'), findsOneWidget);
        expect(find.textContaining('Cheese +Rs1.00 (off)'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('no groups yet: the empty state', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups(groups: const []));
      await pump(t, ModifierGroupsView(controller: ctl()));
      expect(find.byKey(const Key('catEmpty')), findsOneWidget);
    });

    testWidgets('a failed read says so and Try again reads again', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => null);
      await pump(t, ModifierGroupsView(controller: ctl()));
      expect(find.textContaining('Could not load the modifier groups'), findsOneWidget);
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups());
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.byKey(const Key('mod_g1')), findsOneWidget);
    });

    testWidgets('offline with nothing read: needs internet, nothing is asked', (t) async {
      offline();
      await pump(t, ModifierGroupsView(controller: ctl()));
      expect(find.byKey(const Key('reportsNeedsInternet')), findsOneWidget);
      verifyNever(() => repo.getModifierGroups(any(), all: any(named: 'all')));
    });

    testWidgets('new group: name, choices, a negative price change, attached product → saved and listed', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups(groups: const []));
      when(() => repo.saveModifierGroup('st1', any())).thenAnswer(
        (_) async =>
            (
                  success: true,
                  code: null,
                  message: null,
                  data: ModifierGroup.fromJson({
                    'id': 'g9',
                    'name': 'Milk',
                    'minSelect': 0,
                    'maxSelect': 1,
                    'productIds': ['p1'],
                    'options': [
                      {'id': 'o9', 'name': 'Oat', 'priceDeltaMinor': -25},
                    ],
                  }),
                )
                as _ModRes,
      );
      final c = ctl();
      await pump(t, ModifierGroupsView(controller: c));
      await tapKey(t, 'modNew');
      expect(find.byKey(const Key('modEditor')), findsOneWidget);
      await typeKey(t, 'modName', 'Milk');
      await typeKey(t, 'modOptName_0', 'Oat');
      await typeKey(t, 'modOptPrice_0', '-0.25');
      await tapKey(t, 'modAttach');
      await t.enterText(find.byKey(const Key('catSearchField')), 'tea');
      await settle(t);
      await tapKey(t, 'pickProduct_p1');
      expect(find.byKey(const Key('modProduct_p1')), findsOneWidget);
      expect(find.text('Tea'), findsOneWidget);
      await tapKey(t, 'modSaveBottom');
      final g = verify(() => repo.saveModifierGroup('st1', captureAny())).captured.single as ModifierGroup;
      expect(g.toWrite(), {
        'name': 'Milk',
        'minSelect': 0,
        'maxSelect': 1,
        'productIds': ['p1'],
        'active': true,
        'options': [
          {'name': 'Oat', 'priceDeltaMinor': -25, 'active': true},
        ],
      });
      expect(find.byKey(const Key('modEditor')), findsNothing);
      expect(find.byKey(const Key('mod_g9')), findsOneWidget);
      expect(find.byKey(const Key('catNotice')), findsOneWidget);
    });

    testWidgets('editing keeps option ids; prices use the response exponent (KWD, 3 decimals); a bad amount is not sent', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups(currency: 'KWD', exp: 3));
      when(() => repo.saveModifierGroup('st1', any())).thenAnswer((i) async => (success: true, code: null, message: null, data: i.positionalArguments[1] as ModifierGroup) as _ModRes);
      await pump(t, ModifierGroupsView(controller: ctl()));
      await tapKey(t, 'mod_g1');
      expect(find.widgetWithText(TextField, '-0.050'), findsOneWidget);
      await typeKey(t, 'modOptPrice_1', '1.2345');
      await tapKey(t, 'modSaveBottom');
      expect(find.text('Enter an amount with at most 3 decimals.'), findsOneWidget);
      verifyNever(() => repo.saveModifierGroup(any(), any()));
      await typeKey(t, 'modOptPrice_1', '1.25');
      await tapKey(t, 'modOptActive_0');
      await tapKey(t, 'modSaveBottom');
      final g = verify(() => repo.saveModifierGroup('st1', captureAny())).captured.single as ModifierGroup;
      expect(g.toWrite()['options'], [
        {'id': 'o1', 'name': 'Small', 'priceDeltaMinor': -50, 'active': false},
        {'id': 'o2', 'name': 'Large', 'priceDeltaMinor': 1250, 'active': true},
      ]);
    });

    testWidgets('the server\'s refusals in words: a role that may not edit, a bad group', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups());
      when(() => repo.saveModifierGroup('st1', any())).thenAnswer((_) async => (success: false, code: 'POS_ACTION_FORBIDDEN', message: 'x', data: null) as _ModRes);
      final c = ctl();
      await pump(t, ModifierGroupsView(controller: c));
      await tapKey(t, 'mod_g1');
      await tapKey(t, 'modSaveBottom');
      expect(find.byKey(const Key('catForbidden')), findsOneWidget);
      expect(find.text('Your role cannot do this. Ask a manager.'), findsOneWidget);
      expect(find.byKey(const Key('modEditor')), findsOneWidget);
      when(() => repo.saveModifierGroup('st1', any())).thenAnswer((_) async => (success: false, code: 'INVALID_GROUP', message: 'minSelect cannot be more than maxSelect', data: null) as _ModRes);
      c.forbidden.value = false;
      await tapKey(t, 'modSaveBottom');
      expect(find.text('minSelect cannot be more than maxSelect'), findsOneWidget);
    });

    testWidgets('saving offline says it needs internet and sends nothing', (t) async {
      when(() => repo.getModifierGroups('st1', all: true)).thenAnswer((_) async => _groups());
      final c = ctl();
      await pump(t, ModifierGroupsView(controller: c));
      await tapKey(t, 'mod_g1');
      offline();
      await settle(t);
      await tapKey(t, 'modSaveBottom');
      expect(find.text('Saving a modifier group needs an internet connection.'), findsOneWidget);
      verifyNever(() => repo.saveModifierGroup(any(), any()));
    });
  });

  // ── price books ──────────────────────────────────────────────────────────────────────────
  group('price books', () {
    PriceBooksController ctl() => Get.put(
      PriceBooksController(repository: repo, storeId: 'st1', clock: () => DateTime.utc(2026, 11, 10, 12)),
      tag: tag(),
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: in force / scheduled / ended / off', (t) async {
        when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => _books());
        await pump(t, PriceBooksView(controller: ctl()), env);
        for (final (id, label) in [('b1', 'In force'), ('b2', 'Scheduled'), ('b3', 'Ended'), ('b4', 'Off')]) {
          expect(find.descendant(of: find.byKey(Key('bookState_$id')), matching: find.text(label)), findsOneWidget);
        }
        expect(find.textContaining('Until the end of 26 Dec 2026'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('no books yet: the empty state', (t) async {
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => PriceBooks.fromJson({'currency': 'PKR', 'books': []}));
      await pump(t, PriceBooksView(controller: ctl()));
      expect(find.byKey(const Key('catEmpty')), findsOneWidget);
    });

    testWidgets('a refused read is in words', (t) async {
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => null);
      when(() => repo.lastErrorCode).thenReturn('POS_ACTION_FORBIDDEN');
      await pump(t, PriceBooksView(controller: ctl()));
      expect(find.text('Your role cannot do this. Ask a manager.'), findsOneWidget);
    });

    testWidgets('edit: entries named from the product list, a price changed, a variant added, saved with minor units', (t) async {
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => _books());
      when(() => repo.savePriceBook('st1', any(), id: 'b1')).thenAnswer((_) async => (success: true, code: null, message: null, data: _books().books.first) as _BookRes);
      await pump(t, PriceBooksView(controller: ctl()));
      await tapKey(t, 'book_b1');
      expect(find.text('Tea · Small'), findsOneWidget);
      expect(find.widgetWithText(TextField, '1.80'), findsOneWidget);
      await typeKey(t, 'bookPrice_v1', '1.75');
      await tapKey(t, 'bookAddEntry');
      await t.enterText(find.byKey(const Key('catSearchField')), 'cake');
      await settle(t);
      await tapKey(t, 'pickVariant_v3');
      await typeKey(t, 'bookPrice_v3', '3');
      await typeKey(t, 'bookNote', 'Trade customers');
      await tapKey(t, 'bookSaveBottom');
      final body = verify(() => repo.savePriceBook('st1', captureAny(), id: 'b1')).captured.single as Map<String, dynamic>;
      expect(body['name'], 'Wholesale');
      expect(body['note'], 'Trade customers');
      expect(body['startsAt'], isNull);
      expect(body['entries'], [
        {'variantId': 'v1', 'priceMinor': 175},
        {'variantId': 'v3', 'priceMinor': 300},
      ]);
      expect(find.byKey(const Key('bookEditor')), findsNothing);
      verify(() => repo.getPriceBooks('st1')).called(2);
    });

    testWidgets('dates are kept and cleared; INVALID_DATE in words', (t) async {
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => _books());
      when(() => repo.savePriceBook('st1', any(), id: 'b2')).thenAnswer((_) async => (success: false, code: 'INVALID_DATE', message: 'The end must be after the start', data: null) as _BookRes);
      await pump(t, PriceBooksView(controller: ctl()));
      await tapKey(t, 'book_b2');
      await tapKey(t, 'bookSaveBottom');
      var body = verify(() => repo.savePriceBook('st1', captureAny(), id: 'b2')).captured.single as Map<String, dynamic>;
      expect([body['startsAt'], body['endsAt']], ['2026-12-20T00:00:00.000Z', '2026-12-27T00:00:00.000Z']);
      expect(find.text('The end must be after the start'), findsOneWidget);
      await tapKey(t, 'bookEndsClear');
      await tapKey(t, 'bookSaveBottom');
      body = verify(() => repo.savePriceBook('st1', captureAny(), id: 'b2')).captured.single as Map<String, dynamic>;
      expect(body['endsAt'], isNull);
    });

    testWidgets('assign a book to a customer, then clear it', (t) async {
      when(() => repo.getPriceBooks('st1')).thenAnswer((_) async => _books());
      when(() => repo.searchPosCustomers('st1', any())).thenAnswer((_) async => PosCustomerPage(items: [_customer('cu1', 'Bilal')]));
      when(() => repo.assignPriceBook('st1', 'cu1', any())).thenAnswer((_) async => (success: true, code: null, message: null, data: null) as _AssignRes);
      await pump(t, PriceBooksView(controller: ctl()));
      await tapKey(t, 'bookAssign');
      expect(t.widget<AppButton>(find.byKey(const Key('assignSave'))).onPressed, isNull);
      await tapKey(t, 'assignCustomer');
      await tapKey(t, 'pickCustomer_cu1');
      expect(find.text('Bilal'), findsOneWidget);
      await tapKey(t, 'assignBook_b1');
      await tapKey(t, 'assignSave');
      verify(() => repo.assignPriceBook('st1', 'cu1', 'b1')).called(1);
      expect(find.text('Bilal now gets "Wholesale".'), findsOneWidget);
      await tapKey(t, 'assignNone');
      await tapKey(t, 'assignSave');
      verify(() => repo.assignPriceBook('st1', 'cu1', null)).called(1);
      expect(find.text('Bilal now pays the normal prices.'), findsOneWidget);
    });
  });

  // ── new product ──────────────────────────────────────────────────────────────────────────
  group('new product', () {
    NewProductController ctl() => Get.put(
      NewProductController(repository: repo, storeId: 'st1'),
      tag: tag(),
    );
    void stubReads() {
      when(() => repo.getCatalogCategories('st1')).thenAnswer((_) async => _cats());
      when(() => repo.getModifierGroups('st1')).thenAnswer((_) async => _groups(groups: const []));
    }

    for (final env in _Env.values) {
      testWidgets('${env.name}: the form with the categories and the store currency', (t) async {
        stubReads();
        await pump(t, NewProductView(controller: ctl()), env);
        expect(find.byKey(const Key('prodName')), findsOneWidget);
        expect(find.byKey(const Key('prodCategory')), findsOneWidget);
        expect(find.text('PKR '), findsWidgets);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('offline: needs internet', (t) async {
      offline();
      await pump(t, NewProductView(controller: ctl()));
      expect(find.byKey(const Key('reportsNeedsInternet')), findsOneWidget);
    });

    testWidgets('two variants with attributes → the body in minor units, then the created product', (t) async {
      stubReads();
      when(() => repo.createCatalogProduct('st1', any())).thenAnswer((_) async => (success: true, code: null, message: null, data: _made()) as _ProdRes);
      await pump(t, NewProductView(controller: ctl()));
      await typeKey(t, 'prodName', 'Juice');
      await tapKey(t, 'prodCategory');
      await t.tap(find.text('Drinks').last);
      await settle(t);
      await tapKey(t, 'varAddOption_0');
      await typeKey(t, 'varOptName_0_0', 'Size');
      await typeKey(t, 'varOptValue_0_0', 'Small');
      await typeKey(t, 'varPrice_0', '250');
      await typeKey(t, 'varCost_0', '120');
      await typeKey(t, 'varStock_0', '4');
      await tapKey(t, 'varLots_0');
      await tapKey(t, 'prodAddVariant');
      expect(find.widgetWithText(TextField, 'Size'), findsNWidgets(2));
      await typeKey(t, 'varOptValue_1_0', 'Large');
      await typeKey(t, 'varPrice_1', 'x');
      await tapKey(t, 'prodCreate');
      expect(find.text('Enter an amount with at most 2 decimals.'), findsOneWidget);
      verifyNever(() => repo.createCatalogProduct(any(), any()));
      await typeKey(t, 'varPrice_1', '400');
      await typeKey(t, 'varSku_1', 'J-2');
      await tapKey(t, 'prodCreate');
      final body = verify(() => repo.createCatalogProduct('st1', captureAny())).captured.single as Map<String, dynamic>;
      expect(body, {
        'name': 'Juice',
        'categoryId': 'c1',
        'variants': [
          {
            'priceMinor': 25000,
            'costMinor': 12000,
            'stock': 4,
            'trackLots': true,
            'options': [
              {'name': 'Size', 'value': 'Small'},
            ],
          },
          {
            'priceMinor': 40000,
            'sku': 'J-2',
            'trackLots': false,
            'options': [
              {'name': 'Size', 'value': 'Large'},
            ],
          },
        ],
      });
      expect(find.byKey(const Key('prodCreated')), findsOneWidget);
      expect(find.textContaining('Drinks'), findsOneWidget);
      expect(find.byKey(const Key('prodVariant_nv1')), findsOneWidget);
      expect(find.text('Rs250.00'), findsOneWidget);
    });

    testWidgets('a refused create (SKU taken) is in words and keeps the form', (t) async {
      stubReads();
      when(() => repo.createCatalogProduct('st1', any())).thenAnswer((_) async => (success: false, code: 'SKU_TAKEN', message: 'SKU "J-1" is already used', data: null) as _ProdRes);
      await pump(t, NewProductView(controller: ctl()));
      await typeKey(t, 'prodName', 'Juice');
      await typeKey(t, 'varPrice_0', '1');
      await tapKey(t, 'prodCreate');
      expect(find.text('SKU "J-1" is already used'), findsOneWidget);
      expect(find.byKey(const Key('prodName')), findsOneWidget);
    });

    testWidgets('after the create: add a variant (attribute names locked), archive one, LAST_VARIANT in words', (t) async {
      stubReads();
      final c = ctl();
      await pump(t, NewProductView(controller: c));
      c.product.value = _made();
      await settle(t);
      when(() => repo.addCatalogVariant('st1', 'np1', any())).thenAnswer(
        (_) async =>
            (
                  success: true,
                  code: null,
                  message: null,
                  data: _made(
                    variants: [
                      ..._made().variants.map(
                        (v) => {
                          'id': v.id,
                          'sku': v.sku,
                          'priceMinor': v.priceMinor,
                          'options': [
                            for (final o in v.options) {'name': o.name, 'value': o.value},
                          ],
                        },
                      ),
                      {
                        'id': 'nv3',
                        'sku': 'J-3',
                        'priceMinor': 50000,
                        'options': [
                          {'name': 'Size', 'value': 'Jumbo'},
                        ],
                      },
                    ],
                  ),
                )
                as _ProdRes,
      );
      await tapKey(t, 'prodAddVariantAfter');
      final name = t.widget<TextField>(find.byKey(const Key('varOptName_99_0')));
      expect([name.controller!.text, name.enabled], ['Size', false]);
      await typeKey(t, 'varOptValue_99_0', 'Jumbo');
      await typeKey(t, 'varPrice_99', '500');
      await tapKey(t, 'varSave');
      final body = verify(() => repo.addCatalogVariant('st1', 'np1', captureAny())).captured.single as Map<String, dynamic>;
      expect(body['priceMinor'], 50000);
      expect(body['options'], [
        {'name': 'Size', 'value': 'Jumbo'},
      ]);
      expect(find.byKey(const Key('prodVariant_nv3')), findsOneWidget);

      when(() => repo.archiveCatalogVariant('st1', 'np1', 'nv1')).thenAnswer((_) async => (success: false, code: 'LAST_VARIANT', message: 'x', data: null) as _ProdRes);
      await tapKey(t, 'prodArchive_nv1');
      await t.tap(find.text('Archive').last);
      await settle(t);
      verify(() => repo.archiveCatalogVariant('st1', 'np1', 'nv1')).called(1);
      expect(find.text('A product needs at least one active variant.'), findsOneWidget);
    });
  });

  // ── categories ───────────────────────────────────────────────────────────────────────────
  group('categories', () {
    CatalogCategoriesController ctl() => Get.put(
      CatalogCategoriesController(repository: repo, storeId: 'st1'),
      tag: tag(),
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: each with its product count', (t) async {
        when(() => repo.getCatalogCategories('st1')).thenAnswer((_) async => _cats());
        await pump(t, CatalogCategoriesView(controller: ctl()), env);
        expect(t.widget<Text>(find.byKey(const Key('catCount_c1'))).data, '3 products');
        expect(find.text('0 products'), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('empty; a failed read with Try again', (t) async {
      when(() => repo.getCatalogCategories('st1')).thenAnswer((_) async => null);
      await pump(t, CatalogCategoriesView(controller: ctl()));
      expect(find.textContaining('Could not load the categories'), findsOneWidget);
      when(() => repo.getCatalogCategories('st1')).thenAnswer((_) async => const []);
      await t.tap(find.text('Try again'));
      await settle(t);
      expect(find.byKey(const Key('catEmpty')), findsOneWidget);
    });

    testWidgets('add, rename, and a delete the server refuses (still has products)', (t) async {
      when(() => repo.getCatalogCategories('st1')).thenAnswer((_) async => _cats());
      when(
        () => repo.createCatalogCategory('st1', 'Snacks'),
      ).thenAnswer((_) async => (success: true, code: null, message: null, data: _cats([('c1', 'Drinks', 3), ('c2', 'Bakery', 0), ('c3', 'Snacks', 0)])) as _CatRes);
      when(
        () => repo.updateCatalogCategory('st1', 'c2', name: 'Bread'),
      ).thenAnswer((_) async => (success: true, code: null, message: null, data: _cats([('c1', 'Drinks', 3), ('c2', 'Bread', 0), ('c3', 'Snacks', 0)])) as _CatRes);
      when(() => repo.deleteCatalogCategory('st1', 'c1')).thenAnswer((_) async => (success: false, code: 'CATEGORY_IN_USE', message: null, data: null) as _CatRes);
      await pump(t, CatalogCategoriesView(controller: ctl()));
      await tapKey(t, 'catAdd');
      await t.enterText(find.byKey(const Key('catTextField')), ' Snacks ');
      await tapKey(t, 'catTextConfirm');
      expect(find.byKey(const Key('cat_c3')), findsOneWidget);
      await tapKey(t, 'catRename_c2');
      await t.enterText(find.byKey(const Key('catTextField')), 'Bread');
      await tapKey(t, 'catTextConfirm');
      expect(find.text('Bread'), findsOneWidget);
      await tapKey(t, 'catDelete_c1');
      expect(find.text('It still has 3 products.'), findsOneWidget);
      await t.tap(find.text('Delete').last);
      await settle(t);
      expect(find.text('That category still has products.'), findsOneWidget);
      expect(find.byKey(const Key('cat_c1')), findsOneWidget);
    });
  });

  // ── CSV import ───────────────────────────────────────────────────────────────────────────
  group('CSV import', () {
    CsvImportController ctl({CsvFilePicker? picker}) => Get.put(
      CsvImportController(repository: repo, storeId: 'st1', filePicker: picker),
      tag: tag(),
    );

    for (final env in _Env.values) {
      testWidgets('${env.name}: paste, import, the report with the refused rows', (t) async {
        when(() => repo.importCatalogCsv('st1', kind: 'categories', csv: 'Name\nDrinks\n')).thenAnswer(
          (_) async =>
              (
                    success: true,
                    code: null,
                    message: null,
                    data: ImportReport.fromJson({
                      // the server's BulkImportData shape
                      'total': 5,
                      'created': 1,
                      'updated': 2,
                      'skipped': 1,
                      'failedCount': 1,
                      'failed': [
                        {'row': 3, 'error': 'Name is required', 'values': <String, String>{}},
                      ],
                      'skippedRows': [],
                    }),
                  )
                  as _ImpRes,
        );
        await pump(t, CsvImportView(controller: ctl()), env);
        await tapKey(t, 'importKind');
        await t.tap(find.text('Categories'));
        await settle(t);
        await typeKey(t, 'importText', 'Name\nDrinks\n');
        await tapKey(t, 'importSubmit');
        expect(find.descendant(of: find.byKey(const Key('importCreated')), matching: find.text('1')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('importUpdated')), matching: find.text('2')), findsOneWidget);
        expect(find.text('Row 3: Name is required'), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('importFailed')), matching: find.text('1')), findsOneWidget);
        expect(find.descendant(of: find.byKey(const Key('importSkipped')), matching: find.text('1')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('a .csv file fills the text; CSV_TOO_LARGE in words', (t) async {
      when(
        () => repo.importCatalogCsv(
          'st1',
          kind: 'products',
          csv: any(named: 'csv'),
        ),
      ).thenAnswer((_) async => (success: false, code: 'CSV_TOO_LARGE', message: 'x', data: null) as _ImpRes);
      await pump(t, CsvImportView(controller: ctl(picker: () async => (name: 'items.csv', text: 'Name,Price\nTea,2\n'))));
      await tapKey(t, 'importPick');
      expect(find.text('From items.csv'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Name,Price\nTea,2\n'), findsOneWidget);
      await tapKey(t, 'importSubmit');
      verify(() => repo.importCatalogCsv('st1', kind: 'products', csv: 'Name,Price\nTea,2\n')).called(1);
      expect(find.text('The file is too large (2 MB at most).'), findsOneWidget);
    });

    testWidgets('offline: the screen says so and an import needs internet', (t) async {
      offline();
      await pump(t, CsvImportView(controller: ctl()));
      expect(find.byKey(const Key('catOffline')), findsOneWidget);
      await typeKey(t, 'importText', 'Name\nX\n');
      await tapKey(t, 'importSubmit');
      expect(find.text('Importing needs an internet connection.'), findsOneWidget);
      verifyNever(
        () => repo.importCatalogCsv(
          any(),
          kind: any(named: 'kind'),
          csv: any(named: 'csv'),
        ),
      );
    });
  });
}
