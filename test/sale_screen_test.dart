// The redesigned sale screen: layouts (phone pill + expandable cart, two panes on tablets), the product grid, the cart
// panel (steppers, swipe-to-remove with Undo, clear), hold confirm — in light and dark.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cart_panel.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/phone_cart_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_grid.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

import 'support/sale_harness.dart';

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  setUp(() => h = SaleHarness());

  const phone = Size(390, 844);
  const smallPhone = Size(360, 640);
  const tabletPortrait = Size(820, 1180);
  const tabletLandscape = Size(1180, 820);

  Future<void> tapProduct(WidgetTester t, String name) async {
    await t.tap(find.descendant(of: find.byType(ProductGrid), matching: find.text(name)));
    await t.pump(const Duration(milliseconds: 800)); // ripple + fly-to-cart dot
  }

  group('phone', () {
    testWidgets(
      'no pill while the cart is empty; adding a product shows the live total pill',
      (t) async {
        await h.mount(t, size: phone);
        expect(find.byKey(const Key('phoneCartSheet')), findsNothing);
        expect(find.byType(ProductTile), findsNWidgets(3));
        await tapProduct(t, 'Product a');
        expect(find.byKey(const Key('phoneCartSheet')), findsOneWidget);
        expect(t.widget<Text>(find.byKey(const Key('pillCount'))).data, '1 item');
        expect(find.byKey(const Key('pillTotal')), findsOneWidget);
        expect(h.c.itemCount, 1);
      },
    );

    testWidgets(
      'the pill total follows the cart (2 × 10 + 5 = 25) and the product tile shows its in-cart badge',
      (t) async {
        await h.mount(t, size: phone);
        await tapProduct(t, 'Product a');
        await tapProduct(t, 'Product a');
        await tapProduct(t, 'Product b');
        expect(t.widget<Text>(find.byKey(const Key('pillCount'))).data, '3 items');
        final total = t
            .widget<AmountText>(find.byKey(const Key('pillTotal')))
            .text;
        expect(total, Money.format(25));
      },
    );

    testWidgets(
      'tapping the pill expands the cart; Charge and Hold are reachable; tapping again collapses',
      (t) async {
        await h.mount(t, size: phone);
        await tapProduct(t, 'Product a');
        await t.tap(find.byKey(const Key('pillTotal')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        expect(find.text('Current sale'), findsOneWidget);
        expect(find.byKey(const Key('chargeButton')), findsOneWidget);
        expect(find.byKey(const Key('holdButton')), findsOneWidget);
        await t.tap(find.byKey(const Key('pillTotal')));
        await t.pump();
        await t.pump(const Duration(milliseconds: 500));
        expect(
          t.getSize(find.byKey(const Key('phoneCartSheet'))).height,
          PhoneCartSheet.pillHeight,
        );
      },
    );

    testWidgets('an expanded cart that empties starts the next sale collapsed', (
      t,
    ) async {
      await h.mount(t, size: phone);
      await tapProduct(t, 'Product a');
      await t.tap(find.byKey(const Key('pillCount')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));
      expect(
        t.getSize(find.byKey(const Key('phoneCartSheet'))).height,
        greaterThan(PhoneCartSheet.pillHeight + 100),
      );
      h.c.cartItems.clear();
      await t.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const Key('phoneCartSheet')), findsNothing);
      h.addLine(h.products.first);
      await t.pump(const Duration(milliseconds: 600));
      expect(
        t.getSize(find.byKey(const Key('phoneCartSheet'))).height,
        PhoneCartSheet.pillHeight,
      );
    });

    testWidgets(
      'dragging the pill up opens the cart, dragging down closes it',
      (t) async {
        await h.mount(t, size: phone);
        await tapProduct(t, 'Product a');
        await t.fling(
          find.byKey(const Key('pillTotal')),
          const Offset(0, -400),
          1500,
        );
        await t.pump(const Duration(milliseconds: 600));
        expect(
          t.getSize(find.byKey(const Key('phoneCartSheet'))).height,
          greaterThan(300),
        );
        await t.fling(
          find.byKey(const Key('pillTotal')),
          const Offset(0, 500),
          1500,
        );
        await t.pump(const Duration(milliseconds: 600));
        expect(
          t.getSize(find.byKey(const Key('phoneCartSheet'))).height,
          PhoneCartSheet.pillHeight,
        );
      },
    );
  });

  group('tablets: two panes when the content is ≥ 700 px wide', () {
    for (final sz in {
      'portrait 820': tabletPortrait,
      'landscape 1180': tabletLandscape,
    }.entries) {
      testWidgets('${sz.key}: catalogue left, receipt cart right, no pill', (
        t,
      ) async {
        await h.mount(t, size: sz.value);
        expect(find.text('Current sale'), findsOneWidget);
        expect(find.byKey(const Key('phoneCartSheet')), findsNothing);
        expect(find.byType(ProductTile), findsNWidgets(3));
        expect(find.text('Cart is empty'), findsOneWidget);
        await tapProduct(t, 'Product b');
        expect(find.byType(CartLine), findsOneWidget);
        expect(find.byKey(const Key('chargeButton')), findsOneWidget);
        // the cart pane sits to the right of the grid
        expect(
          t.getTopLeft(find.byType(CartPanel)).dx,
          greaterThan(t.getTopLeft(find.byType(ProductTile).first).dx),
        );
      });
    }

    testWidgets('grid columns scale with the width', (t) async {
      expect(ProductGrid.columnsFor(390), 2);
      expect(ProductGrid.columnsFor(500), 3);
      expect(ProductGrid.columnsFor(900), 5);
    });
  });

  group(
    'renders without overflow — light and dark, empty and with 6 items',
    () {
      final sizes = {
        'small phone': smallPhone,
        'phone': phone,
        'tablet portrait': tabletPortrait,
        'tablet landscape': tabletLandscape,
      };
      for (final theme in {
        'light': AppTheme.light,
        'dark': AppTheme.dark,
      }.entries) {
        for (final sz in sizes.entries) {
          testWidgets('${theme.key} · ${sz.key}', (t) async {
            h = SaleHarness()
              ..products = [
                for (var i = 0; i < 8; i++)
                  product(
                    'p$i',
                    price: 3.5 + i,
                    category: i.isEven ? 'c1' : 'c2',
                  ),
              ];
            await h.mount(t, size: sz.value, theme: theme.value);
            expect(t.takeException(), isNull, reason: 'empty');
            for (var i = 0; i < 6; i++) {
              h.addLine(h.products[i], qty: i + 1);
            }
            await h.settle(t);
            if (find.byKey(const Key('pillTotal')).evaluate().isNotEmpty) {
              await t.tap(find.byKey(const Key('pillTotal')));
              await h.settle(t);
            }
            expect(t.takeException(), isNull, reason: 'with 6 items');
          });
        }
      }
    },
  );

  group('grid states', () {
    testWidgets('skeleton while loading; no tiles yet', (t) async {
      await h.mount(t, size: phone, loading: true);
      expect(h.c.isLoadingProducts.value, isTrue);
      expect(find.byType(ProductTile), findsNothing);
      expect(find.byType(SkeletonBox), findsWidgets);
      await t.pump(const Duration(milliseconds: 10));
      // never settle the 1-day delay; unmount first
      await t.pumpWidget(const SizedBox());
    });

    testWidgets(
      'empty catalogue → empty state with Retry, which asks the controller to reload',
      (t) async {
        h.products = [];
        await h.mount(t, size: phone);
        expect(find.text('No products found'), findsOneWidget);
        clearInteractions(h.repo);
        await t.tap(find.text('Retry'));
        await h.settle(t);
        verify(
          () => h.repo.getProducts(
            any(),
            page: any(named: 'page'),
            limit: any(named: 'limit'),
          ),
        ).called(1);
      },
    );

    testWidgets('a sold-out product cannot be added; an unlimited one can', (
      t,
    ) async {
      h.products = [
        product('x', stock: 0, name: 'Gone'),
        product('y', stock: 0, unlimited: true, name: 'Endless'),
      ];
      await h.mount(t, size: phone);
      await t.tap(find.text('Gone'), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 300));
      expect(h.c.hasItems, isFalse);
      await tapProduct(t, 'Endless');
      expect(h.c.itemCount, 1);
    });

    testWidgets(
      'a multi-variant product opens the variant picker; picking a variant adds exactly that variant',
      (t) async {
        h.products = [multiVariant('m')];
        await h.mount(t, size: phone);
        await t.tap(find.descendant(of: find.byType(ProductGrid), matching: find.text('Shirt m')));
        await h.settle(t);
        expect(find.text('Select variant · Shirt m'), findsOneWidget);
        expect(h.c.hasItems, isFalse);
        await t.tap(find.textContaining('M').last, warnIfMissed: false);
        await t.tap(find.text(Money.format(22)).last);
        await h.settle(t);
        expect(h.c.cartItems.single.variant!.variantId, 'm_m');
        expect(find.text('Select variant · Shirt m'), findsNothing);
      },
    );

    testWidgets('search filters the grid through the controller', (t) async {
      await h.mount(t, size: phone);
      h.c.searchText.value = 'Product b';
      await h.settle(t);
      expect(find.byType(ProductTile), findsOneWidget);
    });

    testWidgets('stale (cached) data shows the offline bar with a Refresh', (
      t,
    ) async {
      await h.mount(t, size: phone);
      h.c.catalogFromCache.value = true;
      await h.settle(t);
      expect(find.byKey(const Key('staleDataBar')), findsOneWidget);
      h.c.catalogFromCache.value = false;
      await h.settle(t);
      expect(find.byKey(const Key('staleDataBar')), findsNothing);
    });
  });

  group('cart panel (tablet pane)', () {
    testWidgets(
      '+ / − steppers change the quantity and the line total; the last unit removes the line',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0], qty: 2); // 2 × 10
        await h.settle(t);
        expect(find.text(Money.format(20)), findsWidgets);
        await t.tap(
          find.descendant(
            of: find.byType(CartLine),
            matching: find.byIcon(Icons.add_rounded),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(h.c.cartItems.single.quantity.value, 3);
        await t.tap(
          find.descendant(
            of: find.byType(CartLine),
            matching: find.byIcon(Icons.remove_rounded),
          ),
        );
        await t.tap(
          find.descendant(
            of: find.byType(CartLine),
            matching: find.byIcon(Icons.remove_rounded),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(h.c.cartItems.single.quantity.value, 1);
        await t.tap(
          find.descendant(
            of: find.byType(CartLine),
            matching: find.byIcon(Icons.remove_rounded),
          ),
        );
        await t.pump(const Duration(milliseconds: 300));
        expect(h.c.cartItems, isEmpty);
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'swipe to remove → "Removed … Undo" → Undo puts the exact line back at its position',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0], qty: 2);
        h.addLine(h.products[1], qty: 3);
        h.addLine(h.products[2]);
        await h.settle(t);
        final middle = h.c.cartItems[1];
        await t.drag(find.byType(CartLine).at(1), const Offset(-600, 0));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(h.c.cartItems.map((i) => i.product.productId), ['a', 'c']);
        expect(find.text('Removed Product b'), findsOneWidget);
        await t.tap(find.text('Undo'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 600));
        expect(h.c.cartItems.map((i) => i.product.productId), ['a', 'b', 'c']);
        expect(identical(h.c.cartItems[1], middle), isTrue);
        expect(h.c.cartItems[1].quantity.value, 3);
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'clearing the cart asks first; Cancel keeps it, Clear empties it',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0]);
        await h.settle(t);
        await t.tap(find.byKey(const Key('clearCartButton')));
        await h.settle(t);
        expect(find.text('Clear the cart?'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await h.settle(t);
        expect(h.c.hasItems, isTrue);
        await t.tap(find.byKey(const Key('clearCartButton')));
        await h.settle(t);
        await t.tap(find.text('Clear cart').last);
        await h.settle(t);
        expect(h.c.hasItems, isFalse);
      },
    );

    testWidgets(
      'totals come from the controller (subtotal, discount, tax, total)',
      (t) async {
        await h.mount(t, size: tabletLandscape, manager: true, taxRate: 0.1);
        h.addLine(h.products[0], qty: 2); // 20
        h.c.discountController.text = '5';
        h.c.cartItems.refresh();
        await h.settle(t);
        expect(find.text(Money.format(20)), findsWidgets); // subtotal
        expect(find.text('-${Money.format(5)}'), findsOneWidget);
        expect(find.text('+${Money.format(h.c.taxValue)}'), findsOneWidget);
        expect(
          t
              .widget<AmountText>(
                find.descendant(
                  of: find.byType(CartFooter),
                  matching: find.byType(AmountText),
                ),
              )
              .text,
          Money.format(h.c.total),
        );
      },
    );

    testWidgets(
      'a cashier cannot discount: field disabled, Charge is blocked with the reason shown',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0]);
        h.c.discountController.text = '2';
        h.c.cartItems.refresh();
        await h.settle(t);
        expect(
          find.text('Only managers can apply a discount.'),
          findsOneWidget,
        );
        expect(
          t.widget<AppButton>(find.byKey(const Key('chargeButton'))).onPressed,
          isNull,
        );
      },
    );

    testWidgets(
      'Charge opens the payment sheet; Hold opens the confirm sheet (never runs directly)',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0]);
        await h.settle(t);
        await t.tap(find.byKey(const Key('holdButton')));
        await h.settle(t);
        expect(find.text('Hold this sale?'), findsOneWidget);
        verifyNever(
          () => h.repo.createSale(
            storeId: any(named: 'storeId'),
            sessionId: any(named: 'sessionId'),
            registerId: any(named: 'registerId'),
            employeeId: any(named: 'employeeId'),
            items: any(named: 'items'),
            discountType: any(named: 'discountType'),
            discountValue: any(named: 'discountValue'),
            clientTotal: any(named: 'clientTotal'),
            settingsVersion: any(named: 'settingsVersion'),
            clientCreatedAt: any(named: 'clientCreatedAt'),
            paymentMethod: any(named: 'paymentMethod'),
            payments: any(named: 'payments'),
            amountTendered: any(named: 'amountTendered'),
            paymentReference: any(named: 'paymentReference'),
            customerName: any(named: 'customerName'),
            customerId: any(named: 'customerId'),
            notes: any(named: 'notes'),
            status: any(named: 'status'),
            idempotencyKey: any(named: 'idempotencyKey'),
          ),
        );
        await t.tap(find.byKey(const Key('holdCancel')));
        await h.settle(t);
        expect(find.text('Hold this sale?'), findsNothing);
        await t.tap(find.byKey(const Key('chargeButton')));
        await h.settle(t);
        expect(find.text('Amount due'), findsOneWidget);
      },
    );
  });

  group('hold', () {
    testWidgets(
      'Hold → confirm → holdSale(status held): the cart clears and ONLY the confirm sheet closes (the POS screen stays)',
      (t) async {
        await h.mount(t, size: tabletLandscape);
        h.addLine(h.products[0]);
        h.stubCreateSale(
          (_) async => (
            success: true,
            sale: sale(status: 'held'),
            message: null,
            queued: false,
          ),
        );
        await h.settle(t);
        await t.tap(find.byKey(const Key('holdButton')));
        await h.settle(t);
        await t.tap(find.byKey(const Key('holdConfirm')));
        await h.settle(t, frames: 12);
        expect(h.verifyCreateSale().captured, isEmpty);
        expect(h.c.hasItems, isFalse);
        expect(
          find.text('Hold this sale?'),
          findsNothing,
          reason: 'the sheet closed',
        );
        expect(
          find.text('Quick Sale'),
          findsOneWidget,
          reason: 'the POS screen is still there',
        );
        expect(find.byType(ProductTile), findsNWidgets(3));
        await t.pump(const Duration(seconds: 5));
      },
    );

    testWidgets('a failed hold leaves the sheet open and the cart intact', (
      t,
    ) async {
      await h.mount(t, size: tabletLandscape);
      h.addLine(h.products[0]);
      h.stubCreateSale(
        (_) async =>
            (success: false, sale: null, message: 'nope', queued: false),
      );
      await h.settle(t);
      await t.tap(find.byKey(const Key('holdButton')));
      await h.settle(t);
      await t.tap(find.byKey(const Key('holdConfirm')));
      await h.settle(t, frames: 12);
      expect(h.c.hasItems, isTrue);
      expect(find.text('Hold this sale?'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
