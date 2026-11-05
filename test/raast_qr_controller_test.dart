// The Raast QR payment state machine: create → show → poll → confirmed / failed / expired / cancelled, and everything the
// till must survive on the way — the network dropping, a double tap, the app being killed, the till locking, a wrong device clock.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/qr/raast_qr_controller.dart';

import 'support/fake_payments.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePaymentsRepo repo;
  late PendingQrStore store;
  late List<bool> awake;
  late int nonce;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = FakePaymentsRepo();
    store = memoryQrStore();
    awake = [];
    nonce = 0;
  });

  RaastQrController make({PendingQr? resume, DateTime Function()? clock}) => RaastQrController(
    amountMinor: 150000,
    sessionId: 's-1',
    saleAttemptKey: 'sale-key-1',
    storeId: 'store-1',
    resumeFrom: resume,
    repository: repo,
    store: store,
    pollInterval: const Duration(milliseconds: 15),
    tick: const Duration(milliseconds: 15),
    clock: clock ?? (() => serverNow),
    keepAwake: (on) async => awake.add(on),
    nonce: () => 'n${++nonce}',
  );

  Future<RaastQrController> started(RaastQrController c) async {
    Get.put<RaastQrController>(c, tag: 't${identityHashCode(c)}'); // onInit → start()
    return c;
  }

  tearDown(Get.reset);

  group('create and show', () {
    test('asks for a QR for the exact amount, shows it as waiting, tells the server it is on screen, keeps the screen awake', () async {
      final c = await started(make());
      expect(c.phase.value, QrPhase.creating);
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      expect(repo.createCalls.single.amountMinor, 150000);
      expect(repo.createCalls.single.attempt, 'sale-key-1');
      expect(repo.createCalls.single.sessionId, 's-1');
      expect(repo.createCalls.single.key, startsWith('sale-key-1:qr0:'));
      expect(c.intent.value!.qrPayload, contains('pi-1'));
      expect(await until(() => repo.presentedCalls.isNotEmpty), isTrue);
      expect(awake.first, isTrue);
      expect((await store.read())!.intentId, 'pi-1');
    });

    test('the countdown comes from the SERVER clock: a device clock 3 hours wrong changes nothing', () async {
      final c = await started(make(clock: () => serverNow.subtract(const Duration(hours: 3))));
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      expect(c.secondsLeft.value, inInclusiveRange(178, 180));
      expect(c.totalSeconds.value, 180);
    });

    test('no QR can be made: not verified / no shift / offline are "unavailable" with a clear reason, and nothing stays pending', () async {
      for (final (call, text) in [
        (FakePaymentsRepo.refused('STORE_NOT_VERIFIED'), 'not available for this store yet'),
        (FakePaymentsRepo.refused('NO_OPEN_SESSION'), 'Open the shift'),
        (FakePaymentsRepo.offline(), 'internet'),
      ]) {
        repo.createAnswers.add(call);
        final c = make();
        await c.start();
        expect(c.phase.value, QrPhase.unavailable);
        expect(c.message.value, contains(text));
        expect(await store.read(), isNull);
        expect(c.debugTimersRunning, isFalse);
        c.onClose();
      }
    });
  });

  group('outcomes', () {
    test('confirmed: the result completes with the payment, polling stops, the payment stays remembered until the sale is saved', () async {
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.pending)));
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed)));
      final c = await started(make());
      final r = await c.result;
      expect(r.isConfirmed, isTrue);
      expect(r.intent!.id, 'pi-1');
      expect(c.phase.value, QrPhase.confirmed);
      expect(c.debugTimersRunning, isFalse);
      expect(awake.last, isFalse);
      expect((await store.read())!.intentId, 'pi-1'); // a kill right now must still resume to "paid"
    });

    test('paid after the QR had expired still ends as confirmed, with a note for the cashier', () async {
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed, paidAfterExpiry: true)));
      final c = await started(make());
      expect((await c.result).isConfirmed, isTrue);
      expect(c.message.value, contains('manager'));
    });

    test('expired → the old payment is over and forgotten; "Generate new QR" makes a NEW payment with a NEW key, which can then be paid', () async {
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.expired, secondsLeft: 0)));
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.expired), isTrue);
      expect(c.debugTimersRunning, isFalse);
      expect(await store.read(), isNull);
      repo.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-2', status: PosQrStatus.confirmed)));
      await c.regenerate();
      expect(repo.createCalls, hasLength(2));
      expect(repo.createCalls[0].key, isNot(repo.createCalls[1].key));
      expect((await c.result).intent!.id, 'pi-2');
    });

    test('failed and cancelled-by-server are shown, never confused with paid', () async {
      for (final s in [PosQrStatus.failed, PosQrStatus.cancelled]) {
        repo.createAnswers.add(FakePaymentsRepo.ok(fakeIntent('pi-x', status: s))); // the server already says it is over
        final c = make();
        await c.start();
        expect(c.phase.value, s == PosQrStatus.failed ? QrPhase.failed : QrPhase.cancelled);
        expect(c.debugTimersRunning, isFalse);
        c.onClose();
      }
    });

    test('Cancel releases the QR on the server; if the customer paid in that same moment the answer is "paid", not "cancelled"', () async {
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      await c.cancel();
      expect(repo.cancelCalls, ['pi-1']);
      expect(c.phase.value, QrPhase.cancelled);
      expect((await c.result).kind, QrResultKind.cancelled);
      expect(await store.read(), isNull);

      // the race: the server says "already confirmed"
      final c2 = await started(make());
      expect(await until(() => c2.phase.value == QrPhase.waiting), isTrue);
      repo.cancelAnswers.add(FakePaymentsRepo.refused('PAYMENT_ALREADY_CONFIRMED'));
      repo.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-2', status: PosQrStatus.confirmed)));
      await c2.cancel();
      expect((await c2.result).isConfirmed, isTrue);
    });

    test('Cancel that cannot reach the server does NOT pretend the QR is cancelled — it is still payable, so it keeps waiting', () async {
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      repo.cancelAnswers.add(FakePaymentsRepo.offline());
      await c.cancel();
      expect(c.phase.value, QrPhase.checking);
      expect(c.message.value, contains('still active'));
      expect(c.debugTimersRunning, isTrue);
    });
  });

  group('resilience', () {
    test('the network drops while waiting: "Checking payment…", polling continues, and when it returns the real state is shown (never "failed")', () async {
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      repo.getScript
        ..clear()
        ..add(FakePaymentsRepo.offline());
      expect(await until(() => c.phase.value == QrPhase.checking), isTrue);
      expect(c.phase.value, isNot(QrPhase.failed));
      expect(c.debugTimersRunning, isTrue);
      repo.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.confirmed)));
      expect((await c.result).isConfirmed, isTrue);
    });

    test('double taps do not double anything: start twice, regenerate twice, cancel twice → one create / one cancel', () async {
      repo.createDelay = const Duration(milliseconds: 40);
      final c = make();
      await Future.wait([c.start(), c.start(), c.start()]);
      expect(repo.createCalls, hasLength(1));
      repo.createDelay = Duration.zero;
      await c.regenerate();
      repo.createDelay = const Duration(milliseconds: 40);
      await Future.wait([c.regenerate(), c.regenerate()]);
      expect(repo.createCalls, hasLength(3)); // initial + two regenerations in sequence, not four
      repo.cancelAnswers.add(FakePaymentsRepo.ok(fakeIntent('x', status: PosQrStatus.cancelled)));
      await Future.wait([c.cancel(), c.cancel()]);
      expect(repo.cancelCalls, hasLength(1));
      c.onClose();
    });

    test('KILLED while waiting: the pending payment is looked up on reopen — a still-open QR is resumed, NO second payment is created', () async {
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      final pending = (await store.read())!; // what survives the kill
      Get.reset();
      repo.createCalls.clear();
      repo.getScript
        ..clear()
        ..add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.presented, secondsLeft: 90)));
      final resumed = await started(make(resume: pending));
      expect(await until(() => resumed.phase.value == QrPhase.waiting), isTrue);
      expect(repo.createCalls, isEmpty);
      expect(resumed.intent.value!.id, 'pi-1');
      expect(resumed.secondsLeft.value, inInclusiveRange(88, 90));
    });

    test('KILLED, and the customer paid meanwhile: reopening shows paid immediately', () async {
      final pending = PendingQr(intentId: 'pi-9', createKey: 'k', saleAttemptKey: 'sale-key-1', amountMinor: 150000, qrIndex: 0);
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-9', status: PosQrStatus.confirmed)));
      final c = await started(make(resume: pending));
      expect((await c.result).isConfirmed, isTrue);
      expect(repo.createCalls, isEmpty);
    });

    test('KILLED between "create sent" and "answer received": the retry reuses the SAME create key, so the server returns the SAME payment', () async {
      final pending = PendingQr(intentId: '', createKey: 'sale-key-1:qr0:abc', saleAttemptKey: 'sale-key-1', amountMinor: 150000, qrIndex: 0);
      final c = await started(make(resume: pending));
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      expect(repo.createCalls.single.key, 'sale-key-1:qr0:abc');
    });

    test('a pending payment the server no longer knows (or that is offline on reopen) is not blindly recreated', () async {
      final pending = PendingQr(intentId: 'gone', createKey: 'k', saleAttemptKey: 'sale-key-1', amountMinor: 150000, qrIndex: 0);
      repo.getScript.add(FakePaymentsRepo.offline());
      final off = make(resume: pending);
      await off.start();
      expect(off.phase.value, QrPhase.unavailable);
      expect(repo.createCalls, isEmpty);
      off.onClose();
    });

    test('the till LOCKS mid-payment (screen torn down): polling stops, the screen-awake lock is released, NOTHING is cancelled, and the payment is still remembered', () async {
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.waiting), isTrue);
      c.detach();
      expect((await c.result).kind, QrResultKind.detached);
      expect(c.debugTimersRunning, isFalse);
      expect(awake.last, isFalse);
      expect(repo.cancelCalls, isEmpty);
      expect((await store.read())!.intentId, 'pi-1');
    });

    test('"Choose another method" after an expired QR ends the attempt with the expiry, and forgets the pending payment', () async {
      repo.getScript.add(FakePaymentsRepo.ok(fakeIntent('pi-1', status: PosQrStatus.expired, secondsLeft: 0)));
      final c = await started(make());
      expect(await until(() => c.phase.value == QrPhase.expired), isTrue);
      await c.giveUp();
      expect((await c.result).kind, QrResultKind.expired);
      expect(await store.read(), isNull);
    });
  });

  group('pending-payment store', () {
    test('keeps only identifiers and the amount (sealed), is dropped when old, and survives a restart', () async {
      await store.save(const PendingQr(intentId: 'pi-1', createKey: 'k', saleAttemptKey: 'sale-key-1', amountMinor: 150000, qrIndex: 0));
      final raw = (await SharedPreferences.getInstance()).getString('pos_pending_qr')!;
      expect(raw, startsWith(NoopCipher.prefix));
      final again = await memoryQrStore().read();
      expect(again!.amountMinor, 150000);
      var now = DateTime.now();
      final aging = PendingQrStore(sealed: SealedText(cipher: NoopCipher()), clock: () => now);
      expect(await aging.read(), isNotNull);
      now = now.add(const Duration(hours: 3));
      expect(await aging.read(), isNull);
    });
  });
}

