import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pending_qr_store.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_payments_repository.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Where a QR payment stands, as the till shows it.
enum QrPhase {
  /// asking the server for a QR
  creating,

  /// QR on screen, waiting for the customer
  waiting,

  /// the network dropped while waiting — "Checking payment…" — polling continues until the server answers
  checking,
  confirmed,
  failed,
  expired,
  cancelled,

  /// no QR could be made (offline, store not verified, no open shift …): [RaastQrController.message] says why
  unavailable,
}

/// [detached]: the screen went away without the cashier choosing (the till locked): nothing was cancelled, the pending payment resumes later.
enum QrResultKind { confirmed, cancelled, failed, expired, unavailable, detached }

class QrResult {
  const QrResult(this.kind, {this.intent, this.message});
  final QrResultKind kind;
  final PosPaymentIntent? intent;
  final String? message;
  bool get isConfirmed => kind == QrResultKind.confirmed;
}

/// Drives ONE QR payment: create (or resume) → show → poll → confirmed / failed / expired / cancelled.
///
/// The server decides every status; this class only asks. Nothing here can mark a payment paid. Rules it enforces for the till:
///  * a double tap never makes a second payment (every action is guarded; creation is idempotent by key),
///  * the countdown is computed from the SERVER's clock (offset learned from each response),
///  * a network drop while waiting keeps polling and shows "Checking payment…" — it never turns into "failed",
///  * the pending payment is remembered ([PendingQrStore]) so killing the app or locking the till resumes it,
///  * the screen is kept awake while waiting.
class RaastQrController extends GetxController {
  RaastQrController({
    required this.amountMinor,
    required this.sessionId,
    required this.saleAttemptKey,
    this.qrIndex = 0,
    this.storeId,
    this.resumeFrom,
    PosPaymentsRepository? repository,
    PendingQrStore? store,
    Duration pollInterval = const Duration(seconds: 2),
    Duration tick = const Duration(seconds: 1),
    DateTime Function()? clock,
    Future<void> Function(bool on)? keepAwake,
    String Function()? nonce,
    this.mockScenario,
  })  : _repo = repository ?? PosPaymentsRepository(),
        _store = store ?? PendingQrStore.instance,
        _pollInterval = pollInterval,
        _tick = tick,
        _now = clock ?? DateTime.now,
        _keepAwake = keepAwake ?? ((on) => on ? WakelockPlus.enable() : WakelockPlus.disable()),
        _nonce = nonce ?? _randomNonce;

  final int amountMinor;
  final String sessionId;
  final String saleAttemptKey;
  final int qrIndex;
  final String? storeId;
  final String? mockScenario;

  /// A payment found on this device after a restart: look it up instead of creating a new one.
  final PendingQr? resumeFrom;

  final PosPaymentsRepository _repo;
  final PendingQrStore _store;
  final Duration _pollInterval;
  final Duration _tick;
  final DateTime Function() _now;
  final Future<void> Function(bool on) _keepAwake;
  final String Function() _nonce;

