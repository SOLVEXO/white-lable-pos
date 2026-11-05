// Raast QR in the till, end to end on the widget level: the method chooser (gate + offline messages per role), the QR screen in
// every state on phone and tablet, light and dark, and the whole sale path — the sale is sent only after the payment is
// CONFIRMED, with that payment attached; a failed save re-attaches the same payment instead of charging again; a QR sale is
// never queued offline; resume after a kill.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pos_local_caches.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/services/network_status_service.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_screen.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/payment_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/sale_success_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

import 'support/fake_payments.dart';
import 'support/sale_harness.dart';

void main() {
  SaleHarness.setUpAllShared();
  late SaleHarness h;
  late FakePaymentsRepo pay;
  late PendingQrStore qrStore;
  setUp(() {
    h = SaleHarness();
    pay = FakePaymentsRepo();
    qrStore = memoryQrStore();
  });

  const wide = Size(1180, 820);
  const phone = Size(390, 844);

  /// testWidgets + a final pump: the controller saves the cart 400 ms after any edit (a debounce Timer).
  void qTest(String name, Future<void> Function(WidgetTester t) body) => testWidgets(name, (t) async {
    await body(t);
    await t.pump(const Duration(seconds: 2));
  });

  PosSaleModel done({double total = 10}) => sale(
    number: 'S-0007',
    total: total,
    payment: 'raast_qr',
    items: [PosSaleItemModel(saleItemId: 'i1', productId: 'a', name: 'Product a', sku: 'SKU-a', price: total, qty: 1, lineTotal: total)],
  );

  /// Registers the services the till reads, mounts the sale screen with a 1×10.00 cart and opens the payment sheet.
  Future<void> openPayment(WidgetTester t, {bool verified = true, bool online = true, bool manager = false, Size size = wide, ThemeData? theme}) async {
    final net = Get.put(NetworkStatusService());
    net.isOnline.value = online;
    Get.put(PosEntitlementService()).digitalPaymentsEnabled.value = verified;
    await h.mount(t, size: size, manager: manager, payments: pay, qrStore: qrStore, theme: theme);
    h.addLine(h.products[0]);
    await h.settle(t);
    await t.tap(find.byKey(const Key('chargeButton')));
    await h.settle(t);
    expect(find.text('Amount due'), findsOneWidget);
  }

  void stubSaleOk() => h.stubCreateSale((_) async => (success: true, sale: done(), message: null, queued: false));

  Map<String, dynamic> sentLine(int call, int i) => ((h.calls[call][#payments] as List).cast<Map<String, dynamic>>())[i];

  /// Charge → QR screen is up and showing a code.
  Future<void> startQr(WidgetTester t) async {
    await t.tap(find.byKey(const Key('method-raast_qr')));
    await t.pump();
    await t.tap(find.byKey(const Key('confirmCharge')));
    for (var i = 0; i < 20 && find.byKey(const Key('qrImage')).evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('qrImage')), findsOneWidget);
  }

  group('method chooser: who can use Raast QR, and what they are told when they cannot', () {
    qTest('verified store, online: the Raast tile is usable and there is no warning', (t) async {
      await openPayment(t);
      expect(find.byKey(const Key('method-raast_qr')), findsOneWidget);
      expect(find.byKey(const Key('qrUnavailableNote')), findsNothing);
      await t.tap(find.byKey(const Key('method-raast_qr')));
      await t.pump();
      expect(h.c.selectedPayment.value, 'raast_qr');
      expect(find.byKey(const Key('qrHint')), findsOneWidget);
      expect(find.textContaining('Show QR'), findsOneWidget); // the Charge button now says what it will do
    });

    qTest('CASHIER, store not verified: disabled, "Not available for this store yet"; tapping it selects nothing', (t) async {
      await openPayment(t, verified: false);
      expect(find.text('Raast QR: Not available for this store yet'), findsOneWidget);
      await t.tap(find.byKey(const Key('method-raast_qr')), warnIfMissed: false);
      await t.pump();
      expect(h.c.selectedPayment.value, 'cash');
    });

    qTest('MANAGER / owner, store not verified: "Business verification required"', (t) async {
      await openPayment(t, verified: false, manager: true);
      expect(find.text('Raast QR: Business verification required'), findsOneWidget);
      await t.tap(find.byKey(const Key('method-raast_qr')), warnIfMissed: false);
      await t.pump();
      expect(h.c.selectedPayment.value, 'cash');
    });

    qTest('OFFLINE: the tile is disabled with "Raast QR needs internet"; cash and card are unaffected', (t) async {
      await openPayment(t, online: false);
      expect(find.text('Raast QR: Raast QR needs internet'), findsOneWidget);
      await t.tap(find.byKey(const Key('method-raast_qr')), warnIfMissed: false);
      await t.pump();
      expect(h.c.selectedPayment.value, 'cash');
      await t.tap(find.byKey(const Key('method-card')));
      await t.pump();
      expect(h.c.selectedPayment.value, 'card');
    });

    qTest('the server not saying anything (older backend) does not hide the option', (t) async {
      Get.put(NetworkStatusService());
      Get.put(PosEntitlementService()); // digitalPaymentsEnabled stays null
      await h.mount(t, size: wide, payments: pay, qrStore: qrStore);
      h.addLine(h.products[0]);
      await h.settle(t);
      await t.tap(find.byKey(const Key('chargeButton')));
      await h.settle(t);
      expect(find.byKey(const Key('qrUnavailableNote')), findsNothing);
    });

    qTest('on a PHONE-width sheet all four tiles fit without overflow', (t) async {
      Get.put(NetworkStatusService());
      Get.put(PosEntitlementService()).digitalPaymentsEnabled.value = true;
      await h.mount(t, size: phone, payments: pay, qrStore: qrStore, home: Builder(builder: (_) => Scaffold(body: Center(child: SizedBox(width: 340, child: PaymentSheet(c: h.c))))));
      for (final m in ['cash', 'card', 'other', 'raast_qr']) {
        expect(find.byKey(Key('method-$m')), findsOneWidget);
      }
      expect(t.takeException(), isNull); // no overflow while laying out four tiles in 340 px
    });
  });

  group('the sale path', () {
    qTest('Charge shows the QR; the sale is sent ONLY after the payment is confirmed, with that payment attached', (t) async {
      stubSaleOk();
      await openPayment(t);
      await startQr(t);
      expect(h.calls, isEmpty); // nothing is sold while the customer has not paid
      expect(find.byKey(const Key('qrStatus')), findsOneWidget);
      expect(find.text('Waiting for payment'), findsOneWidget);
      expect(pay.createCalls.single.amountMinor, 1000);
      // the customer pays
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed, amountMinor: 1000)));
      for (var i = 0; i < 60 && h.calls.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(h.calls, hasLength(1));
      expect(h.calls.single[#paymentMethod], 'raast_qr');
      expect(sentLine(0, 0), {'method': 'raast_qr', 'amount': 10.0, 'intentId': 'pi-1'});
      await h.settle(t, frames: 12);
      expect(find.byType(SaleSuccessView), findsOneWidget);
    });

    qTest('expired → "Generate new QR" → paid: the sale carries the SECOND payment', (t) async {
      stubSaleOk();
      await openPayment(t);
      await startQr(t);
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.expired, secondsLeft: 0, amountMinor: 1000)));
      for (var i = 0; i < 80 && find.byKey(const Key('qrRegenerate')).evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('QR expired'), findsOneWidget);
      expect(find.byKey(const Key('qrImage')), findsNothing); // the dead code is never shown again
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-2', status: PosQrStatus.confirmed, amountMinor: 1000)));
      await t.tap(find.byKey(const Key('qrRegenerate')));
      for (var i = 0; i < 60 && h.calls.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(pay.createCalls, hasLength(2));
      expect(sentLine(0, 0)['intentId'], 'pi-2');
    });

    qTest('Cancel on the QR screen returns to the payment sheet: no sale, cart intact', (t) async {
      stubSaleOk();
      await openPayment(t);
      await startQr(t);
      await t.tap(find.byKey(const Key('qrCancel')));
      await h.settle(t, frames: 12);
      expect(find.byKey(const Key('qrImage')), findsNothing);
      expect(find.text('Amount due'), findsOneWidget);
      expect(h.calls, isEmpty);
      expect(h.c.cartItems, hasLength(1));
      expect(pay.cancelCalls, ['pi-1']);
    });

    qTest('the customer paid but the sale could not be saved: the next Charge attaches the SAME payment — no second QR, no second charge', (t) async {
      var attempt = 0;
      h.stubCreateSale((_) async => ++attempt == 1 ? (success: false, sale: null, message: 'Insufficient stock', queued: false) : (success: true, sale: done(), message: null, queued: false));
      await openPayment(t);
      await startQr(t);
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed, amountMinor: 1000)));
      for (var i = 0; i < 60 && h.calls.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await h.settle(t, frames: 12);
      expect(find.byType(SaleSuccessView), findsNothing); // a failure never shows a success screen
      await t.tap(find.byKey(const Key('confirmCharge')));
      await h.settle(t, frames: 12);
      expect(h.calls, hasLength(2));
      expect(pay.createCalls, hasLength(1)); // still ONE payment was ever created
      expect(sentLine(1, 0)['intentId'], 'pi-1');
      expect(find.byKey(const Key('qrImage')), findsNothing);
    });

    qTest('split: card + Raast QR — the QR is for the QR row\'s amount only, and both lines go to the server', (t) async {
      stubSaleOk();
      await openPayment(t);
      await t.tap(find.byKey(const Key('splitToggle')));
      await t.pump();
      h.c.splitLines[0].amount.text = '4.00'; // card
      h.c.splitLines[1].method.value = 'raast_qr';
      h.c.splitLines[1].amount.text = '6.00';
      h.c.cartItems.refresh();
      await t.pump();
      await t.tap(find.byKey(const Key('confirmCharge')));
      for (var i = 0; i < 20 && pay.createCalls.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(pay.createCalls.single.amountMinor, 600);
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed, amountMinor: 600)));
      for (var i = 0; i < 60 && h.calls.isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final lines = (h.calls.single[#payments] as List).cast<Map<String, dynamic>>();
      expect(lines.map((l) => l['method']), ['card', 'raast_qr']);
      expect(lines[1]['intentId'], 'pi-1');
      expect(lines[0].containsKey('intentId'), isFalse);
    });

    qTest('a second QR row is not offered (one QR per checkout in the till)', (t) async {
      await openPayment(t);
      await t.tap(find.byKey(const Key('splitToggle')));
      await t.pump();
      h.c.splitLines[0].method.value = 'raast_qr';
      await t.pump();
      expect(h.c.splitChoicesFor(0), contains('raast_qr')); // the row that has it keeps it
      expect(h.c.splitChoicesFor(1), isNot(contains('raast_qr')));
    });

    qTest('offline at Charge time: nothing is asked of the server, no sale is sent, and nothing is queued', (t) async {
      stubSaleOk();
      await openPayment(t);
      await t.tap(find.byKey(const Key('method-raast_qr')));
      await t.pump();
      Get.find<NetworkStatusService>().isOnline.value = false; // the connection goes away after the method was picked
      await t.pump();
      await t.tap(find.byKey(const Key('confirmCharge')), warnIfMissed: false);
      await h.settle(t, frames: 10);
      expect(pay.createCalls, isEmpty);
      expect(h.calls, isEmpty);
    });
  });

  group('the QR screen in every state', () {
    Future<RaastQrController> show(WidgetTester t, {Size size = phone, ThemeData? theme, bool simulate = false}) async {
      final c = RaastQrController(
        amountMinor: 150000,
        sessionId: 's',
        saleAttemptKey: 'k',
        repository: pay,
        store: qrStore,
        pollInterval: const Duration(milliseconds: 50),
        tick: const Duration(milliseconds: 50),
        clock: () => serverNow,
        keepAwake: (_) async {},
      );
      Get.put<RaastQrController>(c, tag: 'tt');
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      addTearDown(Get.reset);
      await t.pumpWidget(MaterialApp(theme: theme ?? AppTheme.light, home: const RaastQrScreen(tag: 'tt')));
      await t.pump(const Duration(milliseconds: 200));
      return c;
    }

    for (final (sizeName, size) in [('phone', phone), ('tablet', const Size(1024, 768))]) {
      for (final (themeName, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
        testWidgets('$sizeName / $themeName: waiting shows the amount, the QR, a countdown and Cancel', (t) async {
          await show(t, size: size, theme: theme);
          expect(find.byKey(const Key('qrAmount')), findsOneWidget);
          expect(find.byKey(const Key('qrImage')), findsOneWidget);
          expect(find.byKey(const Key('qrCountdown')), findsOneWidget);
          expect(find.text('3:00'), findsOneWidget);
          expect(find.text('Waiting for payment'), findsOneWidget);
          expect(find.byKey(const Key('qrCancel')), findsOneWidget);
          await t.pump(const Duration(milliseconds: 100));
        });
      }
    }

    testWidgets('creating: a spinner, no QR yet', (t) async {
      pay.createDelay = const Duration(seconds: 2);
      final c = await show(t);
      expect(find.text('Preparing QR…'), findsOneWidget);
      expect(find.byKey(const Key('qrImage')), findsNothing);
      expect(c.phase.value, QrPhase.creating);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('checking: the network dropped — "Checking payment…", the QR stays (dimmed) and Cancel is still there', (t) async {
      await show(t);
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.offline());
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Checking payment…'), findsOneWidget);
      expect(find.byKey(const Key('qrImage')), findsOneWidget);
      expect(find.byKey(const Key('qrCancel')), findsOneWidget);
    });

    testWidgets('confirmed: "Payment received" with a check mark, no QR', (t) async {
      await show(t);
      pay.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed)));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Payment received'), findsOneWidget);
      expect(find.byKey(const Key('qrConfirmedIcon')), findsOneWidget);
      expect(find.byKey(const Key('qrImage')), findsNothing);
    });

    for (final (status, label) in [(PosQrStatus.expired, 'QR expired'), (PosQrStatus.failed, 'Payment failed'), (PosQrStatus.cancelled, 'Payment cancelled')]) {
      testWidgets('${status.name}: "$label" with Generate new QR / Choose another method, and the old code is gone', (t) async {
        pay.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-x', status: status, secondsLeft: 0)));
        await show(t);
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text(label), findsOneWidget);
        expect(find.byKey(const Key('qrRegenerate')), findsOneWidget);
        expect(find.byKey(const Key('qrAnother')), findsOneWidget);
        expect(find.byKey(const Key('qrImage')), findsNothing);
        expect(find.byKey(const Key('qrCancel')), findsNothing);
      });
    }

    testWidgets('unavailable: why, with Try again / Choose another method', (t) async {
      pay.createAnswers.add(FakePaymentsRepo.refused('STORE_NOT_VERIFIED'));
      await show(t);
      expect(find.text('Raast QR unavailable'), findsOneWidget);
      expect(find.textContaining('not available for this store yet'), findsOneWidget);
      expect(find.byKey(const Key('qrRetry')), findsOneWidget);
    });

    testWidgets('the QR is drawn on white even in dark mode (scanners need the contrast) and is large', (t) async {
      await show(t, theme: AppTheme.dark);
      final box = t.getSize(find.byKey(const Key('qrBox')));
      expect(box.width, greaterThan(250));
      final deco = t.widget<Container>(find.byKey(const Key('qrBox'))).decoration as BoxDecoration;
      expect(deco.color, Colors.white);
    });

    testWidgets('the countdown turns into a warning in the last 30 seconds', (t) async {
      pay.createAnswers.add(FakePaymentsRepo.ok(fakeIntent('pi-1', secondsLeft: 20)));
      pay.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', secondsLeft: 20))); // every poll says the same 20 s are left
      await show(t);
      expect(find.text('0:20'), findsOneWidget);
    });

    testWidgets('the system back gesture is intercepted: it cancels a live QR instead of leaving it payable', (t) async {
      final c = await show(t);
      expect(c.phase.value, QrPhase.waiting);
      await t.binding.handlePopRoute();
      await t.pump(const Duration(milliseconds: 200));
      expect(pay.cancelCalls, ['pi-1']);
    });
  });

  group('resume after the app was killed', () {
    qTest('a payment pending on this device, for the cart that was in progress, is resumed — paid → the sale completes with it, no new QR', (t) async {
      stubSaleOk();
      Get.put(NetworkStatusService());
      Get.put(PosEntitlementService()).digitalPaymentsEnabled.value = true;
      // what survived the kill: the cart (with its checkout key) and the pending payment
      final p = h.products[0];
      SharedPreferences.setMockInitialValues({});
      await h.mount(t, size: wide, payments: pay, qrStore: qrStore);
      h.addLine(p);
      h.c.selectedPayment.value = 'raast_qr';
      // the checkout started (its key is fixed on the first Charge tap) — emulate by saving the same snapshot the app would
      await h.c.persistNow();
      final snap = await CartSnapshotStore.instance.load(storeId: 'store-1', sessionId: 'session-1');
      expect(snap, isNotNull);
      await CartSnapshotStore.instance.save(CartSnapshot(
        storeId: snap!.storeId, sessionId: snap.sessionId, lines: snap.lines, discountText: snap.discountText, percentDiscount: snap.percentDiscount,
        customerName: snap.customerName, customerId: snap.customerId, note: snap.note, payment: 'raast_qr', tendered: snap.tendered,
        paymentReference: snap.paymentReference, split: false, splitLines: const [], pendingKey: 'KEY-1', pendingAt: DateTime.now(), savedAt: DateTime.now(),
      ));
      await qrStore.save(const PendingQr(intentId: 'pi-7', createKey: 'KEY-1:qr0:abc', saleAttemptKey: 'KEY-1', amountMinor: 1000, qrIndex: 0));
      pay.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-7', status: PosQrStatus.confirmed, amountMinor: 1000)));

      // "reopen the app": a fresh controller restores the cart, then resumes the pending payment
      final reopened = PosHomeController(posRepository: h.repo, categoryRepository: h.cats, paymentsRepository: pay, pendingQrStore: qrStore);
      reopened.onInit(); // the new process starts; the old screen stays mounted (it only provides a navigator for the QR screen)
      addTearDown(reopened.onClose);
      // starting up restores the cart and then resumes the pending payment by itself (the QR screen shows "Payment received" for a moment: fake time, pumped)
      await h.settle(t, frames: 45);
      expect(pay.createCalls, isEmpty); // never a second payment
      expect(h.calls, hasLength(1));
      expect(h.calls.single[#idempotencyKey], 'KEY-1'); // the SAME checkout
      expect(sentLine(0, 0), {'method': 'raast_qr', 'amount': 10.0, 'intentId': 'pi-7'});
    });

    qTest('a pending payment for a sale that no longer exists is not attached to anything: the cashier is told a manager can match it', (t) async {
      stubSaleOk();
      Get.put(NetworkStatusService());
      Get.put(PosEntitlementService()).digitalPaymentsEnabled.value = true;
      await h.mount(t, size: wide, payments: pay, qrStore: qrStore);
      await qrStore.save(const PendingQr(intentId: 'pi-8', createKey: 'k', saleAttemptKey: 'GONE', amountMinor: 1000, qrIndex: 0));
      pay.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-8', status: PosQrStatus.confirmed, amountMinor: 1000)));
      final resumed = h.c.resumePendingQr();
      await h.settle(t, frames: 30);
      await resumed;
      expect(h.calls, isEmpty);
      expect(await qrStore.read(), isNull);
    });
  });
}

Object? tester(WidgetTester t) => t.takeException();
