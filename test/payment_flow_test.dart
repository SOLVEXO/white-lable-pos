// Payment sheet → Charge → success view: cash with keypad and quick amounts, change due / shortfall straight from the
// controller, card reference, split tender, success + offline success, failure (never a success view), the server
// quote changing the total, the sheet being undismissable mid-charge, and the keyboard scanner staying quiet while a
// sheet is open.
import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/cash_keypad.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sale_harness.dart';

void main() {
  SaleHarness.setUpAllShared();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late SaleHarness h;
  setUp(() => h = SaleHarness());

  const wide = Size(1180, 820);

  /// testWidgets + a final pump: the controller saves the cart 400 ms after any edit (a debounce Timer), which must not
  /// still be pending when the test ends.
  void sTest(String name, Future<void> Function(WidgetTester t) body) =>
      testWidgets(name, (t) async {
        await body(t);
        await t.pump(const Duration(seconds: 2));
      });

  PosSaleModel completed({String number = 'S-0007', double total = 10}) => sale(
    number: number,
    total: total,
    items: [
      PosSaleItemModel(
        saleItemId: 'i1',
        productId: 'a',
        name: 'Product a',
        sku: 'SKU-a',
        price: total,
        qty: 1,
        lineTotal: total,
      ),
    ],
  );

  /// A 1×10.00 cart on the wide layout, payment sheet opened.
  Future<void> openPayment(WidgetTester t, {bool manager = false}) async {
    await h.mount(t, size: wide, manager: manager);
    h.addLine(h.products[0]);
    await h.settle(t);
    await t.tap(find.byKey(const Key('chargeButton')));
    await h.settle(t);
    expect(find.text('Amount due'), findsOneWidget);
  }

  Future<void> tapKey(WidgetTester t, String label) async {
    await t.tap(
      find.descendant(of: find.byType(CashKeypad), matching: find.text(label)),
    );
    await t.pump(const Duration(milliseconds: 50));
  }

  group('cash', () {
    sTest(
      'keypad fills tenderedController; short shows "Amount short" from paymentCheck.shortBy; Charge stays disabled',
      (t) async {
        await openPayment(t);
        expect(find.text('Enter the amount received'), findsOneWidget);
        await tapKey(t, '5');
        expect(h.c.tenderedController.text, '5');
        expect(find.byKey(const Key('amountShort')), findsOneWidget);
        expect(
          t
              .widget<AmountText>(
                find.descendant(
                  of: find.byKey(const Key('amountShort')),
                  matching: find.byType(AmountText),
                ),
              )
              .text,
          Money.format(h.c.paymentCheck.shortBy),
        );
        expect(h.c.paymentCheck.shortBy, 5);
        expect(find.text('Enter full amount'), findsOneWidget);
        expect(
          t.widget<AppButton>(find.byKey(const Key('confirmCharge'))).onPressed,
          isNull,
        );
      },
    );

    sTest(
      'enough cash shows "Change due" = controller.changeDue; Charge enables with the total on it',
      (t) async {
        await openPayment(t);
        await tapKey(t, '2');
        await tapKey(t, '0');
        expect(h.c.tenderedController.text, '20');
        expect(h.c.changeDue, 10);
        expect(find.byKey(const Key('changeDue')), findsOneWidget);
        expect(
          find
              .descendant(
                of: find.byKey(const Key('changeDue')),
                matching: find.byType(AmountText),
              )
              .evaluate()
              .length,
          1,
        );
        expect(
          t
              .widget<AmountText>(
                find.descendant(
                  of: find.byKey(const Key('changeDue')),
                  matching: find.byType(AmountText),
                ),
              )
              .text,
          Money.format(h.c.changeDue),
        );
        expect(find.text('Charge ${Money.format(10)}'), findsWidgets);
        expect(
          t.widget<AppButton>(find.byKey(const Key('confirmCharge'))).onPressed,
          isNotNull,
        );
      },
    );

    sTest(
      'quick amounts (Exact + round-ups) only fill the field; Backspace edits; decimals are limited to the currency',
      (t) async {
        await openPayment(t);
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        expect(h.c.tenderedController.text, '10.00');
        expect(h.c.paymentCheck.covered, isTrue);
        expect(h.c.changeDue, 0);
        await t.tap(find.byKey(const Key('quick-20.00')));
        await t.pump(const Duration(milliseconds: 50));
        expect(h.c.tenderedController.text, '20.00');
        expect(h.c.changeDue, 10);
        expect(h.c.total, 10, reason: 'suggestions never touch totals');
        // free typing: 2 decimals max for USD
        h.c.tenderedController.text = '';
        h.c.cartItems.refresh();
        await tapKey(t, '1');
        await tapKey(t, '.');
        await tapKey(t, '5');
        await tapKey(t, '5');
        await tapKey(t, '5');
        expect(h.c.tenderedController.text, '1.55');
        await t.tap(
          find.descendant(
            of: find.byType(CashKeypad),
            matching: find.byIcon(Icons.backspace_outlined),
          ),
        );
        await t.pump(const Duration(milliseconds: 50));
        expect(h.c.tenderedController.text, '1.5');
      },
    );

    sTest(
      'CashKeypad.apply rules: no leading zeros, one dot, decimals capped, 0 decimals = no dot',
      (t) async {
        expect(CashKeypad.apply('', '0', 2), '0');
        expect(CashKeypad.apply('0', '5', 2), '5');
        expect(CashKeypad.apply('', '.', 2), '0.');
        expect(CashKeypad.apply('1.5', '.', 2), '1.5');
        expect(CashKeypad.apply('1.25', '9', 2), '1.25');
        expect(CashKeypad.apply('12', '.', 0), '12');
        expect(CashKeypad.apply('12', 'back', 2), '1');
        expect(CashKeypad.apply('', 'back', 2), '');
      },
    );

    sTest(
      'physical keyboard digits and Backspace work while the keypad has focus',
      (t) async {
        await openPayment(t);
        await tapKey(t, '1'); // gives the keypad focus
        await t.sendKeyDownEvent(LogicalKeyboardKey.digit5, character: '5');
        await t.sendKeyUpEvent(LogicalKeyboardKey.digit5);
        expect(h.c.tenderedController.text, '15');
        await t.sendKeyEvent(LogicalKeyboardKey.backspace);
        expect(h.c.tenderedController.text, '1');
      },
    );
  });

  group('card / other / split', () {
    sTest(
      'card: reference field appears, keypad is gone, Charge is enabled at once (pays the total)',
      (t) async {
        await openPayment(t);
        await t.tap(find.byKey(const Key('method-card')));
        await h.settle(t, frames: 3);
        expect(h.c.selectedPayment.value, PosPaymentMethod.card);
        expect(find.byKey(const Key('paymentReference')), findsOneWidget);
        expect(find.byType(CashKeypad), findsNothing);
        expect(
          t.widget<AppButton>(find.byKey(const Key('confirmCharge'))).onPressed,
          isNotNull,
        );
      },
    );

    sTest(
      'split: two lines by default; amounts + "Fill rest" cover the total; the payload carries both payments',
      (t) async {
        await openPayment(t);
        h.stubCreateSale(
          (_) async =>
              (success: true, sale: completed(), message: null, queued: false),
        );
        await t.tap(find.byKey(const Key('splitToggle')));
        await h.settle(t, frames: 3);
        expect(h.c.isSplitPayment.value, isTrue);
        expect(h.c.splitLines.length, 2);
        expect(find.text('Single payment'), findsOneWidget);
        // line 0 = card (default), line 1 = cash
        await t.enterText(
          find.descendant(
            of: find.byKey(const Key('splitAmount-0')),
            matching: find.byType(TextFormField),
          ),
          '4',
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('splitRemaining')), findsOneWidget);
        expect(h.c.paymentCheck.shortBy, 6);
        expect(find.text('Payments short'), findsOneWidget);
        await t.tap(find.byKey(const Key('fillRemaining-1')));
        await t.pump(const Duration(milliseconds: 100));
        expect(h.c.splitLines[1].amount.text, Money.plain(6));
        expect(h.c.paymentCheck.covered, isTrue);
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 12);
        final payments =
            h.calls.single[#payments] as List<Map<String, dynamic>>;
        expect(payments.map((p) => '${p['method']}:${p['amount']}'), [
          'card:4.0',
          'cash:6.0',
        ]);
        expect(find.byType(SaleSuccessView), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest(
      'split: card/other above the total is flagged; a line can be removed; Single payment returns to one method',
      (t) async {
        await openPayment(t);
        await t.tap(find.byKey(const Key('splitToggle')));
        await h.settle(t, frames: 3);
        await t.enterText(
          find.descendant(
            of: find.byKey(const Key('splitAmount-0')),
            matching: find.byType(TextFormField),
          ),
          '15',
        );
        await t.pump(const Duration(milliseconds: 100));
        expect(find.byKey(const Key('splitExceeds')), findsOneWidget);
        expect(
          t.widget<AppButton>(find.byKey(const Key('confirmCharge'))).onPressed,
          isNull,
        );
        await t.tap(find.byKey(const Key('removeSplit-1')));
        await t.pump(const Duration(milliseconds: 100));
        expect(h.c.splitLines.length, 1);
        await t.tap(find.byKey(const Key('splitToggle')));
        await h.settle(t, frames: 3);
        expect(h.c.isSplitPayment.value, isFalse);
        expect(find.byKey(const Key('method-cash')), findsOneWidget);
      },
    );
  });

  group('Charge → success view', () {
    sTest(
      'a completed sale opens the success view with the receipt number and total; New sale returns to a clean POS screen',
      (t) async {
        await openPayment(t);
        h.stubCreateSale(
          (_) async => (
            success: true,
            sale: completed(number: 'S-0007'),
            message: null,
            queued: false,
          ),
        );
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 14);
        expect(h.c.lastOutcome.value, SaleOutcome.completed);
        expect(find.byType(SaleSuccessView), findsOneWidget);
        expect(find.text('Sale complete'), findsOneWidget);
        expect(find.text('Receipt S-0007'), findsOneWidget);
        expect(
          t.widget<AmountText>(find.byKey(const Key('successTotal'))).text,
          h.c.lastReceipt.value!.total,
        );
        expect(
          find.text('Amount due'),
          findsNothing,
          reason: 'the payment sheet closed',
        );
        // actions
        expect(
          t.widget<AppButton>(find.byKey(const Key('printAgain'))).onPressed,
          isNotNull,
        );
        expect(
          t.widget<AppButton>(find.byKey(const Key('shareReceipt'))).onPressed,
          isNotNull,
        );
        await t.tap(find.byKey(const Key('newSale')));
        await h.settle(t, frames: 10);
        expect(find.byType(SaleSuccessView), findsNothing);
        expect(find.text('Quick Sale'), findsOneWidget);
        expect(h.c.hasItems, isFalse);
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest(
      'Print again with no printer set up says so instead of failing silently',
      (t) async {
        await openPayment(t);
        h.stubCreateSale(
          (_) async =>
              (success: true, sale: completed(), message: null, queued: false),
        );
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 14);
        await t.tap(find.byKey(const Key('printAgain')));
        await h.settle(t, frames: 4);
        expect(
          find.text('No printer set up. Go to Settings → Receipt Printer.'),
          findsOneWidget,
        );
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest(
      'a sale saved offline shows the OFF- number and the "Saved offline" state, not a normal success',
      (t) async {
        await openPayment(t);
        final tmp = (await t.runAsync(
          () => Directory.systemTemp.createTemp('pos_pay_'),
        ))!;
        final store = PendingSaleLocalStore(
          dbPath: '${tmp.path}/q.db',
          cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 9))),
        );
        Get.put<PendingSaleSyncService>(
          PendingSaleSyncService(
            posRepository: h.repo,
            localStore: store,
            currentStoreId: () async => 'store-1',
            currentDeviceId: () async => 'dev-AAAAAA',
            persistLastSync: false,
          ),
        );
        h.stubCreateSale((inv) async {
          final key = inv.namedArguments[#idempotencyKey] as String;
          await store.enqueue(key, {
            'storeId': 'store-1',
            'sessionId': 'session-1',
            'items': [],
            'clientTotal': 10.0,
            'clientCreatedAt': '2026-11-02T10:00:00.000Z',
            'idempotencyKey': key,
          }, deviceShort: 'AAAAAA');
          return (success: false, sale: null, message: null, queued: true);
        });
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.runAsync(() async {
          await t.tap(find.byKey(const Key('confirmCharge')));
          await Future<void>.delayed(const Duration(milliseconds: 400));
        });
        await h.settle(t, frames: 14);
        expect(h.c.lastOutcome.value, SaleOutcome.queuedOffline);
        expect(find.byType(SaleSuccessView), findsOneWidget);
        expect(find.text('Saved offline'), findsOneWidget);
        expect(find.text('Sale complete'), findsNothing);
        expect(find.byKey(const Key('successSubtitle')), findsOneWidget);
        expect(
          t.widget<Text>(find.byKey(const Key('successSubtitle'))).data,
          contains('sync automatically'),
        );
        expect(find.textContaining('Receipt OFF-'), findsOneWidget);
        await t.runAsync(() async {
          await store.close();
          await tmp.delete(recursive: true);
        });
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest(
      'offline without a receipt (could not be built): "Saved offline", Print and Share disabled',
      (t) async {
        await openPayment(t);
        h.stubCreateSale(
          (_) async =>
              (success: false, sale: null, message: null, queued: true),
        );
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 14);
        expect(find.text('Saved offline'), findsOneWidget);
        expect(find.byKey(const Key('receiptNumber')), findsNothing);
        expect(
          t.widget<AppButton>(find.byKey(const Key('printAgain'))).onPressed,
          isNull,
        );
        expect(
          t.widget<AppButton>(find.byKey(const Key('shareReceipt'))).onPressed,
          isNull,
        );
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest(
      'a FAILED charge never shows the success view: the sheet stays open and the same sale can be retried',
      (t) async {
        await openPayment(t);
        var attempt = 0;
        h.stubCreateSale((_) async {
          attempt++;
          return attempt == 1
              ? (
                  success: false,
                  sale: null,
                  message: 'Insufficient stock',
                  queued: false,
                )
              : (
                  success: true,
                  sale: completed(),
                  message: null,
                  queued: false,
                );
        });
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 10);
        expect(h.c.lastOutcome.value, isNull);
        expect(find.byType(SaleSuccessView), findsNothing);
        expect(
          find.text('Amount due'),
          findsOneWidget,
          reason: 'still on the payment sheet',
        );
        expect(h.c.hasItems, isTrue);
        await t.tap(find.byKey(const Key('confirmCharge')));
        await h.settle(t, frames: 14);
        expect(find.byType(SaleSuccessView), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
      },
    );
  });

  group(
    'the server quote changes the total (confirm dialog inside completeSale)',
    () {
      PosQuote quote(double total) => PosQuote(
        subtotal: total,
        discount: 0,
        tax: 0,
        total: total,
        taxRate: 0,
        currency: 'USD',
        currencyExponent: 2,
        settingsVersion: 5,
        unitPrices: {'a_v1': total},
      );

      sTest(
        'confirm → charges the NEW total; the sheet (not the dialog, not the POS screen) closes; success opens',
        (t) async {
          await openPayment(t);
          h.stubQuote(() => (quote: quote(12), message: null, code: null));
          h.stubCreateSale(
            (_) async => (
              success: true,
              sale: completed(total: 12),
              message: null,
              queued: false,
            ),
          );
          await t.tap(find.byKey(const Key('quick-20.00')));
          await t.pump(const Duration(milliseconds: 50));
          await t.tap(find.byKey(const Key('confirmCharge')));
          await h.settle(t, frames: 6);
          expect(find.text('Total updated'), findsOneWidget);
          expect(
            h.calls,
            isEmpty,
            reason: 'nobody is charged before the cashier confirms',
          );
          await t.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Charge ${Money.format(12)}'),
            ),
          );
          await h.settle(t, frames: 14);
          expect(h.calls.single[#clientTotal], 12.0);
          expect(find.text('Total updated'), findsNothing);
          expect(find.text('Amount due'), findsNothing);
          expect(find.byType(SaleSuccessView), findsOneWidget);
          await t.pump(const Duration(seconds: 5));
        },
      );

      sTest(
        'cancel → nothing is charged, no success view, the sheet stays with the refreshed total',
        (t) async {
          await openPayment(t);
          h.stubQuote(() => (quote: quote(12), message: null, code: null));
          h.stubCreateSale(
            (_) async => (
              success: true,
              sale: completed(total: 12),
              message: null,
              queued: false,
            ),
          );
          await t.tap(find.byKey(const Key('quick-20.00')));
          await t.pump(const Duration(milliseconds: 50));
          await t.tap(find.byKey(const Key('confirmCharge')));
          await h.settle(t, frames: 6);
          await t.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.text('Cancel'),
            ),
          );
          await h.settle(t, frames: 8);
          expect(h.calls, isEmpty);
          expect(h.c.lastOutcome.value, isNull);
          expect(find.byType(SaleSuccessView), findsNothing);
          expect(find.text('Amount due'), findsOneWidget);
          expect(
            h.c.total,
            12,
            reason: 'the cart was brought in line with the server',
          );
          await t.pump(const Duration(seconds: 5));
        },
      );
    },
  );

  group('safety while charging', () {
    sTest(
      'the payment sheet cannot be closed (button, system back) while a charge is in flight',
      (t) async {
        await openPayment(t);
        final gate = Completer<SaleResult>();
        h.stubCreateSale((_) => gate.future);
        await t.tap(find.byKey(const Key('quick-10.00')));
        await t.pump(const Duration(milliseconds: 50));
        await t.tap(find.byKey(const Key('confirmCharge')));
        await t.pump(const Duration(milliseconds: 200));
        expect(h.c.isChargingOrHolding.value, isTrue);
        expect(
          t.widget<IconButton>(find.byKey(const Key('paymentClose'))).onPressed,
          isNull,
        );
        await t.binding.handlePopRoute(); // Android back
        await t.pump(const Duration(milliseconds: 400));
        expect(find.text('Amount due'), findsOneWidget, reason: 'still open');
        gate.complete((
          success: true,
          sale: completed(),
          message: null,
          queued: false,
        ));
        await h.settle(t, frames: 14);
        expect(find.byType(SaleSuccessView), findsOneWidget);
        await t.pump(const Duration(seconds: 5));
      },
    );

    sTest('when idle the sheet closes with its X and the cart is untouched', (
      t,
    ) async {
      await openPayment(t);
      await t.tap(find.byKey(const Key('paymentClose')));
      await h.settle(t, frames: 6);
      expect(find.text('Amount due'), findsNothing);
      expect(h.c.hasItems, isTrue);
      expect(find.text('Quick Sale'), findsOneWidget);
    });
  });

  group('keyboard-wedge barcode scanner', () {
    Future<void> scan(WidgetTester t, String code) async {
      const keys = {
        '0': LogicalKeyboardKey.digit0,
        '1': LogicalKeyboardKey.digit1,
        '2': LogicalKeyboardKey.digit2,
        '3': LogicalKeyboardKey.digit3,
        '4': LogicalKeyboardKey.digit4,
        '5': LogicalKeyboardKey.digit5,
        '6': LogicalKeyboardKey.digit6,
        '7': LogicalKeyboardKey.digit7,
        '8': LogicalKeyboardKey.digit8,
        '9': LogicalKeyboardKey.digit9,
      };
      for (final ch in code.split('')) {
        await t.sendKeyDownEvent(keys[ch]!, character: ch);
        await t.sendKeyUpEvent(keys[ch]!);
      }
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump(const Duration(milliseconds: 100));
    }

    void stubBarcode() => when(
      () => h.repo.getProductByBarcode(
        storeId: any(named: 'storeId'),
        barcode: any(named: 'barcode'),
      ),
    ).thenAnswer((_) async => h.products[1]);

    sTest('a scan on the sale screen adds the product', (t) async {
      await h.mount(t, size: wide);
      stubBarcode();
      await scan(t, '4006381333931');
      verify(
        () => h.repo.getProductByBarcode(
          storeId: 'store-1',
          barcode: '4006381333931',
        ),
      ).called(1);
      expect(h.c.cartItems.single.product.productId, 'b');
    });

    sTest(
      'a scan while the PAYMENT sheet is open adds nothing (the scanner is disarmed behind any sheet)',
      (t) async {
        await openPayment(t);
        stubBarcode();
        expect(Get.isBottomSheetOpen, isTrue);
        final before = h.c.itemCount;
        await scan(t, '4006381333931');
        verifyNever(
          () => h.repo.getProductByBarcode(
            storeId: any(named: 'storeId'),
            barcode: any(named: 'barcode'),
          ),
        );
        expect(h.c.itemCount, before);
      },
    );

    sTest('…nor behind the hold confirm sheet', (t) async {
      await h.mount(t, size: wide);
      h.addLine(h.products[0]);
      await h.settle(t);
      stubBarcode();
      await t.tap(find.byKey(const Key('holdButton')));
      await h.settle(t);
      await scan(t, '4006381333931');
      verifyNever(
        () => h.repo.getProductByBarcode(
          storeId: any(named: 'storeId'),
          barcode: any(named: 'barcode'),
        ),
      );
    });
  });
}