  static String _randomNonce() {
    final r = Random.secure();
    return List.generate(8, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  final Rx<QrPhase> phase = QrPhase.creating.obs;
  final Rxn<PosPaymentIntent> intent = Rxn<PosPaymentIntent>();
  final RxInt secondsLeft = 0.obs;

  /// The QR's full lifetime in seconds as first seen (for the progress bar); reset when a new QR is made.
  final RxInt totalSeconds = 0.obs;
  final RxString message = ''.obs;

  /// True while a cancel / regenerate is in flight — the buttons ignore taps (no double action).
  final RxBool busy = false.obs;

  final Completer<QrResult> _done = Completer<QrResult>();
  Future<QrResult> get result => _done.future;

  Timer? _pollTimer;
  Timer? _tickTimer;
  bool _polling = false;
  bool _starting = false;
  Duration _serverOffset = Duration.zero; // serverTime − deviceNow, at the last response
  String? _createKey;

  @override
  void onInit() {
    super.onInit();
    start();
  }

  /// Creates the QR (or resumes the pending one). Safe to call twice: the second call is ignored while one is running.
  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    phase.value = QrPhase.creating;
    message.value = '';
    try {
      unawaited(_keepAwake(true).catchError((_) {}));
      final resume = resumeFrom;
      if (resume != null && resume.intentId.isNotEmpty) {
        final r = await _repo.getIntent(resume.intentId);
        if (r.intent != null) {
          _createKey = resume.createKey;
          _adopt(r.intent!);
          return;
        }
        if (r.connectivityError) {
          _fail(QrPhase.unavailable, 'Needs internet to check this payment.');
          return;
        }
        await _store.clear(); // the server does not know it any more: start clean below
      }
      _createKey = (resume != null && resume.intentId.isEmpty) ? resume.createKey : '$saleAttemptKey:qr$qrIndex:${_nonce()}';
      await _store.save(PendingQr(intentId: '', createKey: _createKey!, saleAttemptKey: saleAttemptKey, amountMinor: amountMinor, qrIndex: qrIndex));
      final r = await _repo.createIntent(
        amountMinor: amountMinor,
        sessionId: sessionId,
        idempotencyKey: _createKey!,
        saleAttemptKey: saleAttemptKey,
        storeId: storeId,
        mockScenario: mockScenario,
      );
      if (r.intent == null) {
        await _store.clear();
        _fail(QrPhase.unavailable, _createMessage(r.code, r.message, r.connectivityError));
        return;
      }
      await _store.save(PendingQr(intentId: r.intent!.id, createKey: _createKey!, saleAttemptKey: saleAttemptKey, amountMinor: amountMinor, qrIndex: qrIndex));
      _adopt(r.intent!);
      unawaited(_repo.markPresented(r.intent!.id));
    } finally {
      _starting = false;
    }
  }

  static String _createMessage(String? code, String? message, bool offline) {
    if (offline) return 'Raast QR needs an internet connection.';
    // G6.1: the server's words first (a real provider's reasons need no app update); the app's text only when the server sent none
    if ((message ?? '').trim().isNotEmpty) return message!.trim();
    switch (code) {
      case 'STORE_NOT_VERIFIED':
        return 'Raast QR is not available for this store yet.';
      case 'NO_OPEN_SESSION':
        return 'Open the shift before taking a QR payment.';
      case 'EMPLOYEE_SESSION_REQUIRED':
        return 'Sign in with your PIN to take a QR payment.';
      case 'POS_PLAN_REQUIRED':
        return 'The POS plan is not active for this store.';
      default:
        return message ?? 'Could not create the QR code. Try again.';
    }
  }

  void _fail(QrPhase p, String msg) {
    phase.value = p;
    message.value = msg;
    _stopTimers();
    unawaited(_keepAwake(false).catchError((_) {}));
    _complete(QrResult(p == QrPhase.unavailable ? QrResultKind.unavailable : QrResultKind.failed, message: msg), keepResult: p != QrPhase.unavailable);
  }

  void _complete(QrResult r, {bool keepResult = true}) {
    if (!_done.isCompleted && keepResult) _done.complete(r);
  }

  /// Takes the server's view of the payment, moves the phase, and (re)starts polling / the countdown while it is open.
  void _adopt(PosPaymentIntent i) {
    intent.value = i;
    _serverOffset = i.serverTime.difference(_now());
    _recount();
    switch (i.status) {
      case PosQrStatus.confirmed:
        phase.value = QrPhase.confirmed;
        message.value = '';
        _stopTimers();
        unawaited(_keepAwake(false).catchError((_) {}));
        if (i.paidAfterExpiry) message.value = 'Paid after the QR expired — a manager will match it to the sale.';
        _complete(QrResult(QrResultKind.confirmed, intent: i));
        return;
      case PosQrStatus.failed:
        _terminal(QrPhase.failed, QrResultKind.failed, 'The payment failed.');
        return;
      case PosQrStatus.expired:
        _terminal(QrPhase.expired, QrResultKind.expired, 'This QR code expired.');
        return;
      case PosQrStatus.cancelled:
        _terminal(QrPhase.cancelled, QrResultKind.cancelled, 'The payment was cancelled.');
        return;
      case PosQrStatus.created:
      case PosQrStatus.presented:
      case PosQrStatus.pending:
        phase.value = QrPhase.waiting; // the server answered: no longer "checking"
        message.value = '';
        _startTimers();
    }
  }

  void _terminal(QrPhase p, QrResultKind kind, String msg) {
    phase.value = p;
    message.value = msg;
    _stopTimers();
    unawaited(_keepAwake(false).catchError((_) {}));
    unawaited(_store.clear());
    // a terminal-unpaid QR does not complete `result`: the cashier may generate a new one on the same screen
    _lastTerminal = QrResult(kind, intent: intent.value, message: msg);
  }

  QrResult? _lastTerminal;

  void _recount() {
    final i = intent.value;
    if (i == null) return;
    final serverNow = _now().add(_serverOffset);
    secondsLeft.value = max(0, i.expiresAt.difference(serverNow).inSeconds);
    if (secondsLeft.value > totalSeconds.value) totalSeconds.value = secondsLeft.value;
  }

  void _startTimers() {
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => poll());
    _tickTimer ??= Timer.periodic(_tick, (_) {
      _recount();
      if (secondsLeft.value == 0 && phase.value == QrPhase.waiting) poll(); // the server's word on expiry, now
    });
  }

