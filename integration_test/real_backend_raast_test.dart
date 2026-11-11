// REAL end-to-end for Raast QR: the app's own QR controller + repositories against the REAL local backend (dev stack, MOCK payment
// provider, store business-verified by the seed). Needs the stack started with a short QR lifetime so expiry can be seen in seconds:
//   (solvexo-api)  E2E_QR_TTL=10 bash dev/up.sh && npm run dev:seed        then   tool/run_real_e2e.sh integration_test/real_backend_raast_test.dart
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:integration_test/integration_test.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';

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
    await owner.revokeAllDevices(storeId);
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    await t.setUpDevice(name: 'raast stock probe');
    await t.pinLogin(managerEmail, managerPin);
    final v = await t.variantsBySku();
    await owner.topUp(storeId, v['DEV-LATTE']!.variantId, v['DEV-LATTE']!.stock, 60);
    await t.closeAnyOpenShift();
    await t.dispose();
  });

  tearDown(() async => owner.revokeAllDevices(storeId));

  Future<Till> till() async {
    final t = await Till.boot(storeId: storeId, registerId: registerId);
    expect(await t.setUpDevice(), DeviceSetupResult.ok);
    await t.pinLogin(managerEmail, managerPin);
    return t;
  }

  /// The QR controller exactly as the till builds it (real repository, real pending-payment store, real timers, real wake-lock plugin).
  RaastQrController qr(Till t, String sessionId, String key, {int amountMinor = 1100}) {
    final c = RaastQrController(
      amountMinor: amountMinor,
      sessionId: sessionId,
      saleAttemptKey: key,
      storeId: storeId,
      repository: PosPaymentsRepository(),
      store: PendingQrStore.instance,
      pollInterval: const Duration(milliseconds: 700),
    );
    Get.put<RaastQrController>(c, tag: key);
    return c;
  }

  Future<Map<String, dynamic>> intentOf(String id) async => ((await owner.get('/api/pos/payments/intents/$id?storeId=$storeId')).data['data'] as Map).cast<String, dynamic>();

  // 10.00 + 10% tax = 11.00 USD = 1100 minor units (two DEV-LATTE at 5.00)
  testWidgets('1 full QR sale: QR created → customer pays (mock) → payment confirmed → sale completes with it; the payment is consumed; the drawer counts it as Raast; refund goes back through the provider', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final line = await t.line('DEV-LATTE', 2);
    final stockBefore = await t.stockOf('DEV-LATTE');
    final key = 'e2e-qr-${DateTime.now().millisecondsSinceEpoch}';

    final c = qr(t, session.id, key);
    await eventually(() async => c.phase.value == QrPhase.waiting, reason: 'QR shown');
    final created = await intentOf(c.intent.value!.id);
    expect(created, containsPair('status', anyOf('created', 'presented', 'pending'))); // 'pending' (provider acknowledged) is a waiting state too
    expect(created['amountMinor'], 1100);
    expect(created['currency'], 'USD');

    // nothing is sold while the customer has not paid: a sale with this payment is refused
    final early = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0,
      paymentMethod: 'raast_qr', payments: [{'method': 'raast_qr', 'amount': 11.0, 'intentId': c.intent.value!.id}], status: 'completed',
    );
    expect(early.success, isFalse, reason: 'an unconfirmed payment must not complete a sale');
    expect(await t.stockOf('DEV-LATTE'), stockBefore);

    await c.simulatePaid(); // the mock provider's "customer paid" webhook, through the real endpoint
    final result = await c.result;
    expect(result.isConfirmed, isTrue);
    final intentId = result.intent!.id;
    expect(c.phase.value, QrPhase.confirmed);

    final sold = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0,
      paymentMethod: 'raast_qr', payments: [{'method': 'raast_qr', 'amount': 11.0, 'intentId': intentId}], idempotencyKey: key, status: 'completed',
    );
    expect(sold.success, isTrue, reason: sold.message ?? 'sale failed');
    expect(sold.queued, isFalse);
    expect(sold.sale!.paymentMethod, 'raast_qr');
    expect(sold.sale!.paymentLines.single.method, 'raast_qr');
    expect(sold.sale!.paymentLines.single.reference, isNotNull, reason: 'the provider reference is on the sale');
    expect(await t.stockOf('DEV-LATTE'), stockBefore - 2);
    expect(await intentOf(intentId), containsPair('consumed', true));
    await PendingQrStore.instance.clear();

    // the same payment cannot settle a second sale
    final again = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0,
      paymentMethod: 'raast_qr', payments: [{'method': 'raast_qr', 'amount': 11.0, 'intentId': intentId}], status: 'completed',
    );
    expect(again.success, isFalse);

    // shift report: Raast is its own tender
    final report = (await owner.get('/api/pos/sessions/${session.id}/report')).data['data']['summary'] as Map;
    expect((report['byPaymentMethod'] as Map)['raast_qr'], containsPair('count', 1));

    // full refund (manager) → provider refund events
    final refund = await t.repo.refundSale(sold.sale!.id);
    expect(refund.success, isTrue, reason: refund.message ?? 'refund failed');
    await eventually(() async => (await intentOf(intentId))['refundStatus'] == 'full', reason: 'provider refund done');
    expect(await t.stockOf('DEV-LATTE'), stockBefore);
    Get.delete<RaastQrController>(tag: key, force: true);
    await t.dispose();
  });

  testWidgets('2 expiry → "Generate new QR" → customer pays the NEW QR → sale; the first QR stays expired and unused', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final line = await t.line('DEV-LATTE', 2);
    final key = 'e2e-qr-exp-${DateTime.now().millisecondsSinceEpoch}';

    final c = qr(t, session.id, key);
    await eventually(() async => c.phase.value == QrPhase.waiting, reason: 'QR shown');
    final firstId = c.intent.value!.id;
    expect(c.secondsLeft.value, lessThanOrEqualTo(10), reason: 'the dev stack runs a 10 s QR lifetime for this test');
    await eventually(() async => c.phase.value == QrPhase.expired, timeout: const Duration(seconds: 40), reason: 'QR expires on the server');
    expect(await intentOf(firstId), containsPair('status', 'expired'));

    await c.regenerate();
    await eventually(() async => c.phase.value == QrPhase.waiting && c.intent.value!.id != firstId, reason: 'new QR');
    final secondId = c.intent.value!.id;
    await c.simulatePaid();
    expect((await c.result).isConfirmed, isTrue);

    final sold = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0,
      paymentMethod: 'raast_qr', payments: [{'method': 'raast_qr', 'amount': 11.0, 'intentId': secondId}], idempotencyKey: key, status: 'completed',
    );
    expect(sold.success, isTrue, reason: sold.message ?? 'sale failed');
    expect(await intentOf(secondId), containsPair('consumed', true));
    expect(await intentOf(firstId), containsPair('consumed', false));
    await PendingQrStore.instance.clear();
    await t.repo.refundSale(sold.sale!.id);
    Get.delete<RaastQrController>(tag: key, force: true);
    await t.dispose();
  });

  testWidgets('3 the customer pays AFTER the QR expired: recorded as paid, listed in Needs attention; the manager attaches it to a sale by receipt number', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final line = await t.line('DEV-LATTE', 2);
    final key = 'e2e-qr-late-${DateTime.now().millisecondsSinceEpoch}';
    final payments = PosPaymentsRepository();

    final c = qr(t, session.id, key);
    await eventually(() async => c.phase.value == QrPhase.waiting, reason: 'QR shown');
    final lateId = c.intent.value!.id;
    await eventually(() async => c.phase.value == QrPhase.expired, timeout: const Duration(seconds: 40), reason: 'QR expires');
    await c.giveUp(); // the cashier chose another method (cash)

    // … and the customer scans the old QR anyway
    expect(await payments.mockSimulate(lateId, 'confirm'), isTrue);
    await eventually(() async => (await intentOf(lateId))['paidAfterExpiry'] == true, reason: 'late payment recorded as confirmed');
    expect(await intentOf(lateId), containsPair('status', 'confirmed'));
    final inbox = await payments.attention(storeId: storeId);
    final item = inbox.items.singleWhere((i) => i.intentId == lateId);
    expect(item.reason, PosAttentionReason.paidAfterExpiry);
    expect(item.saleAttemptKey, key, reason: 'attached to the original checkout attempt');

    // the sale was rung up as cash; the manager matches the money to it
    final cash = await t.repo.createSale(
      storeId: storeId, sessionId: session.id, registerId: registerId, employeeId: t.employee!.id, items: [line], clientTotal: 11.0,
      paymentMethod: 'cash', amountTendered: 20, status: 'completed',
    );
    expect(cash.success, isTrue, reason: cash.message ?? 'cash sale failed');
    final attached = await payments.reconcile(lateId, resolution: 'sale_recorded', saleNumber: cash.sale!.saleNumber, note: 'e2e: matched at the till', idempotencyKey: 'e2e-att-$lateId');
    expect(attached.intent, isNotNull, reason: attached.message ?? 'attach failed');
    expect((await payments.attention(storeId: storeId)).items.where((i) => i.intentId == lateId), isEmpty);
    expect(await intentOf(lateId), containsPair('attention', isEmpty));
    await t.repo.refundSale(cash.sale!.id);
    Get.delete<RaastQrController>(tag: key, force: true);
    await t.dispose();
  });

  testWidgets('4 the till is killed while a QR is waiting: the pending payment is found again and resumed — no second QR — and then completes', (tester) async {
    final t = await till();
    final session = await t.openShift(openingCash: 100);
    final key = 'e2e-qr-kill-${DateTime.now().millisecondsSinceEpoch}';

    final c = qr(t, session.id, key);
    await eventually(() async => c.phase.value == QrPhase.waiting, reason: 'QR shown');
    final id = c.intent.value!.id;
    c.detach(); // the process dies / the till locks: nothing is cancelled
    Get.delete<RaastQrController>(tag: key, force: true);

    final pending = await PendingQrStore.instance.read();
    expect(pending, isNotNull);
    expect(pending!.intentId, id);
    final resumed = RaastQrController(
      amountMinor: pending.amountMinor, sessionId: session.id, saleAttemptKey: pending.saleAttemptKey, qrIndex: pending.qrIndex, storeId: storeId,
      resumeFrom: pending, repository: PosPaymentsRepository(), store: PendingQrStore.instance, pollInterval: const Duration(milliseconds: 700),
    );
    Get.put<RaastQrController>(resumed, tag: '$key-resumed');
    await eventually(() async => resumed.phase.value == QrPhase.waiting, reason: 'resumed');
    expect(resumed.intent.value!.id, id, reason: 'the SAME payment, not a new one');
    await resumed.simulatePaid();
    expect((await resumed.result).isConfirmed, isTrue);
    await PendingQrStore.instance.clear();
    // leave the confirmed-but-unused payment for a manager to resolve, so the dev data stays clean for the next run
    final payments = PosPaymentsRepository();
    await eventually(() async => (await payments.attention(storeId: storeId)).items.any((i) => i.intentId == id && i.reason == PosAttentionReason.confirmedUnattached), reason: 'paid-but-unattached shows up for a manager');
    final r = await payments.reconcile(id, resolution: 'resolved', note: 'e2e: test payment, nothing to match', idempotencyKey: 'e2e-res-$id');
    expect(r.intent, isNotNull, reason: r.message ?? 'resolve failed');
    Get.delete<RaastQrController>(tag: '$key-resumed', force: true);
    await t.dispose();
  });
}
