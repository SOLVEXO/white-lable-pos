import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_payment_intent_model.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// What every payments call answers: the intent (when there is one), or WHY not. [connectivityError] = the server was not
/// reached at all (the caller keeps polling / shows "Checking payment…"); a [code] = a definite answer from the server.
typedef PaymentCall = ({PosPaymentIntent? intent, String? code, String? message, bool connectivityError});

/// Digital (Raast QR) payments. The server owns every rule — status, expiry, amount match, late payments; this class only
/// carries requests. QR payments need the network by design: nothing here is queued or retried in the background.
class PosPaymentsRepository {
  PosPaymentsRepository({BaseClient? client}) : _client = client ?? BaseClient();
  final BaseClient _client;

  Future<Map<String, dynamic>> _employeeHeaders() async {
    final token = await AppPreferences.getPosEmployeeToken();
    return token != null ? {'x-pos-employee-token': token} : {};
  }

  PaymentCall _fail(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      final hasResponse = e.response != null;
      return (
        intent: null,
        code: data is Map ? data['code'] as String? : null,
        message: data is Map ? (data['message'] is String ? data['message'] as String : null) : null,
        connectivityError: !hasResponse || (e.response!.statusCode ?? 0) >= 500,
      );
    }
    debugPrint('payments: $e');
    return (intent: null, code: null, message: null, connectivityError: true);
  }

  PaymentCall _ok(Response res) {
    final raw = res.data;
    final data = raw is Map ? raw['data'] : null;
    if (data is Map<String, dynamic>) return (intent: PosPaymentIntent.fromJson(data), code: null, message: null, connectivityError: false);
    return (intent: null, code: null, message: null, connectivityError: false);
  }

  /// Starts a QR payment. [idempotencyKey] is stable per attempt: a retry (or a double tap) returns the SAME payment.
  Future<PaymentCall> createIntent({
    required int amountMinor,
    required String sessionId,
    required String idempotencyKey,
    String? saleAttemptKey,
    String? storeId,
    String? mockScenario,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posPaymentIntents,
        data: {
          'amountMinor': amountMinor,
          'sessionId': sessionId,
          'idempotencyKey': idempotencyKey,
          if (saleAttemptKey != null) 'saleAttemptKey': saleAttemptKey,
          if (storeId != null) 'storeId': storeId,
          if (mockScenario != null) 'mockScenario': mockScenario,
        },
        requiresAuth: true,
        headers: {...await _employeeHeaders(), 'Idempotency-Key': idempotencyKey},
      );
      return _ok(res);
    } catch (e) {
      return _fail(e);
    }
  }

  Future<PaymentCall> getIntent(String id) async {
    try {
      return _ok(await _client.get(ApiConstants.posPaymentIntent(id), requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }

  Future<PaymentCall> markPresented(String id) async {
    try {
      return _ok(await _client.post(ApiConstants.posPaymentPresented(id), data: {}, requiresAuth: true));
    } catch (e) {
      return _fail(e);
    }
  }

  /// `409 PAYMENT_ALREADY_CONFIRMED` comes back as [code]: the customer paid in the same moment — treat it as paid.
  Future<PaymentCall> cancel(String id) async {
    try {
      return _ok(await _client.post(ApiConstants.posPaymentCancel(id), data: {}, requiresAuth: true, headers: await _employeeHeaders()));
    } catch (e) {
      return _fail(e);
    }
  }

  /// Releases every unconfirmed QR line of a checkout the cashier gave up on (confirmed ones are left for a manager).
  Future<({bool ok, List<String> cancelled, List<String> confirmed})> cancelAttempt(String saleAttemptKey) async {
    try {
      final res = await _client.post(ApiConstants.posPaymentAttemptCancel(saleAttemptKey), data: {}, requiresAuth: true, headers: await _employeeHeaders());
      final d = (res.data is Map ? res.data['data'] : null) as Map?;
      List<String> ids(dynamic v) => [for (final x in (v as List<dynamic>? ?? const [])) '$x'];
      return (ok: true, cancelled: ids(d?['cancelled']), confirmed: ids(d?['confirmed']));
    } catch (e) {
      debugPrint('cancelAttempt: $e');
      return (ok: false, cancelled: const <String>[], confirmed: const <String>[]);
    }
  }

  Future<({List<PosAttentionItem> items, bool ok})> attention({String? storeId}) async {
    try {
      final res = await _client.get(ApiConstants.posPaymentAttention, requiresAuth: true, queryParameters: {if (storeId != null) 'storeId': storeId}, headers: await _employeeHeaders());
      final d = (res.data is Map ? res.data['data'] : null) as Map?;
      return (items: [for (final i in (d?['items'] as List<dynamic>? ?? const [])) PosAttentionItem.fromJson(i as Map<String, dynamic>)], ok: true);
    } catch (e) {
      debugPrint('attention: $e');
      return (items: const <PosAttentionItem>[], ok: false);
    }
  }

  /// Manager actions (the manager's PIN session is the authority; the server checks the role).
  /// [resolution]: `sale_recorded` (needs [saleId] or the [saleNumber] printed on the receipt) · `refund` · `resolved` (needs a [note] of at least 10 characters).
  Future<PaymentCall> reconcile(String intentId, {required String resolution, String? saleId, String? saleNumber, String? note, String? idempotencyKey}) async {
    try {
      final res = await _client.post(
        ApiConstants.posPaymentReconcile(intentId),
        data: {'resolution': resolution, if (saleId != null) 'saleId': saleId, if (saleNumber != null) 'saleNumber': saleNumber, if (note != null) 'note': note},
        requiresAuth: true,
        headers: {...await _employeeHeaders(), if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey},
      );
      return _ok(res);
    } catch (e) {
      return _fail(e);
    }
  }

  /// Dev / mock provider only ("customer paid" for demos and integration tests). The server refuses it elsewhere.
  Future<bool> mockSimulate(String intentId, String scenario) async {
    try {
      await _client.post(ApiConstants.posPaymentMockSimulate, data: {'intentId': intentId, 'scenario': scenario}, requiresAuth: true);
      return true;
    } catch (e) {
      debugPrint('mockSimulate: $e');
      return false;
    }
  }

  /// The store's business-verification status (manager / owner PIN session only; the server refuses a cashier). Read-only.
  Future<PosKybStatus?> verification({String? storeId}) async {
    try {
      final res = await _client.get(ApiConstants.posPaymentVerification, requiresAuth: true, queryParameters: {if (storeId != null) 'storeId': storeId}, headers: await _employeeHeaders());
      final d = res.data is Map ? res.data['data'] : null;
      return d is Map<String, dynamic> ? PosKybStatus.fromJson(d) : null;
    } catch (e) {
      debugPrint('verification: $e');
      return null;
    }
  }
}
