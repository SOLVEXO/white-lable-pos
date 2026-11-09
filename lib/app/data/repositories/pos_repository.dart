import 'dart:async';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'dart:io';

import 'package:solvexo_pos/app/data/local/idempotency_intent_store.dart';
import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:solvexo_pos/app/data/repositories/sale_payload_minor.dart';
import 'package:solvexo_pos/utils/money_json.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

typedef PagedResult<T> = ({List<T> items, int total, int totalPages, bool hasMore});

class PosRepository {
  PosRepository({BaseClient? client, IdempotencyIntentStore? intents})
      : _client = client ?? BaseClient(),
        _intents = intents ?? IdempotencyIntentStore.instance;

  final BaseClient _client;
  final IdempotencyIntentStore _intents;

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Every POS response is `{success, message?, data?, count?}`. Returns the
  /// unwrapped `data` payload only when `success == true`; otherwise null.
  dynamic _data(Response response) {
    final raw = response.data;
    if (raw is Map<String, dynamic> && raw['success'] == true) {
      return raw['data'];
    }
    return null;
  }

  bool _ok(Response response) =>
      response.data is Map<String, dynamic> && response.data['success'] == true;

  PagedResult<T> _emptyPage<T>() => (items: <T>[], total: 0, totalPages: 0, hasMore: false);

  PagedResult<T> _page<T>(
    Map<String, dynamic> data,
    String listKey,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final pagination = data['pagination'] as Map<String, dynamic>? ?? {};
    final page = pagination['page'] as int? ?? 1;
    final totalPages = pagination['totalPages'] as int? ?? 1;
    final items = (data[listKey] as List<dynamic>?)
            ?.map((e) => fromJson(e as Map<String, dynamic>))
            .toList() ??
        <T>[];
    return (
      items: items,
      total: pagination['total'] as int? ?? items.length,
      totalPages: totalPages,
      hasMore: page < totalPages,
    );
  }

  void _logDioError(String tag, DioException e) {
    debugPrint('❌ $tag DioException: ${e.response?.statusCode}');
    debugPrint('   Response: ${e.response?.data}');
  }

  /// G2.5: why the last [refundSale] needed a manager (`amount_above_limit`, `too_many_days_since_sale`, `no_original_receipt`, `store_requires_manager`)
  /// and the credit note it produced ({id, number, totalMinor}).
  List<String> lastErrorReasons = const [];
  Map<String, dynamic>? lastCreditNote;

  /// The server's machine-readable `code` of the last failed [createSale] (e.g. CUSTOM_ITEM_NEEDS_MANAGER, COUPON_EXPIRED), else null.
  /// Kept beside the result so the long-standing return shape of createSale stays as it was.
  String? lastErrorCode;

