// G4.5 on the sale path: a product sold with options opens the modifier sheet (required groups before Add), different choices are different lines,
// the request carries the choices and the server's price wins; a price book picked at checkout prices the lines (estimate → the quote's price) and a
// book no longer in force is refused in words; options and books are cached for offline and never block a sale; held sales and the saved cart keep
// the choices.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/catalog_pricing_cache.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';

import 'support/sale_harness.dart';

ModifierGroups _groups() => ModifierGroups.fromJson({
  'currency': 'USD',
  'currencyExponent': 2,
  'groups': [
    {
      'id': 'gSize',
      'name': 'Size',
      'minSelect': 1,
      'maxSelect': 1,
      'productIds': ['a'],
      'options': [
        {'id': 'small', 'name': 'Small', 'priceDeltaMinor': 0},
        {'id': 'large', 'name': 'Large', 'priceDeltaMinor': 100},
      ],
    },
    {
      'id': 'gExtra',
      'name': 'Extras',
      'minSelect': 0,
      'maxSelect': 2,
      'productIds': ['a'],
      'options': [
        {'id': 'shot', 'name': 'Extra shot', 'priceDeltaMinor': 80},
        {'id': 'oat', 'name': 'Oat milk', 'priceDeltaMinor': 60},
        {'id': 'syrup', 'name': 'Syrup', 'priceDeltaMinor': 50},
      ],
    },
  ],
});

PriceBooks _books() => PriceBooks.fromJson({
  'currency': 'USD',
  'currencyExponent': 2,
  'books': [
    {
      'id': 'wholesale',
      'name': 'Wholesale',
      'inForce': true,
      'entries': [
        {'variantId': 'b_v1', 'priceMinor': 400},
      ],
    },
    {'id': 'old', 'name': 'Old promo', 'active': true, 'endsAt': '2020-01-01T00:00:00Z', 'entries': []},
  ],
});

const _large = ChosenModifier(groupId: 'gSize', groupName: 'Size', optionId: 'large', name: 'Large', priceDeltaMinor: 100);
const _shot = ChosenModifier(groupId: 'gExtra', groupName: 'Extras', optionId: 'shot', name: 'Extra shot', priceDeltaMinor: 80);

