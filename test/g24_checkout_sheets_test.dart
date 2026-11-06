// G2.4 checkout sheets on the real sale screen: recent searches, product detail, categories, discount, custom item, coupon.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_grid.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/sale_harness.dart';

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  setUp(() => h = SaleHarness());

  const tablet = Size(1180, 820);

  Future<void> settle(WidgetTester t) async {
    await t.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 3));
  }

  group('recent searches', () {
    testWidgets('remembered (newest first, no duplicates), shown when the field is focused and empty, one tap runs one again, Clear forgets them', (t) async {
      await h.mount(t, size: tablet);
      await t.runAsync(() async {
        await h.c.rememberSearch('tea');
        await h.c.rememberSearch('milk');
        await h.c.rememberSearch('TEA');
      });
      expect(h.c.recentSearches.toList(), ['TEA', 'milk']);
      expect(find.byKey(const Key('recentSearches')), findsNothing); // not focused yet
      await t.tap(find.byType(TextField).first);
      await t.pump();
      expect(find.byKey(const Key('recentSearches')), findsOneWidget);
      await t.tap(find.byKey(const Key('recent_milk')));
      await t.pump(const Duration(milliseconds: 500));
      expect(h.c.searchText.value, 'milk');
      expect(find.byKey(const Key('recentSearches')), findsNothing); // the field is no longer empty
      h.c.searchController.clear();
      h.c.onSearchChanged('');
      await t.pump();
      await t.runAsync(h.c.clearRecentSearches);
      await t.pump();
      expect(h.c.recentSearches, isEmpty);
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('a one-letter search is not remembered; the list is capped at 6', (t) async {
      await h.mount(t, size: tablet);
      await t.runAsync(() async {
        await h.c.rememberSearch('a');
        for (var i = 0; i < 8; i++) {
          await h.c.rememberSearch('term$i');
        }
      });
      expect(h.c.recentSearches, hasLength(6));
      expect(h.c.recentSearches.first, 'term7');
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('they survive an app restart (stored on the device as plain words)', (t) async {
      await h.mount(t, size: tablet);
      await t.runAsync(() async {
        await h.c.rememberSearch('sugar');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('pos_recent_searches'), ['sugar']);
      });
      await t.pump(const Duration(seconds: 1));
    });
  });

  group('product detail (long press)', () {
    testWidgets('single variant: SKU, price, stock and Add to sale', (t) async {
      await h.mount(t, size: tablet);
      await t.longPress(find.descendant(of: find.byType(ProductGrid), matching: find.text('Product a')));
      await settle(t);
      expect(find.byKey(const Key('detailSku')), findsOneWidget);
      expect(find.text('SKU SKU-a'), findsOneWidget);
      expect(find.byKey(const Key('detailStock')), findsOneWidget);
      expect(find.byKey(const Key('detailPrice')), findsOneWidget);
      await t.tap(find.byKey(const Key('detailAdd')));
      await settle(t);
      expect(h.c.itemCount, 1);
    });

    testWidgets('several variants: each with its own stock and price; tapping one adds exactly that variant', (t) async {
      h.products = [multiVariant('m')];
      await h.mount(t, size: tablet);
      await t.longPress(find.descendant(of: find.byType(ProductGrid), matching: find.text('Shirt m')));
      await settle(t);
      expect(find.byKey(const Key('detailVariant_m_s')), findsOneWidget);
      expect(find.byKey(const Key('detailVariant_m_m')), findsOneWidget);
      await t.tap(find.byKey(const Key('detailVariant_m_m')));
      await settle(t);
      expect(h.c.cartItems.single.variant!.variantId, 'm_m');
    });

    testWidgets('a sold-out product shows "Sold out" and cannot be added from here', (t) async {
      h.products = [product('x', stock: 0)];
      await h.mount(t, size: tablet);
      await t.longPress(find.descendant(of: find.byType(ProductGrid), matching: find.text('Product x')));
      await settle(t);
      expect(t.widget<AppButton>(find.byKey(const Key('detailAdd'))).onPressed, isNull);
    });
  });

  group('categories sheet', () {
    testWidgets('lists every category; choosing one filters the grid', (t) async {
      h.products = [product('a', category: 'c1'), product('b', category: 'c2')];
      await h.mount(t, size: tablet);
      expect(find.byKey(const Key('allCategoriesButton')), findsOneWidget);
      await t.tap(find.byKey(const Key('allCategoriesButton')));
      await settle(t);
      expect(find.byKey(const Key('category_c1')), findsOneWidget);
      expect(find.byKey(const Key('category_c2')), findsOneWidget);
      await t.tap(find.byKey(const Key('category_c2')));
      await settle(t);
      expect(h.c.selectedCategoryId.value, 'c2');
      expect(find.byType(ProductTile), findsOneWidget);
    });
  });

  group('discount sheet', () {
    Future<void> openDiscount(WidgetTester t) async {
      h.addLine(h.products[0]);
      await settle(t);
      await t.tap(find.byKey(const Key('discountSheetButton')));
      await settle(t);
    }

    testWidgets('a manager applies 10% with a quick chip; the cart shows the discount; Remove clears it', (t) async {
      await h.mount(t, size: tablet, manager: true);
      await openDiscount(t);
      await t.tap(find.text('Percent'));
      await t.pump();
      await t.tap(find.byKey(const Key('discountQuick_10')));
      await t.pump();
      await t.tap(find.byKey(const Key('discountApply')));
      await settle(t);
      expect(h.c.isPercentDiscount.value, isTrue);
      expect(h.c.discountController.text, '10');
      expect(h.c.totals.discount, 1); // 10% of 10
      await t.tap(find.byKey(const Key('discountSheetButton')));
      await settle(t);
      await t.tap(find.byKey(const Key('discountRemove')));
      await settle(t);
      expect(h.c.discountController.text, '0');
    });

    testWidgets('more than 100% and zero are refused with a reason', (t) async {
      await h.mount(t, size: tablet, manager: true);
      await openDiscount(t);
      await t.tap(find.text('Percent'));
      await t.pump();
      await t.enterText(find.byKey(const Key('discountValue')), '150');
      await t.tap(find.byKey(const Key('discountApply')));
      await t.pump();
      expect(find.text('A percentage cannot be more than 100.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('discountValue')), '0');
      await t.tap(find.byKey(const Key('discountApply')));
      await t.pump();
      expect(find.text('Enter a discount above zero.'), findsOneWidget);
      expect(h.c.discountController.text, '0');
    });

    testWidgets('a cashier is told only managers can discount', (t) async {
      await h.mount(t, size: tablet);
      await openDiscount(t);
      expect(find.byKey(const Key('discountBlocked')), findsOneWidget);
      expect(find.text('Only managers can apply a discount.'), findsWidgets);
    });

    testWidgets('with a coupon applied the sheet says to remove the coupon first', (t) async {
      await h.mount(t, size: tablet, manager: true);
      h.c.appliedCoupon.value = const PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10);
      await openDiscount(t);
      expect(find.textContaining('Remove it first'), findsOneWidget);
    });
  });

  group('custom item sheet', () {
    testWidgets('name + price + tax category → a "Custom item" line in the cart', (t) async {
      await h.mount(t, size: tablet);
      await t.tap(find.byKey(const Key('customItemButton')));
      await settle(t);
      await t.enterText(find.byKey(const Key('customName')), 'Gift wrap');
      await t.enterText(find.byKey(const Key('customPrice')), '4.5');
      await t.tap(find.byKey(const Key('customQtyPlus')));
      await t.tap(find.text('Tax exempt'));
      await t.pump();
      await t.tap(find.byKey(const Key('customAdd')));
      await settle(t);
      final line = h.c.cartItems.single;
      expect([line.product.name, line.unitPrice, line.quantity.value, line.taxCategory], ['Gift wrap', 4.5, 2, 'exempt']);
      expect(find.byKey(const Key('customLineTag')), findsOneWidget);
      expect(find.textContaining('tax exempt'), findsOneWidget);
    });

    testWidgets('empty name and zero price are refused with a reason; nothing is added', (t) async {
      await h.mount(t, size: tablet);
      await t.tap(find.byKey(const Key('customItemButton')));
      await settle(t);
      await t.tap(find.byKey(const Key('customAdd')));
      await t.pump();
      expect(find.text('Give the item a name.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('customName')), 'x');
      await t.tap(find.byKey(const Key('customAdd')));
      await t.pump();
      expect(find.text('Enter a price above zero.'), findsOneWidget);
      expect(h.c.cartItems, isEmpty);
    });
  });

  group('coupon sheet', () {
    void stubQuote(({PosQuote? quote, String? message, String? code}) Function() f) {
      when(() => h.repo.quoteSale(storeId: any(named: 'storeId'), items: any(named: 'items'), discountType: any(named: 'discountType'), discountValue: any(named: 'discountValue'), settingsVersion: any(named: 'settingsVersion'), couponCode: any(named: 'couponCode')))
          .thenAnswer((_) async => f());
    }

    testWidgets('an accepted code shows as applied in the cart (discount line named after it); Remove takes it off', (t) async {
      await h.mount(t, size: tablet);
      h.addLine(h.products[0], qty: 2);
      stubQuote(() => (
            quote: PosQuote(subtotal: 20, discount: 2, tax: 0, total: 18, taxRate: 0, currency: 'PKR', currencyExponent: 2, settingsVersion: 1, coupon: const PosAppliedCoupon(code: 'SAVE10', discountType: 'percentage', discountValue: 10)),
            message: null,
            code: null,
          ));
      await settle(t);
      await t.tap(find.byKey(const Key('couponButton')));
      await settle(t);
      await t.enterText(find.byKey(const Key('couponCode')), 'save10');
      await t.tap(find.byKey(const Key('couponApply')));
      await settle(t);
      expect(h.c.appliedCoupon.value!.code, 'SAVE10');
      expect(find.text('Coupon SAVE10'), findsOneWidget);
      expect(find.text('-${Money.format(2)}'), findsOneWidget);
      await t.tap(find.byKey(const Key('couponButton')));
      await settle(t);
      expect(find.byKey(const Key('couponApplied')), findsOneWidget);
      await t.tap(find.byKey(const Key('couponRemove')));
      await settle(t);
      expect(h.c.appliedCoupon.value, isNull);
    });

    testWidgets('a refused code shows the server\'s reason in the sheet and applies nothing', (t) async {
      await h.mount(t, size: tablet);
      h.addLine(h.products[0]);
      stubQuote(() => (quote: null, message: 'This coupon has expired', code: 'COUPON_EXPIRED'));
      await settle(t);
      await t.tap(find.byKey(const Key('couponButton')));
      await settle(t);
      await t.enterText(find.byKey(const Key('couponCode')), 'OLD');
      await t.tap(find.byKey(const Key('couponApply')));
      await settle(t);
      expect(find.text('This coupon has expired'), findsOneWidget);
      expect(h.c.appliedCoupon.value, isNull);
    });

    testWidgets('the Coupon button is off while the cart is empty', (t) async {
      await h.mount(t, size: tablet);
      expect(t.widget<InkWell>(find.descendant(of: find.byKey(const Key('couponButton')), matching: find.byType(InkWell))).onTap, isNull);
    });
  });
}