  /// Extracts the backend's `message` field from a failed response, if any.
  String? _dioMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['message'] as String?;
    return null;
  }

  /// Header carrying the current employee's signed PIN-login token — sent
  /// on every privileged action (refund, void, cash in/out, discounts) so
  /// the backend can verify who's actually authorizing it. See
  /// AppPreferences.setPosEmployeeToken's doc comment.
  Future<Map<String, dynamic>> _employeeAuthHeaders() async {
    final token = await AppPreferences.getPosEmployeeToken();
    return token != null ? {'x-pos-employee-token': token} : {};
  }

  /// Headers for a mutating POS call: the employee token plus the
  /// `Idempotency-Key` for this user intent (see [IdempotencyIntentStore]).
  Future<Map<String, dynamic>> _writeHeaders(String idempotencyKey) async => {
        ...await _employeeAuthHeaders(),
        'Idempotency-Key': idempotencyKey,
      };

  /// True when a failed request is a *definite* answer — the server looked at
  /// it and said no (validation, forbidden, not found, plan inactive, and every
  /// BUSINESS-conflict 409 such as "held sale already completed") — so the
  /// intent is over: its key is dropped, it is never retried and never queued.
  ///
  /// Only these are ambiguous (the server may or may not have acted, so the
  /// SAME key is reused on a retry): no response, timeouts, 5xx, 408/429, and
  /// the one retryable 409 — `IDEMPOTENCY_IN_PROGRESS` ("this key is still
  /// running"). See [isRetryableStatus].
  bool _isFinalFailure(DioException e) => !isRetryableStatus(e.response?.statusCode, _dioCode(e));

  /// The backend's machine-readable `code` (e.g. `POS_PLAN_REQUIRED`), if any.
  String? _dioCode(DioException e) {
    final data = e.response?.data;
    if (data is Map) return data['code'] as String?;
    return null;
  }

  /// Tells the app (restricted mode) that the server just refused because the plan isn't active.
  void _noteEntitlement(DioException e) {
    if (_dioCode(e) == 'POS_PLAN_REQUIRED') PosEntitlementService.maybe?.markRestricted();
  }

  // ── PIN login ────────────────────────────────────────────────────────────

  /// [message] carries the backend's error text on failure so the caller can
  /// show a tailored message (e.g. "Invalid PIN") without an auto-toast.
  Future<({bool success, PosEmployeeModel? employee, PosSessionModel? activeSession, String? employeeToken, String? message})> pinLogin({
    required String storeId,
    required String email,
    required String pin,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posPinLogin,
        data: {'storeId': storeId, 'email': email, 'pin': pin},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) {
        return (success: false, employee: null, activeSession: null, employeeToken: null, message: res.data['message'] as String?);
      }
      final employee = PosEmployeeModel.fromJson(data['employee'] as Map<String, dynamic>);
      final sessionJson = data['activeSession'];
      final activeSession = sessionJson is Map<String, dynamic>
          ? PosSessionModel.fromJson(sessionJson)
          : null;
      // Signed proof of this employee's identity/role — see AppPreferences
      // .setPosEmployeeToken's doc comment. Sent as a header on every
      // privileged action (refund/void/cash-adjustment/discount) so the
      // backend can verify who's actually authorizing it, instead of
      // trusting a client-supplied id string.
      final employeeToken = data['employeeToken'] as String?;
      return (success: true, employee: employee, activeSession: activeSession, employeeToken: employeeToken, message: null);
    } on DioException catch (e) {
      _logDioError('pinLogin', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, employee: null, activeSession: null, employeeToken: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ pinLogin: $e');
      return (success: false, employee: null, activeSession: null, employeeToken: null, message: null);
    }
  }

  /// Best-effort — logs the event server-side, doesn't need to succeed for
  /// the local logout (clearPosEmployee) to proceed. Called fire-and-forget
  /// from wherever a PIN session ends (see PosSettingsController._closeShift).
  Future<void> pinLogout(String storeId) async {
    try {
      await _client.post(
        ApiConstants.posPinLogout,
        data: {'storeId': storeId},
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
    } catch (e) {
      debugPrint('❌ pinLogout: $e');
    }
  }

  /// Ends a SPECIFIC employee token server-side (e.g. the one that was live before the till auto-locked), independent of
  /// whichever token is currently stored.
  Future<void> pinLogoutWith(String storeId, String employeeToken) async {
    try {
      await _client.post(
        ApiConstants.posPinLogout,
        data: {'storeId': storeId},
        requiresAuth: true,
        headers: {'x-pos-employee-token': employeeToken},
      );
    } catch (e) {
      debugPrint('❌ pinLogoutWith: $e');
    }
  }

  // ── Employees ────────────────────────────────────────────────────────────

  Future<List<PosEmployeeModel>> getEmployees(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posEmployees(storeId), requiresAuth: true);
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => PosEmployeeModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('getEmployees', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getEmployees: $e');
      ToastUtil.showToast('Failed to load employees.');
      return [];
    }
  }

  Future<PosEmployeeModel?> createEmployee({
    required String storeId,
    required String name,
    required String email,
    required String role,
    required String pin,
    List<String> shiftIds = const [],
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posEmployeesCreate,
        data: {
          'storeId': storeId,
          'name': name,
          'email': email,
          'role': role,
          'pin': pin,
          'shiftIds': shiftIds,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return PosEmployeeModel.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to add employee');
      return null;
    } on DioException catch (e) {
      _logDioError('createEmployee', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ createEmployee: $e');
      ToastUtil.showToast('Failed to add employee.');
      return null;
    }
  }

  Future<PosEmployeeModel?> getEmployeeById(String storeId, String employeeId) async {
    try {
      final res = await _client.get(ApiConstants.posEmployeeV2(storeId, employeeId), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosEmployeeModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getEmployeeById', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getEmployeeById: $e');
      return null;
    }
  }

  /// Updates an employee's name / pin / role / shifts / status.
  Future<PosEmployeeModel?> updateEmployee({
    required String storeId,
    required String employeeId,
    String? name,
    String? pin,
    String? role,
    List<String>? shiftIds,
    String? status,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.posEmployeeV2(storeId, employeeId),
        data: {
          if (name != null) 'name': name,
          if (pin != null) 'pin': pin,
          if (role != null) 'role': role,
          if (shiftIds != null) 'shiftIds': shiftIds,
          if (status != null) 'status': status,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return PosEmployeeModel.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to update employee');
      return null;
    } on DioException catch (e) {
      _logDioError('updateEmployee', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ updateEmployee: $e');
      ToastUtil.showToast('Failed to update employee.');
      return null;
    }
  }

  Future<bool> resetEmployeePin({
    required String storeId,
    required String employeeId,
    required String newPin,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posEmployeeResetPin(storeId, employeeId),
        data: {'newPin': newPin},
        requiresAuth: true,
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to reset PIN');
      return false;
    } on DioException catch (e) {
      _logDioError('resetEmployeePin', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ resetEmployeePin: $e');
      ToastUtil.showToast('Failed to reset PIN.');
      return false;
    }
  }

  /// Deactivates (soft-deletes) an employee. Uses the storeId-scoped route,
  /// which also writes an audit log entry.
  Future<bool> deleteEmployee(String storeId, String employeeId) async {
    try {
      final res = await _client.delete(ApiConstants.posEmployeeV2(storeId, employeeId), requiresAuth: true);
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to remove employee');
      return false;
    } on DioException catch (e) {
      _logDioError('deleteEmployee', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ deleteEmployee: $e');
      ToastUtil.showToast('Failed to remove employee.');
      return false;
    }
  }

  // ── Registers ────────────────────────────────────────────────────────────

  Future<bool> createRegister({
    required String storeId,
    required String name,
    double? defaultFloatCash,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posRegisters(storeId),
        data: {'name': name, if (defaultFloatCash != null) 'defaultFloatCash': defaultFloatCash},
        requiresAuth: true,
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to add register');
      return false;
    } on DioException catch (e) {
      _logDioError('createRegister', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ createRegister: $e');
      ToastUtil.showToast('Failed to add register.');
      return false;
    }
  }

  Future<List<StoreRegister>> listRegisters(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posRegisters(storeId), requiresAuth: true);
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => StoreRegister.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('listRegisters', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ listRegisters: $e');
      return [];
    }
  }

  Future<StoreRegister?> updateRegister({
    required String storeId,
    required String registerId,
    String? name,
    double? defaultFloatCash,
    String? status,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.posRegisterById(storeId, registerId),
        data: {
          if (name != null) 'name': name,
          if (defaultFloatCash != null) 'defaultFloatCash': defaultFloatCash,
          if (status != null) 'status': status,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return StoreRegister.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to update register');
      return null;
    } on DioException catch (e) {
      _logDioError('updateRegister', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ updateRegister: $e');
      ToastUtil.showToast('Failed to update register.');
      return null;
    }
  }

  /// Fails with a friendly message if the register has an open session.
  Future<bool> deleteRegister(String storeId, String registerId) async {
    try {
      final res = await _client.delete(ApiConstants.posRegisterById(storeId, registerId), requiresAuth: true);
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to remove register');
      return false;
    } on DioException catch (e) {
      _logDioError('deleteRegister', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ deleteRegister: $e');
      ToastUtil.showToast('Failed to remove register.');
      return false;
    }
  }

  // ── Shifts ───────────────────────────────────────────────────────────────

  Future<bool> createShift({
    required String storeId,
    required String name,
    required String startTime,
    required String endTime,
    List<int>? daysOfWeek,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posShifts(storeId),
        data: {
          'name': name,
          'startTime': startTime,
          'endTime': endTime,
          if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
        },
        requiresAuth: true,
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to add shift');
      return false;
    } on DioException catch (e) {
      _logDioError('createShift', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ createShift: $e');
      ToastUtil.showToast('Failed to add shift.');
      return false;
    }
  }

  Future<List<StoreShift>> listShifts(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posShifts(storeId), requiresAuth: true);
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => StoreShift.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('listShifts', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ listShifts: $e');
      return [];
    }
  }

  Future<StoreShift?> updateShift({
    required String storeId,
    required String shiftId,
    String? name,
    String? startTime,
    String? endTime,
    List<int>? daysOfWeek,
    String? status,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.posShiftById(storeId, shiftId),
        data: {
          if (name != null) 'name': name,
          if (startTime != null) 'startTime': startTime,
          if (endTime != null) 'endTime': endTime,
          if (daysOfWeek != null) 'daysOfWeek': daysOfWeek,
          if (status != null) 'status': status,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return StoreShift.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to update shift');
      return null;
    } on DioException catch (e) {
      _logDioError('updateShift', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ updateShift: $e');
      ToastUtil.showToast('Failed to update shift.');
      return null;
    }
  }

  /// [force]: if employees are still assigned to this shift, pass true to
  /// unassign them and delete anyway (mirrors the backend's ?force=true).
  Future<bool> deleteShift(String storeId, String shiftId, {bool force = false}) async {
    try {
      final res = await _client.delete(
        ApiConstants.posShiftById(storeId, shiftId),
        queryParameters: force ? {'force': 'true'} : null,
        requiresAuth: true,
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to remove shift');
      return false;
    } on DioException catch (e) {
      _logDioError('deleteShift', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ deleteShift: $e');
      ToastUtil.showToast('Failed to remove shift.');
      return false;
    }
  }

  // ── Sessions ─────────────────────────────────────────────────────────────

  Future<({bool success, PosSessionModel? session, String? message})> openSession({
    required String storeId,
    required String registerId,
    required String employeeId,
    String? shiftId,
    required double openingCash,
  }) async {
    final payload = {
      'storeId': storeId,
      'registerId': registerId,
      'employeeId': employeeId,
      if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
      'openingCash': openingCash,
    };
    final fp = IdempotencyIntentStore.fingerprint('openSession', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSessionsOpen,
        data: payload,
        requiresAuth: true,
        headers: await _writeHeaders(await _intents.keyFor(fp)),
      );
      settled = true;
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, session: PosSessionModel.fromJson(data), message: null);
      return (success: false, session: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('openSession', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, session: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ openSession: $e');
      return (success: false, session: null, message: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  Future<({bool success, PosSessionModel? session, String? message})> closeSession({
    required String sessionId,
    required double closingCash,
    double? cardTotalFromSlip, // G2.4: the total printed on the card terminal's settlement slip (a difference needs a manager)
    String? approverToken, // a manager's token approving a card variance (replaces the cashier's for this call)
  }) async {
    lastErrorCode = null;
    final payload = {'sessionId': sessionId, 'closingCash': closingCash, if (cardTotalFromSlip != null) 'cardTotalFromSlip': cardTotalFromSlip};
    final fp = IdempotencyIntentStore.fingerprint('closeSession', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSessionsClose,
        data: payload,
        requiresAuth: true,
        headers: {...await _writeHeaders(await _intents.keyFor(fp)), if (approverToken != null) 'x-pos-employee-token': approverToken},
      );
      settled = true;
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, session: PosSessionModel.fromJson(data), message: null);
      return (success: false, session: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      lastErrorCode = _dioCode(e);
      _logDioError('closeSession', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, session: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ closeSession: $e');
      return (success: false, session: null, message: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  Future<PosSessionModel?> forceCloseSession(String sessionId, {String? reason}) async {
    try {
      final res = await _client.post(
        ApiConstants.posSessionForceClose(sessionId),
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return PosSessionModel.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to force-close session');
      return null;
    } on DioException catch (e) {
      _logDioError('forceCloseSession', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ forceCloseSession: $e');
      ToastUtil.showToast('Failed to force-close session.');
      return null;
    }
  }

  Future<PosSessionModel?> getActiveSession({
    required String storeId,
    required String registerId,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posSessionsActive,
        queryParameters: {'storeId': storeId, 'registerId': registerId},
        requiresAuth: true,
      );
      final data = _data(res);
      return data is Map<String, dynamic> ? PosSessionModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getActiveSession', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getActiveSession: $e');
      return null;
    }
  }

  Future<PagedResult<PosSessionModel>> getSessionHistory({
    required String storeId,
    int page = 1,
    String? registerId,
    String? employeeId,
    String? status,
    String? from,
    String? to,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posSessionsHistory,
        queryParameters: {
          'storeId': storeId,
          'page': page,
          if (registerId != null && registerId.isNotEmpty) 'registerId': registerId,
          if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
          if (status != null && status.isNotEmpty) 'status': status,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return _emptyPage();
      return _page(data, 'sessions', PosSessionModel.fromJson);
    } on DioException catch (e) {
      _logDioError('getSessionHistory', e);
      DioExceptionHandler.handleDioException(e);
      return _emptyPage();
    } catch (e) {
      debugPrint('❌ getSessionHistory: $e');
      return _emptyPage();
    }
  }

  Future<Map<String, dynamic>?> cashAdjustment({
    required String sessionId,
    required String type, // "cash_in" | "cash_out"
    required double amount,
    required String reason,
    required String employeeId,
  }) async {
    final payload = {'type': type, 'amount': amount, 'reason': reason, 'employeeId': employeeId};
    final fp = IdempotencyIntentStore.fingerprint('cashAdjustment:$sessionId', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSessionCashAdjustment(sessionId),
        data: payload,
        requiresAuth: true,
        headers: await _writeHeaders(await _intents.keyFor(fp)),
      );
      settled = true;
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return data;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to record cash movement');
      return null;
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('cashAdjustment', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ cashAdjustment: $e');
      ToastUtil.showToast('Failed to record cash movement.');
      return null;
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  Future<PosSessionReportModel?> getSessionReport(String sessionId) async {
    try {
      final res = await _client.get(ApiConstants.posSessionReport(sessionId), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosSessionReportModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getSessionReport', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getSessionReport: $e');
      return null;
    }
  }

  // ── Products ─────────────────────────────────────────────────────────────

  Future<PagedResult<PosProductModel>> getProducts(
    String storeId, {
    int page = 1,
    int limit = 30,
    String? categoryId,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posProducts(storeId),
        queryParameters: {
          'page': page,
          'limit': limit,
          if (categoryId != null && categoryId.isNotEmpty) 'categoryId': categoryId,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return _emptyPage();
      return _page(data, 'products', PosProductModel.fromJson);
    } on DioException catch (e) {
      _logDioError('getProducts', e);
      DioExceptionHandler.handleDioException(e);
      return _emptyPage();
    } catch (e) {
      debugPrint('❌ getProducts: $e');
      ToastUtil.showToast('Failed to load products.');
      return _emptyPage();
    }
  }

  Future<List<PosProductModel>> searchProducts({
    required String storeId,
    required String q,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posProductsSearch,
        queryParameters: {'storeId': storeId, 'q': q},
        requiresAuth: true,
      );
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => PosProductModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('searchProducts', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ searchProducts: $e');
      return [];
    }
  }

  Future<PosProductModel?> getProductByBarcode({
    required String storeId,
    required String barcode,
  }) async {
    try {
      final res = await _client.get(ApiConstants.posProductBarcode(storeId, barcode), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosProductModel.fromBarcodeJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getProductByBarcode', e);
      if (e.response?.statusCode != 404) DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getProductByBarcode: $e');
      return null;
    }
  }

  // ── Sales ────────────────────────────────────────────────────────────────

  /// True for Dio failures that mean "couldn't reach the server at all"
  /// (no signal, DNS failure, connection refused) as opposed to a real
  /// response the server sent back (4xx/5xx) — only the former is safe to
  /// silently queue and retry later, since the latter (e.g. a validation
  /// error) would just fail again identically on retry.
  bool _isConnectivityError(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return true;
    }
    return e.type == DioExceptionType.unknown && e.error is SocketException;
  }

  Future<({bool success, PosSaleModel? sale, String? message, bool queued})> createSale({
    required String storeId,
    required String sessionId,
    required String registerId,
    required String employeeId,
    required List<Map<String, dynamic>> items,
    String? discountType, // "amount" | "percent" — the server computes the discount from it
    double? discountValue,
    double? clientTotal, // what this device displayed; the server rejects a mismatch (TOTAL_MISMATCH)
    int? settingsVersion, // the POS settings version (tax rate…) the device priced this with — see quoteSale
    DateTime? clientCreatedAt, // when the sale was really made; sent so a queued sale keeps its true time
    required String paymentMethod,
    List<Map<String, dynamic>>? payments, // split tender: [{method, amount, reference?}]
    double? amountTendered, // single cash payment: what the customer handed over
    String? paymentReference,
    String customerName = 'Walk-in',
    String? customerId,
    String? notes,
    required String status, // "completed" | "held"
    String? idempotencyKey,
    String? couponCode, // G2.4: a POS coupon code — the server validates it and counts its use inside the sale (online only, never queued)
    String? approverToken, // G2.4: a manager's PIN-login token approving custom items on this sale (replaces the cashier's token for this call)
  }) async {
    lastErrorCode = null;
    final payload = <String, dynamic>{
      'storeId': storeId,
      'sessionId': sessionId,
      'registerId': registerId,
      'employeeId': employeeId,
      'items': items,
      if (discountType != null && (discountValue ?? 0) > 0) ...{'discountType': discountType, 'discountValue': discountValue},
      if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
      if (clientTotal != null) 'clientTotal': clientTotal,
      if (settingsVersion != null) 'settingsVersion': settingsVersion,
      // the moment the cashier rang it up (stable across retries — it is part of the queued payload)
      'clientCreatedAt': (clientCreatedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'paymentMethod': paymentMethod,
      if (payments != null && payments.isNotEmpty) 'payments': payments,
      if (amountTendered != null) 'amountTendered': amountTendered,
      if (paymentReference != null && paymentReference.isNotEmpty) 'paymentReference': paymentReference,
      'customerName': customerName,
      if (customerId != null) 'customerId': customerId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'status': status,
    };
    // The key belongs to this checkout *intent*: the same cart retried after a
    // timeout (or after an app restart) reuses it; the caller no longer mints
    // one per tap. See IdempotencyIntentStore.
    // `clientCreatedAt` is excluded: it is the retry-stable moment of the sale, not part of WHAT is being sold
    final fp = IdempotencyIntentStore.fingerprint('createSale', {...payload}..remove('clientCreatedAt'));
    final key = idempotencyKey ?? await _intents.keyFor(fp);
    payload['idempotencyKey'] = key;
    // G1b: the integer minor-unit twins ride next to the decimals (added AFTER the fingerprint, so a checkout intent started by an
    // older build keeps its key). The queued copy below is built from this payload, so a later replay carries them too.
    final minorPayload = withMinorTwins(payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSales,
        data: minorPayload,
        requiresAuth: true,
        headers: {...await _writeHeaders(key), if (approverToken != null) 'x-pos-employee-token': approverToken},
      );
      settled = true;
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) {
        return (success: true, sale: PosSaleModel.fromJson(data), message: null, queued: false);
      }
      return (success: false, sale: null, message: res.data['message'] as String?, queued: false);
    } on DioException catch (e) {
      _logDioError('createSale', e);
      _noteEntitlement(e);
      // A sale with a Raast QR payment is NEVER queued for later: digital payments need the network by design (the server checks the
      // payment is confirmed when the sale arrives). Not final = the cashier simply presses Charge again — the same key and the same
      // confirmed payment are reused, so nothing is charged twice and nothing is lost.
      final hasDigital = (payload['payments'] as List<dynamic>? ?? const []).any((p) => p is Map && p['method'] == 'raast_qr');
      // G2.4: a coupon needs a live check — never queued either (the server refuses it on an offline sale)
      final hasCoupon = payload.containsKey('couponCode') && status != 'held'; // a HELD sale only remembers the code — that may be queued
      if (!_isFinalFailure(e) && !hasDigital && !hasCoupon && Get.isRegistered<PendingSaleSyncService>()) {
        // The outcome is unknown (no route to the server, a timeout after the
        // request was sent, a 5xx, or "already in progress"): the sale may
        // already exist server-side. Persist it locally under the SAME key
        // and let the sync replay it — the backend returns the original sale
        // if it was recorded and creates it exactly once if it wasn't, so
        // the cashier is never asked to ring it up a second time.
        final sync = Get.find<PendingSaleSyncService>();
        // `offline: true` tells the server this is a replay: it keeps `clientCreatedAt` as the sale's time, checks the
        // plan at THAT time, applies the offline stock rule and validates the offline window. The employee's token is
        // kept only when a discount needs a manager's authority — the server checks it was valid when the sale was made.
        final queued = {...minorPayload, 'offline': true};
        // G2.4: a custom item above the store's limit is approved by a manager — keep the approver's token for the replay too
        final hasCustom = items.any((i) => i['isCustom'] == true);
        final needsToken = (payload['discountValue'] as num? ?? 0) > 0 || hasCustom;
        await sync.enqueue(key, queued, employeeToken: needsToken ? (approverToken ?? await AppPreferences.getPosEmployeeToken()) : null);
        await _intents.release(fp); // the queue owns the key now
        sync.scheduleSync();
        return (success: false, sale: null, message: null, queued: true);
      }
      settled = _isFinalFailure(e);
      lastErrorCode = _dioCode(e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, sale: null, message: _dioMessage(e), queued: false);
    } catch (e) {
      debugPrint('❌ createSale: $e');
      return (success: false, sale: null, message: null, queued: false);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  /// Resubmits a previously-queued sale payload as-is. Used only by
  /// [PendingSaleSyncService] once connectivity returns — see
  /// [PendingSaleLocalStore] for what's stored.
  Future<({bool success, bool connectivityError, bool retryable, String? message, String? code})> submitRawSale(
    Map<String, dynamic> payload, {
    String? employeeToken,
  }) async {
    try {
      final key = payload['idempotencyKey'] as String?;
      // Replay with the token saved when the sale was made (if any) — the current cashier's token may be a different
      // person, or expired; the server judges the saved one as of the sale's own time.
      final headers = {
        ...await _employeeAuthHeaders(),
        if (employeeToken != null) 'x-pos-employee-token': employeeToken,
        if (key != null) 'Idempotency-Key': key,
      };
      // G2.7: the provisional `OFF-…` number printed on the customer's first receipt goes to the server as a SEPARATE field (a lookup
      // reference so a return at another till can find the sale). The stored/queued payload and the idempotency fingerprint never contain it.
      String? provisional;
      try {
        if (key != null && Get.isRegistered<PendingSaleSyncService>()) provisional = await Get.find<PendingSaleSyncService>().provisionalNumberFor(key);
      } catch (_) {}
      final res = await _client.post(
        ApiConstants.posSales,
        data: provisional == null ? payload : {...payload, 'provisionalNumber': provisional},
        requiresAuth: true,
        headers: headers,
      );
      if (_ok(res)) {
        // Remember which real receipt number this offline sale got (best effort — never affects the sync result).
        try {
          final d = _data(res);
          if (key != null && d is Map && Get.isRegistered<PendingSaleSyncService>()) {
            await Get.find<PendingSaleSyncService>().noteSynced(key, realNumber: (d['saleNumber'] ?? '').toString(), saleId: (d['_id'] ?? d['id'])?.toString());
          }
        } catch (_) {}
        return (success: true, connectivityError: false, retryable: false, message: null, code: null);
      }
      return (success: false, connectivityError: false, retryable: false, message: res.data['message'] as String?, code: null);
    } on DioException catch (e) {
      _logDioError('submitRawSale', e);
      _noteEntitlement(e);
      final connectivityError = _isConnectivityError(e);
      // retryable = outcome still unknown (connectivity, timeouts, 5xx, 409 in-progress): keep the
      // queued sale and replay it with the same key. Only a definite rejection is a final failure.
      final retryable = !_isFinalFailure(e);
      if (!retryable) DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, connectivityError: connectivityError, retryable: retryable, message: _dioMessage(e), code: _dioCode(e));
    } catch (e) {
      debugPrint('❌ submitRawSale: $e');
      return (success: false, connectivityError: false, retryable: true, message: null, code: null);
    }
  }

  Future<List<PosSaleModel>> getHeldSales({
    required String storeId,
    String? sessionId,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posSalesHeld,
        queryParameters: {
          'storeId': storeId,
          if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
        },
        requiresAuth: true,
      );
      final list = _data(res) as List<dynamic>? ?? [];
      return list.map((e) => PosSaleModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('getHeldSales', e);
      DioExceptionHandler.handleDioException(e);
      return [];
    } catch (e) {
      debugPrint('❌ getHeldSales: $e');
      return [];
    }
  }

  Future<PagedResult<PosSaleModel>> getSales({
    required String storeId,
    String? sessionId,
    String? employeeId,
    String? paymentMethod,
    String? status,
    String? from,
    String? to,
    int page = 1,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posSales,
        queryParameters: {
          'storeId': storeId,
          'page': page,
          if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
          if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
          if (paymentMethod != null && paymentMethod.isNotEmpty) 'paymentMethod': paymentMethod,
          if (status != null && status.isNotEmpty) 'status': status,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return _emptyPage();
      return _page(data, 'sales', PosSaleModel.fromJson);
    } on DioException catch (e) {
      _logDioError('getSales', e);
      DioExceptionHandler.handleDioException(e);
      return _emptyPage();
    } catch (e) {
      debugPrint('❌ getSales: $e');
      ToastUtil.showToast('Failed to load transactions.');
      return _emptyPage();
    }
  }

  Future<PosSaleModel?> getSaleById(String saleId) async {
    try {
      final res = await _client.get(ApiConstants.posSaleById(saleId), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosSaleModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getSaleById', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getSaleById: $e');
      return null;
    }
  }

  Future<({bool success, PosSaleModel? sale, String? message})> completeSale({
    required String saleId,
    required String paymentMethod,
    List<Map<String, dynamic>>? payments,
    double? amountTendered,
    String? paymentReference,
    String? discountType,
    double? discountValue,
    double? clientTotal,
    String? notes,
  }) async {
    final payload = {
      'paymentMethod': paymentMethod,
      if (payments != null && payments.isNotEmpty) 'payments': payments,
      if (amountTendered != null) 'amountTendered': amountTendered,
      if (paymentReference != null && paymentReference.isNotEmpty) 'paymentReference': paymentReference,
      if (discountType != null) ...{'discountType': discountType, 'discountValue': discountValue ?? 0},
      if (clientTotal != null) 'clientTotal': clientTotal,
      if (notes != null) 'notes': notes,
    };
    final fp = IdempotencyIntentStore.fingerprint('completeSale:$saleId', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSaleComplete(saleId),
        data: payload,
        requiresAuth: true,
        headers: await _writeHeaders(await _intents.keyFor(fp)),
      );
      settled = true;
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, sale: PosSaleModel.fromJson(data), message: null);
      return (success: false, sale: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('completeSale', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, sale: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ completeSale: $e');
      return (success: false, sale: null, message: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  Future<PosSaleModel?> editHeldSaleItems({
    required String saleId,
    required List<Map<String, dynamic>> items,
    double? discount,
    double? tax,
  }) async {
    try {
      final res = await _client.patch(
        ApiConstants.posSaleItems(saleId),
        data: {
          'items': items,
          if (discount != null) 'discount': discount,
          if (tax != null) 'tax': tax,
        },
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return PosSaleModel.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to update held sale');
      return null;
    } on DioException catch (e) {
      _logDioError('editHeldSaleItems', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ editHeldSaleItems: $e');
      ToastUtil.showToast('Failed to update held sale.');
      return null;
    }
  }

  Future<bool> discardSale(String saleId, {String? reasonCode, String? reason}) async {
    try {
      // the reason travels in the query string (some HTTP clients drop a DELETE body); an old server simply ignores it
      final q = <String>[
        if (reasonCode != null && reasonCode.isNotEmpty) 'reasonCode=${Uri.encodeQueryComponent(reasonCode)}',
        if (reason != null && reason.trim().isNotEmpty) 'reason=${Uri.encodeQueryComponent(reason.trim())}',
      ];
      final url = ApiConstants.posSaleDiscard(saleId) + (q.isEmpty ? '' : '?${q.join('&')}');
      final res = await _client.delete(url, requiresAuth: true);
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to discard sale');
      return false;
    } on DioException catch (e) {
      _logDioError('discardSale', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ discardSale: $e');
      ToastUtil.showToast('Failed to discard sale.');
      return false;
    }
  }

  /// Omit [items] for a full refund; pass line items (`saleItemId` + `qty`)
  /// for a partial refund. Authorization comes from the current employee's
  /// signed token (see [_employeeAuthHeaders]) — the backend requires a
  /// verified manager-role token, not a client-supplied id.
  Future<({bool success, double? refundedAmount, String? newStatus, String? message, List<PosPaymentLine> tenders})> refundSale(
    String saleId, {
    List<Map<String, dynamic>>? items,
    String? reasonCode, // G2.4 picker code (wrong_item, damaged_or_defective, …) — recorded on the refund and its audit event
    String? reason, // optional free-text note
    bool? receiptPresented, // G2.5: false = the customer has no original receipt (a manager must approve)
    String? approverToken, // G2.5: a manager's PIN-login token approving this return (replaces the cashier's for this call)
  }) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    lastCreditNote = null;
    // G2.7: the register this till is paired with — so a return of a sale rung up on ANOTHER till is paid out of THIS till's open shift.
    String? returnRegister;
    try {
      returnRegister = await AppPreferences.getPosRegisterId();
    } catch (_) {}
    final payload = {
      if (items != null && items.isNotEmpty) 'items': items,
      if (returnRegister != null && returnRegister.isNotEmpty) 'registerId': returnRegister,
      if (receiptPresented == false) 'receiptPresented': false,
      if (reasonCode != null && reasonCode.isNotEmpty) 'reasonCode': reasonCode,
      if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
    };
    final fp = IdempotencyIntentStore.fingerprint('refundSale:$saleId', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSaleRefund(saleId),
        data: payload,
        requiresAuth: true,
        headers: {...await _writeHeaders(await _intents.keyFor(fp)), if (approverToken != null) 'x-pos-employee-token': approverToken},
      );
      settled = true;
      if (_ok(res)) {
        final data = res.data['data'] as Map<String, dynamic>?;
        if (data?['creditNote'] is Map) lastCreditNote = (data!['creditNote'] as Map).cast<String, dynamic>();
        return (
          success: true,
          refundedAmount: (data?['refundedAmount'] as num?)?.toDouble(),
          newStatus: data?['newStatus'] as String?,
          message: res.data['message'] as String?,
          // what the SERVER recorded per tender — the cashier is told to do exactly this
          tenders: (data?['tenders'] as List<dynamic>?)?.map((e) => PosPaymentLine.fromJson((e as Map).cast<String, dynamic>())).toList() ?? const <PosPaymentLine>[],
        );
      }
      return (success: false, refundedAmount: null, newStatus: null, message: res.data['message'] as String?, tenders: const <PosPaymentLine>[]);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('refundSale', e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      final body = e.response?.data;
      if (body is Map && body['reasons'] is List) lastErrorReasons = [for (final r in body['reasons'] as List) r.toString()];
      // the rules the cashier can act on (ask a manager, open a shift, say why it is not restocked) are answered in the UI, not as a toast
      if (const {'RETURN_NEEDS_MANAGER', 'OPEN_SHIFT_REQUIRED', 'RESTOCK_REASON_REQUIRED'}.contains(lastErrorCode)) {
        return (success: false, refundedAmount: null, newStatus: null, message: _dioMessage(e), tenders: const <PosPaymentLine>[]);
      }
      DioExceptionHandler.handleDioException(e);
      return (success: false, refundedAmount: null, newStatus: null, message: null, tenders: const <PosPaymentLine>[]);
    } catch (e) {
      debugPrint('❌ refundSale: $e');
      ToastUtil.showToast('Could not process refund.');
      return (success: false, refundedAmount: null, newStatus: null, message: null, tenders: const <PosPaymentLine>[]);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  /// Authorization comes from the current employee's signed token — see
  /// [refundSale]'s doc comment.
  Future<bool> voidSale(String saleId, {String? reason, String? reasonCode}) async {
    lastCreditNote = null;
    // G3.0: a void pays back at THIS till, so the register this till is paired with is named (its open shift takes the refund)
    String? voidRegister;
    try {
      voidRegister = await AppPreferences.getPosRegisterId();
    } catch (_) {}
    final payload = {
      if (reason != null && reason.isNotEmpty) 'reason': reason,
      if (reasonCode != null && reasonCode.isNotEmpty) 'reasonCode': reasonCode,
      if (voidRegister != null && voidRegister.isNotEmpty) 'registerId': voidRegister,
    };
    final fp = IdempotencyIntentStore.fingerprint('voidSale:$saleId', payload);
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSaleVoid(saleId),
        data: payload,
        requiresAuth: true,
        headers: await _writeHeaders(await _intents.keyFor(fp)),
      );
      settled = true;
      if (_ok(res)) {
        final cn = (res.data['data'] as Map?)?['creditNote'];
        if (cn is Map) lastCreditNote = cn.cast<String, dynamic>();
        return true;
      }
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to void sale');
      return false;
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('voidSale', e);
      _noteEntitlement(e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ voidSale: $e');
      ToastUtil.showToast('Failed to void sale.');
      return false;
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  // ── Quote (price a cart on the server, no side effects) ──────────────────

  /// What the server would charge for this cart — lines, discount, tax, total, currency, exponent and the
  /// settingsVersion used. Null when it can't be reached (offline / timeout): the caller then prices locally and the
  /// sale goes through the offline queue. A business refusal (POS plan, discount too large …) is returned in [message].
  Future<({PosQuote? quote, String? message, String? code})> quoteSale({
    required String storeId,
    required List<Map<String, dynamic>> items,
    String? discountType,
    double? discountValue,
    int? settingsVersion,
    String? couponCode,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSalesQuote,
        data: {
          'storeId': storeId,
          'items': items,
          if (couponCode != null && couponCode.trim().isNotEmpty) 'couponCode': couponCode.trim(),
          if (discountType != null && (discountValue ?? 0) > 0) ...{'discountType': discountType, 'discountValue': discountValue},
          if (settingsVersion != null) 'settingsVersion': settingsVersion,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (quote: PosQuote.fromJson(data), message: null, code: null);
      return (quote: null, message: res.data['message'] as String?, code: null);
    } on DioException catch (e) {
      _logDioError('quoteSale', e);
      _noteEntitlement(e);
      return (quote: null, message: isRetryableStatus(e.response?.statusCode, _dioCode(e)) ? null : _dioMessage(e), code: _dioCode(e));
    } catch (e) {
      debugPrint('❌ quoteSale: $e');
      return (quote: null, message: null, code: null);
    }
  }

  /// G2.4: the sale's public digital-receipt link (created on first use, the same link afterwards). Null when it can't be had
  /// right now (offline, or the sale has no receipt) — the caller simply doesn't show the QR.
  Future<String?> getReceiptLink(String saleId) async {
    try {
      final res = await _client.get(ApiConstants.posSaleReceiptLink(saleId), requiresAuth: true);
      final data = _data(res);
      return data is Map ? data['url'] as String? : null;
    } on DioException catch (e) {
      _logDioError('getReceiptLink', e);
      return null;
    } catch (e) {
      debugPrint('❌ getReceiptLink: $e');
      return null;
    }
  }

  // ── G2.5 documents ──
  Future<PosSaleDocuments?> getSaleDocuments(String saleId) async {
    try {
      final res = await _client.get(ApiConstants.posSaleDocuments(saleId), requiresAuth: true);
      final data = _data(res);
      return data is Map ? PosSaleDocuments.fromJson(data.cast<String, dynamic>()) : null;
    } on DioException catch (e) {
      _logDioError('getSaleDocuments', e);
      return null;
    } catch (e) {
      debugPrint('❌ getSaleDocuments: $e');
      return null;
    }
  }

  // ── G2.6 dashboard ──
  /// The Home business pulse, role-based by the server (a cashier's token gets their own shift only). Null when it can't be had.
  Future<Map<String, dynamic>?> getDashboard(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posDashboard(storeId), requiresAuth: true, headers: await _employeeAuthHeaders());
      final data = _data(res);
      return data is Map ? data.cast<String, dynamic>() : null;
    } on DioException catch (e) {
      _logDioError('getDashboard', e);
      return null;
    } catch (e) {
      debugPrint('❌ getDashboard: $e');
      return null;
    }
  }

  // ── G2.6 catalog edits (manager PIN; the server audits before/after and the storefront reads the same documents) ──
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> updateCatalogVariant(String storeId, String variantId, Map<String, dynamic> changes, {String? approverToken}) async {
    try {
      final res = await _client.patch(ApiConstants.posCatalogVariant(storeId, variantId), data: changes, requiresAuth: true, headers: {...await _employeeAuthHeaders(), if (approverToken != null) 'x-pos-employee-token': approverToken});
      final data = _data(res);
      return (success: true, message: null, code: null, data: data is Map ? data.cast<String, dynamic>() : null);
    } on DioException catch (e) {
      _logDioError('updateCatalogVariant', e);
      return (success: false, message: _dioMessage(e) ?? 'Could not save the change.', code: _dioCode(e), data: null);
    } catch (e) {
      debugPrint('❌ updateCatalogVariant: $e');
      return (success: false, message: 'Could not save the change.', code: null, data: null);
    }
  }

  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> adjustCatalogStock(String storeId, String variantId, {required int delta, required String reason, String? note, String? approverToken}) async {
    final payload = {'delta': delta, 'reason': reason, if (note != null && note.trim().isNotEmpty) 'note': note.trim()};
    final fp = IdempotencyIntentStore.fingerprint('catalogStock:$variantId', payload);
    var settled = false;
    try {
      final res = await _client.post(ApiConstants.posCatalogStock(storeId, variantId), data: payload, requiresAuth: true, headers: {...await _writeHeaders(await _intents.keyFor(fp)), if (approverToken != null) 'x-pos-employee-token': approverToken});
      settled = true;
      final data = _data(res);
      return (success: true, message: null, code: null, data: data is Map ? data.cast<String, dynamic>() : null);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('adjustCatalogStock', e);
      return (success: false, message: _dioMessage(e) ?? 'Could not change the stock.', code: _dioCode(e), data: null);
    } catch (e) {
      debugPrint('❌ adjustCatalogStock: $e');
      return (success: false, message: 'Could not change the stock.', code: null, data: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  // ── Offline review / discard ──────────────────────────────────────────────

  /// G2.7: find a sale of THIS STORE (any till) by the number on the customer's receipt: `OFF-…` (offline receipt), `INV-…`, the sale
  /// number, a bare number, or a credit note number (`CN-…`). Used by Orders search so a return can be made at a different till.
  Future<List<PosSaleModel>> lookupSales(String storeId, String ref) async {
    final q = ref.trim();
    if (q.isEmpty) return [];
    try {
      final res = await _client.get(ApiConstants.posSalesLookup(storeId, q), requiresAuth: true);
      final data = _data(res);
      return (data as List<dynamic>? ?? []).map((e) => PosSaleModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('lookupSales', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return [];
    } catch (e) {
      debugPrint('❌ lookupSales: $e');
      return [];
    }
  }

  Future<List<PosSaleModel>> getSalesNeedingReview(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posSalesNeedsReview(storeId), requiresAuth: true);
      final data = _data(res);
      return (data as List<dynamic>? ?? []).map((e) => PosSaleModel.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      _logDioError('getSalesNeedingReview', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return [];
    } catch (e) {
      debugPrint('❌ getSalesNeedingReview: $e');
      return [];
    }
  }

  Future<({bool success, String? message})> resolveSaleReview(String saleId, String note) async {
    final fp = IdempotencyIntentStore.fingerprint('resolveReview:$saleId', {'note': note});
    var settled = false;
    try {
      final res = await _client.post(
        ApiConstants.posSaleResolveReview(saleId),
        data: {'note': note},
        requiresAuth: true,
        headers: await _writeHeaders(await _intents.keyFor(fp)),
      );
      settled = true;
      return (success: _ok(res), message: res.data['message'] as String?);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('resolveSaleReview', e);
      return (success: false, message: _dioMessage(e));
    } catch (e) {
      return (success: false, message: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  /// Writes a manager's decision to give up on a queued sale to the server's audit log. [recorded] = it is on the
  /// server now (the device may delete its copy); [alreadySynced] = the sale actually reached the server after all.
  Future<({bool recorded, bool alreadySynced, bool connectivityError, String? message})> recordOfflineDiscard({
    required String storeId,
    required String idempotencyKey,
    required String reason,
    Map<String, dynamic>? summary,
    String? employeeToken,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posOfflineDiscards,
        data: {'storeId': storeId, 'idempotencyKey': idempotencyKey, 'reason': reason, if (summary != null) 'summary': summary},
        requiresAuth: true,
        headers: {
          ...await _employeeAuthHeaders(),
          if (employeeToken != null) 'x-pos-employee-token': employeeToken,
          'Idempotency-Key': 'discard-$idempotencyKey',
        },
      );
      return (recorded: _ok(res), alreadySynced: false, connectivityError: false, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('recordOfflineDiscard', e);
      if (_dioCode(e) == 'SALE_ALREADY_SYNCED') return (recorded: false, alreadySynced: true, connectivityError: false, message: _dioMessage(e));
      return (recorded: false, alreadySynced: false, connectivityError: _isConnectivityError(e) || !_isFinalFailure(e), message: _dioMessage(e));
    } catch (e) {
      return (recorded: false, alreadySynced: false, connectivityError: true, message: null);
    }
  }

  // ── Reports ──────────────────────────────────────────────────────────────

  Future<PosDailyReportModel?> getDailyReport(String storeId, {String? date, String? registerId}) async {
    try {
      final res = await _client.get(
        ApiConstants.posReportsDaily,
        queryParameters: {
          'storeId': storeId,
          if (date != null) 'date': date,
          if (registerId != null && registerId.isNotEmpty) 'registerId': registerId,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosDailyReportModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getDailyReport', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getDailyReport: $e');
      return null;
    }
  }

  Future<PosRangeReportModel?> getRangeReport(String storeId, {required String from, required String to}) async {
    try {
      final res = await _client.get(
        ApiConstants.posReportsRange,
        queryParameters: {'storeId': storeId, 'from': from, 'to': to},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosRangeReportModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getRangeReport', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getRangeReport: $e');
      return null;
    }
  }

  Future<PosRegisterReportModel?> getRegisterReport(String registerId, {String? from, String? to}) async {
    try {
      final res = await _client.get(
        ApiConstants.posReportsRegister(registerId),
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosRegisterReportModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getRegisterReport', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getRegisterReport: $e');
      return null;
    }
  }

  Future<PosEmployeeReportModel?> getEmployeeReport(
    String employeeId, {
    required String storeId,
    String? from,
    String? to,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posReportsEmployee(employeeId),
        queryParameters: {'storeId': storeId, if (from != null) 'from': from, if (to != null) 'to': to},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      return data != null ? PosEmployeeReportModel.fromJson(data) : null;
    } on DioException catch (e) {
      _logDioError('getEmployeeReport', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getEmployeeReport: $e');
      return null;
    }
  }

  /// Returns raw CSV bytes, or null on failure. Caller is responsible for
  /// sharing/saving (see ReceiptShareService / share_plus usage).
  Future<List<int>?> exportDailyReportCsv(String storeId, {String? date}) async {
    try {
      final res = await _client.get(
        ApiConstants.posReportsDailyExport,
        queryParameters: {'storeId': storeId, if (date != null) 'date': date},
        requiresAuth: true,
        responseType: ResponseType.bytes,
      );
      return res.data as List<int>;
    } on DioException catch (e) {
      _logDioError('exportDailyReportCsv', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ exportDailyReportCsv: $e');
      ToastUtil.showToast('Failed to export report.');
      return null;
    }
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<PosSettingsModel?> getPosSettings(String storeId) async {
    try {
      final res = await _client.get(ApiConstants.posSettings(storeId), requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return null;
      final settings = PosSettingsModel.fromJson(data);
      // The store's currency + exponent come from the backend; everything that formats money follows it.
      Money.configure(currency: settings.currency, exponent: settings.currencyExponent);
      unawaited(AppPreferences.saveStoreCurrency(settings.currency, settings.currencyExponent));
      return settings;
    } on DioException catch (e) {
      _logDioError('getPosSettings', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ getPosSettings: $e');
      return null;
    }
  }

  Future<PosSettingsModel?> updatePosSettings(String storeId, Map<String, dynamic> updates) async {
    try {
      final res = await _client.patch(ApiConstants.posSettings(storeId), data: updates, requiresAuth: true);
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return PosSettingsModel.fromJson(data);
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to save settings');
      return null;
    } on DioException catch (e) {
      _logDioError('updatePosSettings', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ updatePosSettings: $e');
      ToastUtil.showToast('Failed to save settings.');
      return null;
    }
  }

  // ── Audit logs ───────────────────────────────────────────────────────────

  Future<PagedResult<PosAuditLogModel>> getAuditLogs(
    String storeId, {
    int page = 1,
    int limit = 20,
    String? employeeId,
    String? action,
    String? targetType,
    String? from,
    String? to,
  }) async {
    try {
      final res = await _client.get(
        ApiConstants.posAuditLogs(storeId),
        queryParameters: {
          'page': page,
          'limit': limit,
          if (employeeId != null && employeeId.isNotEmpty) 'employeeId': employeeId,
          if (action != null && action.isNotEmpty) 'action': action,
          if (targetType != null && targetType.isNotEmpty) 'targetType': targetType,
          if (from != null) 'from': from,
          if (to != null) 'to': to,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data == null) return _emptyPage();
      return _page(data, 'logs', PosAuditLogModel.fromJson);
    } on DioException catch (e) {
      _logDioError('getAuditLogs', e);
      DioExceptionHandler.handleDioException(e);
      return _emptyPage();
    } catch (e) {
      debugPrint('❌ getAuditLogs: $e');
      return _emptyPage();
    }
  }

  // ── G3.1 inventory (device + PIN session; the server decides who may see / do what) ─────────────────────────────────────────────
  // Reads return null on failure and leave the server's `code` in [lastErrorCode]; writes return a record with `success`, `message`, `code`.

  String _inv(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/inventory/$path/$storeId';

  Future<T?> _invGet<T>(String tag, String url, T Function(Map<String, dynamic> data) parse, {Map<String, dynamic>? query, bool dataIsList = false}) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    try {
      final res = await _client.get(url, queryParameters: query, requiresAuth: true, headers: await _employeeAuthHeaders());
      if (!_ok(res)) return null;
      final data = res.data['data'];
      if (dataIsList) return parse({'list': data});
      return data is Map ? parse(data.cast<String, dynamic>()) : null;
    } on DioException catch (e) {
      _logDioError(tag, e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      return null;
    } catch (e) {
      debugPrint('❌ $tag: $e');
      return null;
    }
  }

  InvPage<InvRow> _invRows(Map<String, dynamic> d) => InvPage(
        items: [for (final e in (d['items'] as List? ?? const [])) if (e is Map) InvRow.fromJson(e.cast<String, dynamic>())],
        total: (d['total'] as num?)?.toInt() ?? 0,
        page: (d['page'] as num?)?.toInt() ?? 1,
        hasMore: d['hasMore'] == true,
      );

  Future<InvOverview?> getInventoryOverview(String storeId) => _invGet('inventoryOverview', _inv(storeId, 'overview'), InvOverview.fromJson);

  /// [filter]: all | low | out.
  Future<InvPage<InvRow>?> getInventoryStock(String storeId, {String search = '', String filter = 'all', int page = 1, int limit = 30}) =>
      _invGet('inventoryStock', _inv(storeId, 'stock'), _invRows, query: {if (search.trim().isNotEmpty) 'search': search.trim(), 'filter': filter, 'page': page, 'limit': limit});

  Future<InvPage<InvRow>?> getInventoryLowStock(String storeId) => _invGet('inventoryLowStock', _inv(storeId, 'low-stock'), _invRows);

  Future<List<InvRow>?> lookupInventory(String storeId, String code) async {
    final r = await _invGet<List<InvRow>>('inventoryLookup', _inv(storeId, 'lookup'), (d) => [for (final e in (d['list'] as List? ?? const [])) if (e is Map) InvRow.fromJson(e.cast<String, dynamic>())], query: {'code': code.trim()}, dataIsList: true);
    return r;
  }

  Future<InvDetail?> getInventoryVariant(String storeId, String variantId) => _invGet('inventoryVariant', '${_inv(storeId, 'variant')}/$variantId', InvDetail.fromJson);

  /// Managers / owners only (a cashier gets `POS_ACTION_FORBIDDEN` in [lastErrorCode]).
  Future<InvPage<InvMovement>?> getInventoryMovements(String storeId, {String? variantId, String? type, DateTime? from, DateTime? to, int page = 1, int limit = 30}) =>
      _invGet(
        'inventoryMovements',
        _inv(storeId, 'movements'),
        (d) => InvPage(
          items: [for (final e in (d['items'] as List? ?? const [])) if (e is Map) InvMovement.fromJson(e.cast<String, dynamic>())],
          total: (d['total'] as num?)?.toInt() ?? 0,
          page: (d['page'] as num?)?.toInt() ?? 1,
          hasMore: d['hasMore'] == true,
        ),
        query: {
          if (variantId != null) 'variantId': variantId,
          if (type != null && type.isNotEmpty) 'type': type,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
          'page': page,
          'limit': limit,
        },
      );

  Future<({int exponent, List<InvLimit> limits})?> getInventoryLimits(String storeId) => _invGet(
        'inventoryLimits',
        _inv(storeId, 'limits'),
        (d) => (exponent: (d['currencyExponent'] as num?)?.toInt() ?? 2, limits: [for (final e in (d['limits'] as List? ?? const [])) if (e is Map) InvLimit.fromJson(e.cast<String, dynamic>())]),
      );

  /// Manual stock change. [reason]: restocked | damaged | correction | other (note required for other). When the server answers
  /// `POS_APPROVAL_REQUIRED`, ask a manager and call again with [approverToken] (sent as `x-pos-approver-token`).
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> adjustInventory(String storeId, String variantId, {required int delta, required String reason, String? note, String? locationId, String? approverToken}) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    final payload = {'delta': delta, 'reason': reason, if (note != null && note.trim().isNotEmpty) 'note': note.trim(), if (locationId != null) 'locationId': locationId};
    final fp = IdempotencyIntentStore.fingerprint('invAdjust:$variantId${approverToken != null ? ':approved' : ''}', payload);
    var settled = false;
    try {
      final res = await _client.post(
        '${_inv(storeId, 'adjust')}/$variantId',
        data: payload,
        requiresAuth: true,
        headers: {...await _writeHeaders(await _intents.keyFor(fp)), if (approverToken != null) 'x-pos-approver-token': approverToken},
      );
      settled = true;
      final data = _data(res);
      return (success: _ok(res), message: res.data is Map ? res.data['message'] as String? : null, code: null, data: data is Map ? data.cast<String, dynamic>() : null);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError('adjustInventory', e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      final body = e.response?.data;
      if (body is Map && body['reasons'] is List) lastErrorReasons = [for (final r in body['reasons'] as List) r.toString()];
      return (success: false, message: _dioMessage(e), code: lastErrorCode, data: null);
    } catch (e) {
      debugPrint('❌ adjustInventory: $e');
      return (success: false, message: 'Could not change the stock.', code: null, data: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  // — stock counts —

  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> _invCountPost(String tag, String url, Map<String, dynamic> payload, {String intent = ''}) async {
    lastErrorCode = null;
    final fp = IdempotencyIntentStore.fingerprint('$tag:$url:$intent', payload);
    var settled = false;
    try {
      final res = await _client.post(url, data: payload, requiresAuth: true, headers: await _writeHeaders(await _intents.keyFor(fp)));
      settled = true;
      final data = _data(res);
      return (success: _ok(res), message: res.data is Map ? res.data['message'] as String? : null, code: null, data: data is Map ? data.cast<String, dynamic>() : null);
    } on DioException catch (e) {
      settled = _isFinalFailure(e);
      _logDioError(tag, e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      return (success: false, message: _dioMessage(e), code: lastErrorCode, data: null);
    } catch (e) {
      debugPrint('❌ $tag: $e');
      return (success: false, message: 'Could not reach the server.', code: null, data: null);
    } finally {
      if (settled) await _intents.release(fp);
    }
  }

  Future<List<InvCount>?> listInventoryCounts(String storeId) async {
    final r = await _invGet<List<InvCount>>('inventoryCounts', _inv(storeId, 'counts'), (d) => [for (final e in (d['list'] as List? ?? const [])) if (e is Map) InvCount.fromJson(e.cast<String, dynamic>())], dataIsList: true);
    return r;
  }

  Future<InvCount?> getInventoryCount(String storeId, String countId) => _invGet('inventoryCount', '${_inv(storeId, 'counts')}/$countId', InvCount.fromJson);

  /// Count line for a scanned / typed barcode or SKU: `(found: false)` means "not on this count"; null = the request failed.
  Future<({bool found, InvCountItem? item})?> findInventoryCountItem(String storeId, String countId, String code) => _invGet(
        'inventoryCountFind',
        '${_inv(storeId, 'counts')}/$countId/find',
        (d) => (found: d['found'] == true, item: d['item'] is Map ? InvCountItem.fromJson((d['item'] as Map).cast<String, dynamic>()) : null),
        query: {'code': code.trim()},
      );

  Future<({bool success, String? message, String? code, InvCount? count})> startInventoryCount(String storeId, {String? locationId}) async {
    final r = await _invCountPost('inventoryCountStart', _inv(storeId, 'counts'), {if (locationId != null) 'locationId': locationId});
    return (success: r.success, message: r.message, code: r.code, count: r.data == null ? null : InvCount.fromJson(r.data!));
  }

  Future<({bool success, String? message, String? code, InvCount? count})> enterInventoryCount(String storeId, String countId, String itemId, int countedQty) async {
    final r = await _invCountPost('inventoryCountEnter', '${_inv(storeId, 'counts')}/$countId/items/$itemId', {'countedQty': countedQty}, intent: '$countedQty');
    return (success: r.success, message: r.message, code: r.code, count: r.data == null ? null : InvCount.fromJson(r.data!));
  }

  /// Posts the variances as stock changes (idempotent on the server). `data` = `{count, applied, skipped}`.
  Future<({bool success, String? message, String? code, InvCountResult? result})> finishInventoryCount(String storeId, String countId) async {
    final r = await _invCountPost('inventoryCountFinish', '${_inv(storeId, 'counts')}/$countId/finish', const {});
    final d = r.data;
    return (
      success: r.success,
      message: r.message,
      code: r.code,
      result: d == null ? null : InvCountResult(applied: (d['applied'] as num?)?.toInt() ?? 0, skipped: [for (final s in (d['skipped'] as List? ?? const [])) '$s']),
    );
  }

  Future<({bool success, String? message, String? code})> cancelInventoryCount(String storeId, String countId) async {
    final r = await _invCountPost('inventoryCountCancel', '${_inv(storeId, 'counts')}/$countId/cancel', const {});
    return (success: r.success, message: r.message, code: r.code);
  }
}

/// Whether an HTTP failure leaves the outcome UNKNOWN (so the request may be retried / queued with its
/// SAME idempotency key) as opposed to a definite answer.
///  * no response (connectivity/timeouts) → retryable
///  * 5xx, 408, 429 → retryable
///  * 409 → retryable ONLY for `IDEMPOTENCY_IN_PROGRESS`; every other 409 is a business conflict
///    (HELD_SALE_ALREADY_RESOLVED, SALE_CHANGED_CONCURRENTLY, SESSION_ALREADY_CLOSED, …) and is final
///  * every other 4xx → final
bool isRetryableStatus(int? status, String? code) {
  if (status == null) return true;
  if (status >= 500) return true;
  if (status == 408 || status == 429) return true;
  if (status == 409) return code == 'IDEMPOTENCY_IN_PROGRESS';
  return false;
}

/// The server's pricing of a cart (`POST /pos/sales/quote`).
class PosQuote {
  final double subtotal;
  final double discount;
  final double tax;
  final double total;
  final double taxRate;
  final String currency;
  final int currencyExponent;
  final int settingsVersion;
  final bool settingsVersionReplaced;

  /// The server's current unit price per variant (variantId → price) — used to refresh a stale cart.
  final Map<String, double> unitPrices;

  /// G2.4: the coupon the server applied (code + how it discounts: 'percent' or 'amount'), null when none.
  final PosAppliedCoupon? coupon;

  const PosQuote({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.taxRate,
    required this.currency,
    required this.currencyExponent,
    required this.settingsVersion,
    this.settingsVersionReplaced = false,
    this.unitPrices = const {},
    this.coupon,
  });

  factory PosQuote.fromJson(Map<String, dynamic> j) {
    final exp = (j['currencyExponent'] as num?)?.toInt() ?? 2;
    return PosQuote(
        subtotal: MoneyJson.read(j, 'subtotal', exp: exp),
        discount: MoneyJson.read(j, 'discount', exp: exp),
        tax: MoneyJson.read(j, 'tax', exp: exp),
        total: MoneyJson.read(j, 'total', exp: exp),
        taxRate: (j['taxRate'] as num?)?.toDouble() ?? 0,
        currency: (j['currency'] as String?)?.toUpperCase() ?? 'USD',
        currencyExponent: (j['currencyExponent'] as num?)?.toInt() ?? 2,
        settingsVersion: (j['settingsVersion'] as num?)?.toInt() ?? 1,
        settingsVersionReplaced: j['settingsVersionReplaced'] as bool? ?? false,
        unitPrices: {
          for (final l in (j['lines'] as List? ?? []))
            if ((l as Map)['variantId'] != null) l['variantId'] as String: MoneyJson.read(l, 'price', exp: exp),
        },
        coupon: j['coupon'] is Map ? PosAppliedCoupon.fromJson((j['coupon'] as Map).cast<String, dynamic>()) : null,
      );
  }
}

/// A coupon the server accepted for the cart: shown on the sale screen and sent again (as `couponCode`) when the sale is charged.
class PosAppliedCoupon {
  final String code;
  final String discountType; // 'percent' | 'fixed' (storefront naming) — informational; the quote's `discount` is the amount
  final double discountValue;
  const PosAppliedCoupon({required this.code, required this.discountType, required this.discountValue});

  factory PosAppliedCoupon.fromJson(Map<String, dynamic> j) => PosAppliedCoupon(
        code: (j['code'] as String? ?? '').toUpperCase(),
        discountType: j['discountType'] as String? ?? 'percent',
        discountValue: (j['discountValue'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {'code': code, 'discountType': discountType, 'discountValue': discountValue};
}