  void _stopTimers() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  /// One look at the server. Public so tests and the "resume" path can drive it.
  Future<void> poll() async {
    final i = intent.value;
    if (_polling || i == null || phase.value == QrPhase.confirmed) return;
    _polling = true;
    try {
      final r = await _repo.getIntent(i.id);
      if (r.intent != null) {
        _adopt(r.intent!);
      } else if (r.connectivityError && phase.value == QrPhase.waiting) {
        phase.value = QrPhase.checking; // keep polling; never claim failure because the network blinked
      }
    } finally {
      _polling = false;
    }
  }

  /// Cancel at the till. If the customer paid in that same moment the server says so and the payment is simply confirmed.
  Future<void> cancel() async {
    final i = intent.value;
    if (busy.value) return;
    busy.value = true;
    try {
      if (i == null || !(phase.value == QrPhase.waiting || phase.value == QrPhase.checking)) {
        await _finish(QrResult(QrResultKind.cancelled, message: 'Cancelled'));
        return;
      }
      final r = await _repo.cancel(i.id);
      if (r.code == 'PAYMENT_ALREADY_CONFIRMED') {
        await poll();
        return;
      }
      if (r.intent != null) {
        _adopt(r.intent!);
        await _finish(_lastTerminal ?? const QrResult(QrResultKind.cancelled));
        return;
      }
      // not reached the server: the QR could still be paid — say so and keep waiting rather than pretend it is cancelled
      message.value = 'Could not cancel — check the connection. The QR is still active.';
      phase.value = QrPhase.checking;
    } finally {
      busy.value = false;
    }
  }

  /// A new QR for the same checkout after expiry / cancel / failure. The old payment is already over; a new one starts.
  Future<void> regenerate() async {
    if (busy.value || _starting) return;
    busy.value = true;
    try {
      await _store.clear();
      intent.value = null;
      totalSeconds.value = 0;
      _lastTerminal = null;
      await start();
    } finally {
      busy.value = false;
    }
  }

  /// The cashier leaves this screen without a payment ("Choose another method").
  Future<void> giveUp() async {
    await _finish(_lastTerminal ?? const QrResult(QrResultKind.cancelled));
  }

  Future<void> _finish(QrResult r) async {
    _stopTimers();
    unawaited(_keepAwake(false).catchError((_) {})); // never block the payment flow on the screen-awake plugin
    if (r.kind != QrResultKind.confirmed) await _store.clear();
    _complete(r);
  }

  /// The screen was torn down without a choice (idle lock, sign-out, route replaced): stop polling and releasing the screen-awake lock,
  /// but KEEP the pending payment (on the device and on the server) so it resumes when the till is unlocked. Nothing is cancelled.
  void detach() {
    if (_done.isCompleted) return;
    _stopTimers();
    unawaited(_keepAwake(false).catchError((_) {}));
    _done.complete(const QrResult(QrResultKind.detached));
  }

  /// "Simulate customer paid" for demos on the mock provider (debug builds only; the server refuses it elsewhere).
  Future<void> simulatePaid() async {
    final i = intent.value;
    if (i == null) return;
    await _repo.mockSimulate(i.id, 'confirm');
    await poll();
  }

  @override
  void onClose() {
    _stopTimers();
    unawaited(_keepAwake(false).catchError((_) {}));
    if (!_done.isCompleted) _done.complete(const QrResult(QrResultKind.cancelled));
    super.onClose();
  }

  @visibleForTesting
  bool get debugTimersRunning => _pollTimer != null;
}
