import 'dart:async';

import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';

/// A cipher that does nothing — the QR store only needs SOME [SealedText] in tests (the real one needs the Keychain).
class NoopCipher implements QueueCipher {
  static String get prefix => AesGcmQueueCipher.currentPrefix; // SealedText only opens text that carries the real prefix
  @override
  Future<String> encrypt(String plain) async => '$prefix$plain';
  @override
  Future<String> decrypt(String cipher) async => cipher.substring(prefix.length);
}

PendingQrStore memoryQrStore() => PendingQrStore(sealed: SealedText(cipher: NoopCipher()));

final DateTime serverNow = DateTime.utc(2026, 11, 5, 12, 0, 0);

PosPaymentIntent fakeIntent(
  String id, {
  PosQrStatus status = PosQrStatus.presented,
  int secondsLeft = 180,
  int amountMinor = 150000,
  bool paidAfterExpiry = false,
  DateTime? at,
  String? saleAttemptKey,
}) {
  final now = at ?? serverNow;
  return PosPaymentIntent(
    id: id,
    status: status,
    amountMinor: amountMinor,
    currency: 'PKR',
    currencyExponent: 2,
    qrPayload: 'mock-raast://pay/$id?am=$amountMinor',
    expiresAt: now.add(Duration(seconds: secondsLeft)),
    serverTime: now,
    paidAfterExpiry: paidAfterExpiry,
    saleAttemptKey: saleAttemptKey,
  );
}

/// Scripted payments server. `create` answers come from [createAnswers] (or a default fresh intent); `get` answers from [getScript]
/// (the last one repeats). Records every call so tests can assert "exactly one create" for double taps, resume, etc.
class FakePaymentsRepo extends PosPaymentsRepository {
  FakePaymentsRepo();

  final List<PaymentCall> createAnswers = [];
  final List<PaymentCall> getScript = [];
  final List<PaymentCall> cancelAnswers = [];
  Duration createDelay = Duration.zero;

  final createCalls = <({int amountMinor, String key, String? attempt, String sessionId})>[];
  final getCalls = <String>[];
  final cancelCalls = <String>[];
  final cancelAttemptCalls = <String>[];
  final presentedCalls = <String>[];
  final simulateCalls = <String>[];
  int _n = 0;

  static PaymentCall ok(PosPaymentIntent i) => (intent: i, code: null, message: null, connectivityError: false);
  static PaymentCall offline() => (intent: null, code: null, message: null, connectivityError: true);
  static PaymentCall refused(String code, [String? message]) => (intent: null, code: code, message: message, connectivityError: false);

  @override
  Future<PaymentCall> createIntent({required int amountMinor, required String sessionId, required String idempotencyKey, String? saleAttemptKey, String? storeId, String? mockScenario}) async {
    createCalls.add((amountMinor: amountMinor, key: idempotencyKey, attempt: saleAttemptKey, sessionId: sessionId));
    if (createDelay > Duration.zero) await Future<void>.delayed(createDelay);
    if (createAnswers.isNotEmpty) return createAnswers.removeAt(0);
    return ok(fakeIntent('pi-${++_n}', amountMinor: amountMinor, saleAttemptKey: saleAttemptKey));
  }

  @override
  Future<PaymentCall> getIntent(String id) async {
    getCalls.add(id);
    if (getScript.isEmpty) return ok(fakeIntent(id));
    return getScript.length > 1 ? getScript.removeAt(0) : getScript.first;
  }

  @override
  Future<PaymentCall> markPresented(String id) async {
    presentedCalls.add(id);
    return ok(fakeIntent(id));
  }

  @override
  Future<PaymentCall> cancel(String id) async {
    cancelCalls.add(id);
    if (cancelAnswers.isNotEmpty) return cancelAnswers.removeAt(0);
    return ok(fakeIntent(id, status: PosQrStatus.cancelled));
  }

  @override
  Future<({bool ok, List<String> cancelled, List<String> confirmed})> cancelAttempt(String saleAttemptKey) async {
    cancelAttemptCalls.add(saleAttemptKey);
    return (ok: true, cancelled: const <String>[], confirmed: const <String>[]);
  }

  @override
  Future<bool> mockSimulate(String intentId, String scenario) async {
    simulateCalls.add('$intentId:$scenario');
    return true;
  }

  final List<PosAttentionItem> attentionItems = [];
  PosKybStatus? kyb;

  @override
  Future<({List<PosAttentionItem> items, bool ok})> attention({String? storeId}) async => (items: List.of(attentionItems), ok: true);

  @override
  Future<PosKybStatus?> verification({String? storeId}) async => kyb;

  final reconcileCalls = <Map<String, Object?>>[];
  PaymentCall reconcileAnswer = ok(fakeIntent('pi-r', status: PosQrStatus.confirmed));

  @override
  Future<PaymentCall> reconcile(String intentId, {required String resolution, String? saleId, String? saleNumber, String? note, String? idempotencyKey}) async {
    reconcileCalls.add({'id': intentId, 'resolution': resolution, 'saleId': saleId, 'saleNumber': saleNumber, 'note': note});
    return reconcileAnswer;
  }
}

/// Polls [cond] every few ms (real time) — the QR controller uses real short timers in tests.
Future<bool> until(bool Function() cond, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    if (cond()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return cond();
}