void main() {
  setUpAll(SaleHarness.setUpAllShared);

  group('models', () {
    test('a line: list price + options; a book price replaces the list price; the server\'s price wins; options split lines', () {
      final p = product('a', price: 5);
      final plain = CartItem(product: p, variant: p.defaultVariant);
      final large = CartItem(product: p, variant: p.defaultVariant, modifiers: const [_large, _shot]);
      expect(large.unitPrice, closeTo(6.80, 1e-9));
      expect(large.displayName, 'Product a (Large, Extra shot)');
      expect(large.cartKey, isNot(plain.cartKey));
      expect(CartItem(product: p, variant: p.defaultVariant, modifiers: const [_shot, _large]).cartKey, large.cartKey, reason: 'the order of the taps does not matter');
      large.bookUnitPrice = 4;
      expect(large.unitPrice, closeTo(5.80, 1e-9));
      large.serverUnitPrice = 6.25;
      expect(large.unitPrice, 6.25);
      expect(ChosenModifier.toRequest(const [_large, _shot]), [
        {'groupId': 'gSize', 'optionIds': ['large']},
        {'groupId': 'gExtra', 'optionIds': ['shot']},
      ]);
    });

    test('the quote: each line\'s price in order, and whether options or a book priced it', () {
      final q = PosQuote.fromJson({
        'subtotal': 10,
        'discount': 0,
        'tax': 0,
        'total': 10,
        'currency': 'USD',
        'currencyExponent': 2,
        'lines': [
          {'variantId': 'a_v1', 'price': 6.8, 'modifiers': [_large.toJson()]},
          {'variantId': 'b_v1', 'price': 4, 'basePriceMinor': 400},
          {'variantId': 'c_v1', 'price': 7.5},
        ],
      });
      expect([for (final l in q.lines) (l.price, l.priced)], [(6.8, true), (4.0, true), (7.5, false)]);
    });

    test('a price book is offered only in its window', () {
      final b = _books().books;
      expect(b.first.inForceAt(DateTime(2026, 11, 10)), isTrue);
      expect(b.last.inForceAt(DateTime(2026, 11, 10)), isFalse);
    });
  });

  group('selling with options', () {
    late SaleHarness h;
    setUp(() {
      h = SaleHarness();
      when(() => h.repo.getModifierGroups(any())).thenAnswer((_) async => _groups());
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => _books());
    });

    testWidgets('the sheet: a required size before Add; extras up to two; Add puts the line in with the options and the estimate', (t) async {
      await h.mount(t);
      h.c.addToCart(h.products.first);
      await h.settle(t);
      expect(find.byKey(const Key('modifierSheet')), findsOneWidget);
      expect(h.c.cartItems, isEmpty);
      expect(find.byKey(const Key('modifierMissing')), findsOneWidget);
      await t.tap(find.byKey(const Key('modifierAdd')));
      await h.settle(t);
      expect(h.c.cartItems, isEmpty, reason: 'Add does nothing until the size is chosen');
      await t.tap(find.byKey(const Key('mod_gSize_large')));
      await t.tap(find.byKey(const Key('mod_gExtra_shot')));
      await t.tap(find.byKey(const Key('mod_gExtra_oat')));
      await t.tap(find.byKey(const Key('mod_gExtra_syrup'))); // a third extra is not taken
      await h.settle(t);
      expect(find.textContaining('Add · \$12.40'), findsOneWidget, reason: '10.00 + 1.00 + 0.80 + 0.60');
      await t.tap(find.byKey(const Key('modifierAdd')));
      await h.settle(t);
      final line = h.c.cartItems.single;
      expect(line.modifiers.map((m) => m.name), ['Large', 'Extra shot', 'Oat milk']);
      expect(line.unitPrice, closeTo(12.40, 1e-9));
      expect(find.text('Large, Extra shot, Oat milk'), findsOneWidget);
    });

    testWidgets('different choices are different lines; the same choice adds to its line; the request carries the choices', (t) async {
      await h.mount(t);
      final a = h.products.first;
      h.c.addToCart(a, a.defaultVariant, const [_large]);
      h.c.addToCart(a, a.defaultVariant, const [_large]);
      h.c.addToCart(a, a.defaultVariant, const [ChosenModifier(groupId: 'gSize', groupName: 'Size', optionId: 'small', name: 'Small', priceDeltaMinor: 0)]);
      await h.settle(t);
      expect(h.c.cartItems.map((i) => i.quantity.value), [2, 1]);
      expect(h.c.cartQtyFor(a), 3);
      h.stubCreateSale((_) async => (success: true, sale: sale(), message: null, queued: false));
      h.c.selectedPayment.value = PosPaymentMethod.card;
      await h.c.completeSale();
      await h.settle(t);
      final items = (h.calls.single[#items] as List).cast<Map<String, dynamic>>();
      expect(items.first['modifiers'], [
        {'groupId': 'gSize', 'optionIds': ['large']},
      ]);
      expect(items.first['unitPrice'], 11.0, reason: 'what the till shows — used only when the sale is replayed offline');
    });

    testWidgets('the server\'s quote prices an option line as is (the list price stays the variant\'s)', (t) async {
      await h.mount(t);
      final a = h.products.first;
      h.c.addToCart(a, a.defaultVariant, const [_large]);
      h.stubQuote(
        () => (
          quote: PosQuote.fromJson({
            'subtotal': 11.5,
            'discount': 0,
            'tax': 0,
            'total': 11.5,
            'currency': 'USD',
            'currencyExponent': 2,
            'lines': [
              {'variantId': 'a_v1', 'price': 11.5, 'modifiers': [_large.toJson()]},
            ],
          }),
          message: null,
          code: null,
        ),
      );
      h.stubCreateSale((_) async => (success: true, sale: sale(), message: null, queued: false));
      h.c.selectedPayment.value = PosPaymentMethod.card;
      final done = h.c.completeSale();
      await h.settle(t);
      expect(find.text('Total updated'), findsOneWidget);
      expect(h.c.cartItems.single.unitPrice, 11.5);
      expect(h.c.cartItems.single.variant!.price, 10, reason: 'not overwritten with the option price');
      await t.tap(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('Charge \$11.50')));
      await done;
      await t.pump(const Duration(seconds: 4)); // the cart's delayed save and the snackbar
    });
  });

  group('price books', () {
    late SaleHarness h;
    setUp(() {
      h = SaleHarness();
      when(() => h.repo.getModifierGroups(any())).thenAnswer((_) async => ModifierGroups.fromJson({'groups': []}));
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => _books());
    });

    testWidgets('picked at checkout: the estimate on screen, the book sent with the sale; only books in force are offered', (t) async {
      await h.mount(t, size: const Size(1024, 1366));
      final b = h.products[1];
      h.c.addToCart(b);
      await h.settle(t);
      await t.tap(find.byKey(const Key('priceBookButton')));
      await h.settle(t);
      expect(find.byKey(const Key('priceBook_old')), findsNothing);
      await t.tap(find.byKey(const Key('priceBook_wholesale')));
      await h.settle(t);
      expect(h.c.cartItems.single.unitPrice, 4.0);
      expect(find.text('Prices: Wholesale'), findsOneWidget);
      expect(find.byKey(Key('lineBook_${h.c.cartItems.single.cartKey}')), findsOneWidget);
      h.stubCreateSale((_) async => (success: true, sale: sale(), message: null, queued: false));
      h.c.selectedPayment.value = PosPaymentMethod.card;
      await h.c.completeSale();
      await h.settle(t);
      expect(h.calls.single[#priceBookId], 'wholesale');
      expect(h.c.priceBook.value, isNull, reason: 'the next sale starts at normal prices');
    });

    testWidgets('a book no longer in force: refused in words, normal prices back, nothing charged', (t) async {
      await h.mount(t);
      h.c.addToCart(h.products[1]);
      h.c.setPriceBook(_books().books.first);
      h.stubQuote(() => (quote: null, message: 'That price book is not available now', code: 'PRICE_BOOK_NOT_ACTIVE'));
      h.stubCreateSale((_) async => (success: true, sale: sale(), message: null, queued: false));
      h.c.selectedPayment.value = PosPaymentMethod.card;
      await h.c.completeSale();
      await h.settle(t);
      expect(find.textContaining('That price book is not available now. Choose another'), findsOneWidget);
      expect(h.c.priceBook.value, isNull);
      expect(h.c.cartItems.single.unitPrice, 5.0);
      expect(h.calls, isEmpty);
      await t.pump(const Duration(seconds: 4));
    });
  });

  group('offline, held sales and the saved cart', () {
    testWidgets('offline: the options and books come from the last copy kept on the device', (t) async {
      final h = SaleHarness();
      await CatalogPricingCache.saveGroups('store-1', _groups());
      await CatalogPricingCache.saveBooks('store-1', _books());
      when(() => h.repo.getModifierGroups(any())).thenAnswer((_) async => null);
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => null);
      h.putController();
      // (putController resets the preferences and starts loading: keep the copies again before the load reaches them)
      await CatalogPricingCache.saveGroups('store-1', _groups());
      await CatalogPricingCache.saveBooks('store-1', _books());
      await h.settle(t);
      expect(h.c.modifierGroups.value!.of('a').map((g) => g.name), ['Size', 'Extras']);
      expect(h.c.priceBooks.map((b) => b.id), ['wholesale', 'old']);
      Get.reset();
    });

    testWidgets('no options known at all: the product is added plain (selling never waits for options)', (t) async {
      final h = SaleHarness();
      when(() => h.repo.getModifierGroups(any())).thenThrow(Exception('offline'));
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => null);
      await h.mount(t);
      h.c.addToCart(h.products.first);
      await h.settle(t);
      expect(find.byKey(const Key('modifierSheet')), findsNothing);
      expect(h.c.cartItems.single.modifiers, isEmpty);
    });

    testWidgets('a held sale resumes with its options and the server\'s held price; the name is not doubled', (t) async {
      final h = SaleHarness();
      when(() => h.repo.getModifierGroups(any())).thenAnswer((_) async => _groups());
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => null);
      await h.mount(t);
      h.products = [];
      h.c.resumeHeldSale(
        sale(
          status: 'held',
          total: 11.5,
          items: [
            PosSaleItemModel.fromJson({
              'productId': 'gone',
              'variantId': 'gone_v1',
              'name': 'Latte (Large)',
              'qty': 1,
              'price': 11.5,
              'lineTotal': 11.5,
              'basePriceMinor': 1000,
              'modifiers': [_large.toJson()],
            }, exp: 2),
          ],
        ),
      );
      await h.settle(t);
      final line = h.c.cartItems.single;
      expect(line.displayName, 'Latte (Large)');
      expect(line.unitPrice, 11.5);
      expect(line.modifiers.single.optionId, 'large');
    });

    testWidgets('the saved cart keeps the options across a restart', (t) async {
      final h = SaleHarness();
      when(() => h.repo.getModifierGroups(any())).thenAnswer((_) async => _groups());
      when(() => h.repo.getPriceBooks(any())).thenAnswer((_) async => null);
      await h.mount(t);
      final a = h.products.first;
      h.c.addToCart(a, a.defaultVariant, const [_large, _shot]);
      await h.c.persistNow();
      final again = PosHomeController(posRepository: h.repo, categoryRepository: h.cats);
      again.storeId.value = 'store-1';
      again.sessionId.value = 'session-1';
      await again.restoreCart();
      expect(again.cartItems.single.modifiers.map((m) => m.optionId), ['large', 'shot']);
      expect(again.cartItems.single.unitPrice, closeTo(11.80, 1e-9));
      await t.pump(const Duration(seconds: 1)); // the cart's delayed save
    });
  });
}
