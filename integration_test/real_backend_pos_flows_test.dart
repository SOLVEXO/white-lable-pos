// REAL end-to-end: the app's own repositories/services/Dio stack against the REAL local backend (solvexo-api dev stack:
// real Mongo replica set, Redis, guards, idempotency, money rules). No repository fakes, no mocked HTTP.
// Run:  tool/run_real_e2e.sh   (starts the control sidecar; needs `npm run dev:stack:up && npm run dev:seed` in solvexo-api)
// Scope note: these drive the app's data/service layer exactly as its controllers do (PIN-controller persistence, the
// queue, entitlement, device service); they do not tap widgets — see real_backend_ui_test.dart for the UI-level pass.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/repositories/account_repository.dart';
import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/owner_session.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/receipt_data.dart';

import 'support/real_backend.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Api owner;
  late String storeId, registerId;

  setUpAll(() async {
    await Control.call('/health');
    owner = await Api.ownerLogin(ownerEmail, ownerPassword);
    final s = await owner.mainStore();
    storeId = s.storeId;
    registerId = s.registerId;
    await owner.revokeAllDevices(storeId); // devices leaked by earlier runs (the backend caps a store at 50 active)
    // dev data drifts as flows sell it: make sure the limited items are well stocked
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    await t.setUpDevice(name: 'stock probe');
    await t.pinLogin(managerEmail, managerPin);
    final v = await t.variantsBySku();
    await owner.topUp(storeId, v['DEV-LATTE']!.variantId, v['DEV-LATTE']!.stock, 60);
    await owner.topUp(storeId, v['DEV-BEANS']!.variantId, v['DEV-BEANS']!.stock, 30);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till({String role = 'manager'}) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(), DeviceSetupResult.ok);
    await t.pinLogin(role == 'manager' ? managerEmail : cashierEmail, role == 'manager' ? managerPin : cashierPin);
    return t;
  }

  // ── 1 · device setup ─────────────────────────────────────────────────────────────────────────────────────────────
  testWidgets('1 device setup: wrong password refused; owner login → register → device token replaces the owner JWT', (tester) async {
    await Till.boot(storeId: storeId, registerId: registerId);
    final bad = await AuthRepository().login(email: ownerEmail, password: 'wrong-password');
    expect(bad, isNull, reason: 'a wrong owner password is refused by the real backend');
    expect(AppPreferences.cachedToken ?? '', isEmpty);

    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(name: 'Setup test till'), DeviceSetupResult.ok);
    expect(AppPreferences.cachedDeviceMode, isTrue);
    final reg = await AppPreferences.getDeviceRegistration();
    expect(reg.storeId, storeId);
    expect(reg.registerId, registerId);
    expect(reg.name, 'Setup test till');
    expect(await AppPreferences.getRefreshToken(), isNull, reason: "the owner's refresh token is dropped on registration");
    // the backend lists exactly this device as active
    final list = await owner.devices(storeId);
    final mine = list.where((d) => d['_id'] == reg.deviceId || d['deviceId'] == reg.deviceId).toList();
    expect(mine, isNotEmpty, reason: 'device visible to the owner: $list');
    expect(mine.first['status'], 'active');
    await t.dispose();
  });

  // ── 2 · employee PIN login ───────────────────────────────────────────────────────────────────────────────────────
  testWidgets('2 PIN login: wrong PIN refused with a message and no token; cashier and manager sign in with their roles', (tester) async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(), DeviceSetupResult.ok);
    final wrong = await t.repo.pinLogin(storeId: storeId, email: cashierEmail, pin: '9999');
    expect(wrong.success, isFalse);
    expect(wrong.employeeToken, isNull);
    expect(wrong.message, isNotNull, reason: 'the server explains the failure');
    final c = await t.pinLogin(cashierEmail, cashierPin);
    expect(c.role, 'cashier');
    final m = await t.pinLogin(managerEmail, managerPin);
    expect(m.role, 'manager');
    expect(await AppPreferences.getPosEmployeeToken(), isNotEmpty);
    await t.dispose();
  });

  // ── 3 · shift + sale with a manager discount ─────────────────────────────────────────────────────────────────────
  testWidgets('3 sale with 10% manager discount: server totals, stock decrement, receipt; cashier cannot discount; wrong clientTotal rejected', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final stockBefore = await t.stockOf('DEV-LATTE');
    final line = await t.line('DEV-LATTE', 2);

    final res = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id,
      items: [line], discountType: 'percent', discountValue: 10, clientTotal: 9.9,
      paymentMethod: 'cash', amountTendered: 20, status: 'completed',
    );
    expect(res.success, isTrue, reason: res.message ?? 'sale failed');
    final sale = res.sale!;
    expect(sale.subtotal, 10.0);
    expect(sale.discount, 1.0);
    expect(sale.tax, 0.9, reason: '10% tax on the discounted subtotal, computed by the server');
    expect(sale.total, 9.9);
    expect(sale.changeGiven, 10.1);
    expect(sale.currency, 'USD');
    expect(sale.status, 'completed');
    expect(await t.stockOf('DEV-LATTE'), stockBefore - 2, reason: 'server decremented stock');

    final receipt = ReceiptData.fromSale(sale, null);
    expect(receipt.receiptNumber, sale.saleNumber);
    expect(receipt.total, contains('9.90'));
    expect(receipt.discountLabel, contains('10%'));
    expect(receipt.change, isNotNull);

    // a client total that disagrees with the server's maths is refused (TOTAL_MISMATCH), nothing recorded
    final mismatch = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id,
      items: [line], clientTotal: 1.0, paymentMethod: 'cash', amountTendered: 20, status: 'completed',
    );
    expect(mismatch.success, isFalse);
    expect(mismatch.queued, isFalse, reason: 'a definite rejection is never queued');
    expect(await t.stockOf('DEV-LATTE'), stockBefore - 2, reason: 'rejected sale took no stock');

    // a CASHIER's token cannot apply a discount (manager-only, enforced server-side)
    await t.pinLogin(cashierEmail, cashierPin);
    final denied = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id,
      items: [await t.line('DEV-LATTE', 1)], discountType: 'percent', discountValue: 10,
      paymentMethod: 'cash', amountTendered: 10, status: 'completed',
    );
    expect(denied.success, isFalse, reason: 'cashier discount must be refused by the backend');
    expect(await t.stockOf('DEV-LATTE'), stockBefore - 2);
    await t.pinLogin(managerEmail, managerPin);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 4 · split tender ─────────────────────────────────────────────────────────────────────────────────────────────
  testWidgets('4 split tender card+cash: payments sum to the server total, change computed server-side, report breaks it down', (tester) async {
    final t = await till();
    final session = await t.openShift();
    final items = [await t.line('DEV-BEANS', 1), await t.line('DEV-REFILL', 1)]; // 24 + 2.50 = 26.50 → tax 2.65 → 29.15
    final q = await t.repo.quoteSale(storeId: storeId, items: items);
    expect(q.quote, isNotNull, reason: q.message);
    final total = q.quote!.total;
    expect(total, 29.15);
    final res = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: items, clientTotal: total,
      paymentMethod: 'cash', status: 'completed',
      payments: [
        {'method': 'card', 'amount': 20.0, 'reference': 'AUTH-E2E'},
        {'method': 'cash', 'amount': 15.0},
      ],
    );
    expect(res.success, isTrue, reason: res.message ?? '');
    final sale = res.sale!;
    expect(sale.isSplit, isTrue);
    expect(sale.paymentLines.fold<double>(0, (a, p) => a + p.amount), closeTo(29.15, 0.001));
    expect(sale.changeGiven, 5.85);
    expect(sale.paymentLines.firstWhere((p) => p.method == 'card').reference, 'AUTH-E2E');
    final report = await t.repo.getSessionReport(session.id);
    expect(report!.byPaymentMethod.card.total, 20.0);
    expect(report.byPaymentMethod.cash.total, 9.15);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 5 · refund (partial, per tender) and void ───────────────────────────────────────────────────────────────────
  testWidgets('5 refund + void: partial refund goes card-first then cash, stock restored, expected cash follows; void restores stock', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final items = [await t.line('DEV-LATTE', 2)]; // 10.00 + 1.00 tax = 11.00
    final stock0 = await t.stockOf('DEV-LATTE');
    final res = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: items, clientTotal: 11.0,
      paymentMethod: 'cash', status: 'completed',
      payments: [
        {'method': 'card', 'amount': 4.0, 'reference': 'R-1'},
        {'method': 'cash', 'amount': 7.0, 'tendered': 7.0},
      ],
    );
    expect(res.success, isTrue, reason: res.message ?? '');
    final sale = res.sale!;
    expect(await t.stockOf('DEV-LATTE'), stock0 - 2);

    // refund ONE of the two lattes: 5.00 + 0.50 tax = 5.50 → documented order: card (4.00) first, then cash (1.50)
    final itemId = sale.items.first.saleItemId!;
    final ref = await t.repo.refundSale(sale.id, items: [{'saleItemId': itemId, 'qty': 1}]);
    expect(ref.success, isTrue, reason: ref.message ?? '');
    expect(ref.refundedAmount, 5.5);
    expect(ref.newStatus, 'partially_refunded');
    expect(ref.tenders.map((e) => '${e.method}:${e.amount}').toList(), ['card:4.0', 'cash:1.5']);
    expect(await t.stockOf('DEV-LATTE'), stock0 - 1, reason: 'the returned latte went back on the shelf');
    final afterRefund = await t.repo.getSessionReport(session.id);
    // cash that stayed in the drawer = 100 opening + 7.00 cash tender − 1.50 cash handed back
    final cf = afterRefund!.cashFlow;
    expect(cf.openingCash + cf.cashSales + cf.cashIn - cf.cashOut, 105.5);

    // void a second sale: stock back, status voided
    final second = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-LATTE', 1)],
      clientTotal: 5.5, paymentMethod: 'cash', amountTendered: 10, status: 'completed',
    );
    expect(second.success, isTrue);
    final stockAfterSecond = await t.stockOf('DEV-LATTE');
    expect(stockAfterSecond, stock0 - 2);
    expect(await t.repo.voidSale(second.sale!.id, reason: 'e2e void'), isTrue);
    expect(await t.stockOf('DEV-LATTE'), stock0 - 1);
    expect((await t.repo.getSaleById(second.sale!.id))!.isVoided, isTrue);

    // a cashier cannot refund or void (manager-only)
    await t.pinLogin(cashierEmail, cashierPin);
    expect((await t.repo.refundSale(sale.id, items: [{'saleItemId': itemId, 'qty': 1}])).success, isFalse);
    await t.pinLogin(managerEmail, managerPin);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 6 · offline sale → API really down → reconnect → sync ────────────────────────────────────────────────────────
  testWidgets('6 offline: API stopped → cash sale queued under its key → API back → sync creates exactly one offline sale', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final stock0 = await t.stockOf('DEV-LATTE');
    final line = await t.line('DEV-LATTE', 1);
    const key = 'e2e-offline-key-0001';
    final key1 = '$key-${DateTime.now().millisecondsSinceEpoch}';
    final madeAt = DateTime.now();

    await Control.stopApi();
    try {
      final q = await t.repo.createSale(
        storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientCreatedAt: madeAt,
        paymentMethod: 'cash', amountTendered: 10, status: 'completed', idempotencyKey: key1,
      );
      expect(q.success, isFalse);
      expect(q.queued, isTrue, reason: 'no route to the server → persisted locally, never lost');
      expect(t.sync.unresolvedCount.value, 1);
      final store = PendingSaleLocalStore();
      final row = await store.getById(key1);
      expect(row, isNotNull);
      expect(row!.payload['offline'], isTrue);
      expect(row.payload['idempotencyKey'], key1);
    } finally {
      await Control.startApi();
    }

    await t.sync.syncNow(ignoreBackoff: true);
    await eventually(() async => t.sync.unresolvedCount.value == 0, reason: 'queue drained after reconnect');
    final sales = await t.repo.getSales(storeId: storeId, sessionId: session.id);
    expect(sales.items.length, 1, reason: 'exactly one sale, not zero, not two');
    final sale = sales.items.first;
    expect(sale.isOffline, isTrue);
    expect(sale.saleNumber, startsWith('POS-'), reason: 'the real server receipt number');
    expect(await t.stockOf('DEV-LATTE'), stock0 - 1);
    // a second replay of the same key (e.g. app killed after the server answered) must not duplicate
    final replay = await t.repo.submitRawSale(queuedPayload(key1, session.id, registerId, t.employee!.id, line, madeAt, storeId));
    expect(replay.success, isTrue);
    expect((await t.repo.getSales(storeId: storeId, sessionId: session.id)).items.length, 1, reason: 'same key replayed → still one sale');
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 7 · idempotent retry ─────────────────────────────────────────────────────────────────────────────────────────
  testWidgets('7 idempotent retry: the same key twice returns the original sale — one sale, stock taken once', (tester) async {
    final t = await till();
    final session = await t.openShift();
    final stock0 = await t.stockOf('DEV-LATTE');
    final line = await t.line('DEV-LATTE', 1);
    final key = 'e2e-idem-${DateTime.now().microsecondsSinceEpoch}';
    Future<({bool success, dynamic sale, String? message, bool queued})> go() => t.repo.createSale(
          storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line],
          clientTotal: 5.5, paymentMethod: 'cash', amountTendered: 10, status: 'completed', idempotencyKey: key,
        );
    final a = await go();
    final b = await go();
    expect(a.success && b.success, isTrue);
    expect(b.sale.id, a.sale.id, reason: 'the retry got the ORIGINAL sale back');
    expect(b.sale.saleNumber, a.sale.saleNumber);
    expect((await t.repo.getSales(storeId: storeId, sessionId: session.id)).items.length, 1);
    expect(await t.stockOf('DEV-LATTE'), stock0 - 1, reason: 'stock decremented once');
    final rep = await t.repo.getSessionReport(session.id);
    expect(rep!.session.totalTransactions, 1);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 8 · close shift ──────────────────────────────────────────────────────────────────────────────────────────────
  testWidgets('8 close shift: expectedCash = opening + cash sales − cash refunds, counted == expected → variance 0; a wrong count shows the variance', (tester) async {
    final t = await till();
    final s1 = await t.openShift(openingCash: 50);
    final cash1 = await t.repo.createSale(storeId: storeId, sessionId: s1.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-LATTE', 2)], clientTotal: 11.0, paymentMethod: 'cash', amountTendered: 20, status: 'completed');
    final cash2 = await t.repo.createSale(storeId: storeId, sessionId: s1.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-BEANS', 1)], clientTotal: 26.4, paymentMethod: 'cash', amountTendered: 30, status: 'completed');
    expect(cash1.success && cash2.success, isTrue, reason: '${cash1.message} ${cash2.message}');
    final ref = await t.repo.refundSale(cash1.sale!.id, items: [{'saleItemId': cash1.sale!.items.first.saleItemId, 'qty': 1}]); // 5.50 back in cash
    expect(ref.success, isTrue, reason: ref.message ?? '');
    final expected = 50 + 11.0 + 26.4 - 5.5;
    final rep = await t.repo.getSessionReport(s1.id);
    final cf = rep!.cashFlow;
    expect(cf.openingCash + cf.cashSales + cf.cashIn - cf.cashOut, closeTo(expected, 0.001), reason: 'report maths: opening + cash sales (net of cash refunds)');
    final closed = await t.repo.closeSession(sessionId: s1.id, closingCash: expected);
    expect(closed.success, isTrue, reason: closed.message ?? '');
    expect(closed.session!.expectedCash, closeTo(expected, 0.001), reason: 'server expectedCash matches the independent calculation');
    expect(closed.session!.cashDifference, closeTo(0, 0.001));
    expect(closed.session!.isOpen, isFalse);

    // next shift: count $2 short → the server records the variance
    final s2 = await t.openShift(openingCash: 20);
    final r2 = await t.repo.closeSession(sessionId: s2.id, closingCash: 18);
    expect(r2.session!.cashDifference, closeTo(-2, 0.001));
    await t.dispose();
  });

  // ── 9 · plan expiry → restricted mode → restore ──────────────────────────────────────────────────────────────────
  testWidgets('9 plan expiry: restricted (cannot sell/open; can read, refund, close); restoring brings selling back', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final latte = await t.line('DEV-LATTE', 1); // fetched now: the product catalogue is switched off once the plan lapses
    final made = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [latte], clientTotal: 5.5, paymentMethod: 'cash', amountTendered: 10, status: 'completed');
    expect(made.success, isTrue);
    await Control.expirePlan();
    try {
      expect(await t.entitlement.checkPlan(storeId: storeId), isTrue, reason: 'the backend says the plan is not active → app enters restricted mode');
      // selling is refused by the server (and the app notes it)
      expect((await t.repo.getProducts(storeId)).items, isEmpty, reason: 'catalogue refused without a plan');
      final blocked = await t.repo.createSale(storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [latte], clientTotal: 5.5, paymentMethod: 'cash', amountTendered: 10, status: 'completed');
      expect(blocked.success, isFalse);
      expect(blocked.queued, isFalse);
      // reading, refunding and closing still work (never trap cash in an open drawer)
      expect((await t.repo.getSessionReport(session.id)), isNotNull);
      expect((await t.repo.getSaleById(made.sale!.id))!.saleNumber, made.sale!.saleNumber);
      final ref = await t.repo.refundSale(made.sale!.id);
      expect(ref.success, isTrue, reason: 'refund after expiry is allowed: ${ref.message}');
      final cur = await t.repo.getSessionReport(session.id);
      final closed = await t.repo.closeSession(sessionId: session.id, closingCash: cur!.cashFlow.openingCash + cur.cashFlow.cashSales + cur.cashFlow.cashIn - cur.cashFlow.cashOut);
      expect(closed.success, isTrue, reason: 'close after expiry is allowed: ${closed.message}');
      // …but a new shift cannot be opened
      final open = await t.repo.openSession(storeId: storeId, registerId: registerId, employeeId: t.employee!.id, openingCash: 10);
      expect(open.success, isFalse, reason: 'cannot open a session without an active plan');
    } finally {
      await Control.restorePlan();
    }
    expect(await t.entitlement.checkPlan(storeId: storeId), isFalse, reason: 'plan active again → normal mode');
    final s = await t.openShift();
    final ok = await t.repo.createSale(storeId: storeId, sessionId: s.id, registerId: registerId, employeeId: t.employee!.id, items: [await t.line('DEV-LATTE', 1)], clientTotal: 5.5, paymentMethod: 'cash', amountTendered: 10, status: 'completed');
    expect(ok.success, isTrue, reason: ok.message ?? '');
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 10 · device revocation keeps the queue ───────────────────────────────────────────────────────────────────────
  testWidgets('10 device revoked by the owner: next call → credentials cleared, store binding + queued sale kept; re-register uploads it', (tester) async {
    final t = await till();
    final session = await t.openShift();
    final reg = await AppPreferences.getDeviceRegistration();
    final line = await t.line('DEV-LATTE', 1);
    final key = 'e2e-revoke-${DateTime.now().microsecondsSinceEpoch}';
    final stock0 = await t.stockOf('DEV-LATTE');
    // a sale waiting in the queue (as if made offline before the revocation)
    await t.sync.enqueue(key, queuedPayload(key, session.id, registerId, t.employee!.id, line, DateTime.now(), storeId));
    final store = PendingSaleLocalStore();
    final before = await store.getById(key);
    expect(before, isNotNull);

    // the owner removes the device (real API call, owner JWT)
    final r = await owner.post('/api/pos/devices/$storeId/${reg.deviceId}/revoke');
    expect(r.statusCode, anyOf(200, 201), reason: '${r.data}');
    // the device's next call is answered POS_DEVICE_REVOKED → the Dio layer routes it to the device service
    await t.repo.getProducts(storeId);
    await eventually(() async => t.devices.revokedNotice.value != null, reason: 'device service told it was revoked');
    expect(AppPreferences.cachedDeviceMode, isFalse, reason: 'credentials cleared after revocation');
    final kept = await AppPreferences.getDeviceRegistration();
    expect(kept.storeId, storeId, reason: 'store binding kept');
    expect(await store.getById(key), isNotNull, reason: 'the queued sale is still on the device');
    await t.sync.syncNow(ignoreBackoff: true);
    expect(await store.getById(key), isNotNull, reason: 'no credentials → nothing sent, nothing dropped');

    // owner registers the device again for the SAME store → queue uploads by itself (onRegistered → syncNow)
    expect(await t.setUpDevice(name: 'E2E iPhone (again)'), DeviceSetupResult.ok);
    await eventually(() async => await store.getById(key) == null, reason: 'queued sale uploaded after re-registration');
    await t.pinLogin(managerEmail, managerPin);
    final sales = await t.repo.getSales(storeId: storeId, sessionId: session.id);
    expect(sales.items.length, 1);
    expect(await t.stockOf('DEV-LATTE'), stock0 - 1);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  // ── 11 · account deletion (dedicated throwaway owner) ───────────────────────────────────────────────────────────
  testWidgets('11 account deletion from the app: throwaway owner, password re-auth → pending_deletion, device revoked', (tester) async {
    final o = await Control.throwawayOwner();
    final email = o['email'] as String, password = o['password'] as String;
    final t = await Till.boot(storeId: o['storeId'] as String, registerId: o['registerId'] as String);
    expect(await t.setUpDevice(email: email, password: password, name: 'Doomed till'), DeviceSetupResult.ok);
    expect(AppPreferences.cachedDeviceMode, isTrue);

    // owner-only route on a registered device: needs the owner's in-memory session (password re-authentication)
    final tok = await AuthRepository().verifyOwnerPassword(email: email, password: password);
    expect(tok, isNotNull);
    OwnerSession.start(tok!);
    final account = AccountRepository();
    final methods = await account.authMethods();
    expect(methods.hasPassword, isTrue);
    final wrong = await account.requestDeletion(password: 'not-the-password');
    expect(wrong.outcome, DeletionOutcome.wrongPassword);

    final done = await account.requestDeletion(password: password);
    expect(done.outcome, DeletionOutcome.requested);
    expect(done.scheduledFor, isNotNull);
    expect(done.scheduledFor!.isAfter(DateTime.now().add(const Duration(days: 29))), isTrue, reason: '30-day grace');

    // independent proof against the API: the account is pending deletion, its sessions are dead, the device is revoked
    final api = await Api.ownerLogin(email, password); // signing in during the grace period is allowed (to cancel)
    final st = await api.get('/api/seller/account-deletion');
    expect(st.data['data']['pending'], isTrue);
    final devs = await api.devices(o['storeId'] as String);
    expect(devs.where((d) => d['status'] == 'active'), isEmpty, reason: 'every device revoked at the request: $devs');
    await t.repo.getProducts(o['storeId'] as String); // the doomed device's token is now refused
    await eventually(() async => !AppPreferences.cachedDeviceMode, reason: 'device told it is revoked');
    // restore the grace-period account so re-runs of this suite stay independent
    final cancel = await api.post('/api/seller/account-deletion/cancel');
    expect(cancel.statusCode, anyOf(200, 201));
    await t.dispose();
  });
}

/// The payload shape PosRepository.createSale queues on a connectivity failure (offline replay).
Map<String, dynamic> queuedPayload(String key, String sessionId, String registerId, String employeeId, Map<String, dynamic> line, DateTime madeAt, String storeId) => {
      'storeId': storeId, 'sessionId': sessionId, 'registerId': registerId, 'employeeId': employeeId, 'items': [line],
      'clientCreatedAt': madeAt.toUtc().toIso8601String(), 'paymentMethod': 'cash', 'amountTendered': 10, 'customerName': 'Walk-in',
      'status': 'completed', 'idempotencyKey': key, 'offline': true,
    };
