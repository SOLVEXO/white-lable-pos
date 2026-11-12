import 'dart:async';
import 'package:solvexo_pos/app/data/models/pos/pos_connectors_models.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_page_models.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_catalog_admin_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
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
    List<Map<String, int>>? denominations, // G4.6: the notes / coins counted into the float (their total must equal openingCash)
  }) async {
    lastErrorCode = null;
    final payload = {
      'storeId': storeId,
      'registerId': registerId,
      'employeeId': employeeId,
      if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
      'openingCash': openingCash,
      if (denominations != null && denominations.isNotEmpty) 'denominations': denominations,
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
      lastErrorCode = _dioCode(e);
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
    List<Map<String, int>>? denominations, // G4.6: the notes / coins counted at close (their total must equal closingCash)
  }) async {
    lastErrorCode = null;
    final payload = {
      'sessionId': sessionId,
      'closingCash': closingCash,
      if (cardTotalFromSlip != null) 'cardTotalFromSlip': cardTotalFromSlip,
      if (denominations != null && denominations.isNotEmpty) 'denominations': denominations,
    };
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
    String? expiredApproverToken, // G3.2: a manager's token approving the sale of EXPIRED lot units (`items[].sellExpired`), sent as `x-pos-approver-token`
    int? redeemPoints, // G3.3: loyalty points spent on this sale (online only; the SERVER prices them)
    String? priceBookId, // G4.5: the price book picked at checkout (the server prices with it)
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
      'priceBookId': ?priceBookId,
      if (redeemPoints != null && redeemPoints > 0) 'redeemPoints': redeemPoints,
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
        headers: {...await _writeHeaders(key), if (approverToken != null) 'x-pos-employee-token': approverToken, if (expiredApproverToken != null) 'x-pos-approver-token': expiredApproverToken},
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
      // G3.3: store credit and points need a live balance check — never queued either
      final hasCustomerMoney = status != 'held' && (payload.containsKey('redeemPoints') || (payload['payments'] as List<dynamic>? ?? const []).any((p) => p is Map && p['method'] == 'store_credit'));
      if (!_isFinalFailure(e) && !hasDigital && !hasCoupon && !hasCustomerMoney && Get.isRegistered<PendingSaleSyncService>()) {
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
        // G3.2: `sellExpired` is never sent for an offline sale (the server allocates the lots at sync and flags what it finds)
        final queued = {
          ...minorPayload,
          'items': [for (final i in (minorPayload['items'] as List<dynamic>)) i is Map ? ({...i}..remove('sellExpired')) : i],
          'offline': true,
        };
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
    String? registerId, // G5.1
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
          if (registerId != null && registerId.isNotEmpty) 'registerId': registerId,
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
    String? refundTo, // G3.3: 'store_credit' = the cash / card / other part of this refund becomes store credit for the sale's customer
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
      if (refundTo != null) 'refundTo': refundTo,
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
    String? priceBookId, // G4.5: the book picked at checkout (PRICE_BOOK_NOT_ACTIVE when it is not in force)
    String? customerId, // G4.5: so the customer's own price book prices the quote as it will the sale
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSalesQuote,
        data: {
          'storeId': storeId,
          'items': items,
          'priceBookId': ?priceBookId,
          'customerId': ?customerId,
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
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
        cur: InvCur.fromJson(d),
        costsHidden: d['costsHidden'] == true,
      );

  Future<InvOverview?> getInventoryOverview(String storeId) => _invGet('inventoryOverview', _inv(storeId, 'overview'), InvOverview.fromJson);

  /// [filter]: all | low | out.
  /// G5.1 [locationId]: only what is stocked at that location; each row then carries `locationStock`.
  Future<InvPage<InvRow>?> getInventoryStock(String storeId, {String search = '', String filter = 'all', int page = 1, int limit = 30, String? locationId}) =>
      _invGet('inventoryStock', _inv(storeId, 'stock'), _invRows, query: {if (search.trim().isNotEmpty) 'search': search.trim(), 'filter': filter, 'page': page, 'limit': limit, 'locationId': ?locationId});

  /// G5.1: the store's locations, quietly (no toast) — for the stock list's location filter. Null on failure.
  Future<List<StoreLocationModel>?> getStoreLocations(String storeId) => _invGet<List<StoreLocationModel>>(
    'storeLocations',
    _inv(storeId, 'locations'), // the till-readable list (the owner-session locations route refuses device tokens)
    (d) => [
      for (final e in (d['locations'] as List? ?? const []))
        if (e is Map) StoreLocationModel(id: '${e['id'] ?? ''}', storeId: storeId, sellerId: '', name: e['name'] as String? ?? '', status: e['status'] as String? ?? 'active', createdAt: DateTime.fromMillisecondsSinceEpoch(0)),
    ],
  );

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
          cur: InvCur.fromJson(d),
          costsHidden: d['costsHidden'] == true,
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

  Future<({InvCur? cur, List<InvLimit> limits})?> getInventoryLimits(String storeId) => _invGet(
        'inventoryLimits',
        _inv(storeId, 'limits'),
        (d) => (cur: InvCur.fromJson(d), limits: [for (final e in (d['limits'] as List? ?? const [])) if (e is Map) InvLimit.fromJson(e.cast<String, dynamic>())]),
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

  // ── G3.2 lots ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

  /// First-expiry-first-out preview for [qty] units of a lot-tracked item: the lots a sale would take from. Null on failure (the code is in [lastErrorCode]).
  Future<LotPreview?> getLotPreview(String storeId, String variantId, int qty) => _invGet(
    'lotPreview',
    '${ApiConstants.apiPrefix}/pos/inventory/lots/$storeId/$variantId',
    (d) => LotPreview.fromJson(d, asOf: DateTime.now()),
    query: {'qty': qty},
  );

  // ── G3.3 customers, store credit, loyalty ──────────────────────────────────────────────────────────────────────────────────────

  String _cust(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/customers/$path$storeId';

  Future<CustomerConfig?> getCustomerConfig(String storeId) => _invGet('customerConfig', _cust(storeId, 'config/'), CustomerConfig.fromJson);

  /// Search by name, phone or e-mail; an empty [q] lists the most recent customers.
  Future<PosCustomerPage?> searchPosCustomers(String storeId, String q) => _invGet(
    'customerSearch',
    _cust(storeId, 'search/'),
    (d) => PosCustomerPage(items: [for (final e in (d['items'] as List? ?? const [])) if (e is Map) PosCustomer.fromJson(e.cast<String, dynamic>())], cur: InvCur.fromJson(d)),
    query: {'q': q.trim()},
  );

  Future<CustomerProfile?> getCustomerProfile(String storeId, String customerId) => _invGet('customerProfile', '${_cust(storeId, 'profile/')}/$customerId', CustomerProfile.fromJson);

  /// Managers / owners only.
  Future<CreditLedgerPage?> getCustomerCredit(String storeId, String customerId, {int page = 1}) => _invGet(
    'customerCredit',
    '${_cust(storeId, 'credit/')}/$customerId',
    (d) => CreditLedgerPage(
      enabled: d['enabled'] == true,
      cur: InvCur.fromJson(d),
      items: [for (final e in (d['items'] as List? ?? const [])) if (e is Map) CreditEntry.fromJson(e.cast<String, dynamic>())],
      hasMore: d['hasMore'] == true,
    ),
    query: {'page': page},
  );

  /// One idempotent write of the customer endpoints. The key belongs to this intent (same payload = same key until the server answers).
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> _customerWrite(String tag, String method, String url, Map<String, dynamic> payload) async {
    lastErrorCode = null;
    final fp = IdempotencyIntentStore.fingerprint('$tag:$url', payload);
    var settled = false;
    try {
      final headers = await _writeHeaders(await _intents.keyFor(fp));
      final res = method == 'PATCH' ? await _client.patch(url, data: payload, requiresAuth: true, headers: headers) : await _client.post(url, data: payload, requiresAuth: true, headers: headers);
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

  static Map<String, dynamic> _customerFields(Map<String, dynamic> fields) => {
    for (final e in fields.entries)
      // `registrationType: null` is meaningful on an edit (it CLEARS the type); every other empty field is simply not sent
      if (e.value != null || e.key == 'registrationType') e.key: e.value is String ? (e.value as String).trim() : e.value,
  };

  /// Same phone number = the same customer: the result has `existing: true` and nothing new is made. All fields except [fields]`['name']` are optional.
  Future<({bool success, String? message, String? code, PosCustomer? customer})> createPosCustomer(String storeId, Map<String, dynamic> fields) async {
    final r = await _customerWrite('customerCreate', 'POST', _cust(storeId, ''), _customerFields(fields));
    return (success: r.success, message: r.message, code: r.code, customer: r.data == null ? null : PosCustomer.fromJson(r.data!));
  }

  /// Managers / owners only (a cashier gets `POS_ACTION_FORBIDDEN`; another customer's phone gives `PHONE_IN_USE`).
  Future<({bool success, String? message, String? code, PosCustomer? customer})> updatePosCustomer(String storeId, String customerId, Map<String, dynamic> fields) async {
    final r = await _customerWrite('customerUpdate', 'PATCH', '${_cust(storeId, '')}/$customerId', _customerFields(fields));
    return (success: r.success, message: r.message, code: r.code, customer: r.data == null ? null : PosCustomer.fromJson(r.data!));
  }

  /// Managers / owners only. [amountMinor] is signed (never 0); above the manager's limit the server answers `POS_OWNER_REQUIRED`.
  Future<({bool success, String? message, String? code})> adjustCustomerCredit(String storeId, String customerId, {required int amountMinor, required String note, DateTime? expiresAt}) async {
    final r = await _customerWrite('customerCreditAdjust', 'POST', '${_cust(storeId, 'credit/')}/$customerId/adjust', {
      'amountMinor': amountMinor,
      'note': note.trim(),
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
    });
    return (success: r.success, message: r.message, code: r.code);
  }

  // ── G3.4 supply: suppliers, purchase orders, receiving, supplier returns, payables, supplier payments ────────────────────────────
  // Reads return null on failure (the server's `code` is in [lastErrorCode]; no code = no connection). Writes return a record with
  // `success`, `message`, `code`. The server decides who may do what: a cashier gets no costs and POS_ACTION_FORBIDDEN on manager actions.

  String _sup(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/supply/$path/$storeId';

  Future<SupplierList?> getSuppliers(String storeId) => _invGet('supplyList', _sup(storeId, 'suppliers'), SupplierList.fromJson);

  Future<SupplierProfile?> getSupplier(String storeId, String supplierId) => _invGet('supplyOne', '${_sup(storeId, 'suppliers')}/$supplierId', SupplierProfile.fromJson);

  /// [status]: all | draft | approved | sent | partially_received | received | cancelled (a cashier always gets only the receivable ones, without costs).
  Future<PoList?> getSupplyOrders(String storeId, {String status = 'all', String? supplierId}) =>
      _invGet('supplyOrders', _sup(storeId, 'orders'), PoList.fromJson, query: {if (status != 'all') 'status': status, if (supplierId != null) 'supplierId': supplierId});

  Future<PoDetail?> getSupplyOrder(String storeId, String orderId) => _invGet('supplyOrder', '${_sup(storeId, 'orders')}/$orderId', PoDetail.fromJson);

  /// Managers / owners only.
  Future<List<SupplyReceipt>?> getSupplyReceipts(String storeId, {String? supplierId, String? purchaseOrderId}) => _invGet(
    'supplyReceipts',
    _sup(storeId, 'receipts'),
    (d) => [for (final e in (d['receipts'] as List? ?? const [])) if (e is Map) SupplyReceipt.fromJson(e.cast<String, dynamic>())],
    query: {if (supplierId != null) 'supplierId': supplierId, if (purchaseOrderId != null) 'purchaseOrderId': purchaseOrderId},
  );

  /// Managers / owners only.
  Future<Payables?> getPayables(String storeId) => _invGet('supplyPayables', _sup(storeId, 'payables'), Payables.fromJson);

  /// Managers / owners only: the supplier's ledger, newest first, each entry with the running balance.
  Future<SupplierLedger?> getSupplierLedger(String storeId, String supplierId) => _invGet('supplyLedger', '${_sup(storeId, 'payables')}/$supplierId', SupplierLedger.fromJson);

  /// One write of the supply endpoints. The Idempotency-Key belongs to this intent (same payload = same key until the server answers).
  /// [approverToken] (a manager's approval of THIS action) goes in `x-pos-approver-token`.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> _supplyWrite(
    String tag,
    String method,
    String url,
    Map<String, dynamic> payload, {
    String? approverToken,
  }) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    final fp = IdempotencyIntentStore.fingerprint('$tag:$url${approverToken != null ? ':approved' : ''}', payload);
    var settled = false;
    try {
      final headers = {...await _writeHeaders(await _intents.keyFor(fp)), if (approverToken != null) 'x-pos-approver-token': approverToken};
      final res = method == 'PATCH' ? await _client.patch(url, data: payload, requiresAuth: true, headers: headers) : await _client.post(url, data: payload, requiresAuth: true, headers: headers);
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

  Future<({bool success, String? message, String? code, Supplier? supplier})> createSupplier(String storeId, Map<String, dynamic> fields) async {
    final r = await _supplyWrite('supplyCreate', 'POST', _sup(storeId, 'suppliers'), fields);
    return (success: r.success, message: r.message, code: r.code, supplier: r.data?['supplier'] is Map ? Supplier.fromJson((r.data!['supplier'] as Map).cast<String, dynamic>()) : null);
  }

  Future<({bool success, String? message, String? code, Supplier? supplier})> updateSupplier(String storeId, String supplierId, Map<String, dynamic> fields) async {
    final r = await _supplyWrite('supplyUpdate', 'PATCH', '${_sup(storeId, 'suppliers')}/$supplierId', fields);
    return (success: r.success, message: r.message, code: r.code, supplier: r.data?['supplier'] is Map ? Supplier.fromJson((r.data!['supplier'] as Map).cast<String, dynamic>()) : null);
  }

  PurchaseOrder? _poOf(Map<String, dynamic>? d) => d?['order'] is Map ? PurchaseOrder.fromJson({...(d!['order'] as Map).cast<String, dynamic>(), ...?_curOf(d)}) : null;
  Map<String, dynamic>? _curOf(Map<String, dynamic> d) => d['currency'] != null ? {'currency': d['currency'], 'currencyExponent': d['currencyExponent']} : null;

  /// Managers / owners only. Money is integer minor units: `items[].unitCostMinor`, `shippingMinor`, `taxMinor`.
  Future<({bool success, String? message, String? code, PurchaseOrder? order})> createSupplyOrder(String storeId, Map<String, dynamic> payload) async {
    final r = await _supplyWrite('supplyOrderCreate', 'POST', _sup(storeId, 'orders'), payload);
    return (success: r.success, message: r.message, code: r.code, order: _poOf(r.data));
  }

  /// Managers / owners only. An approved / sent order that is edited goes back to draft; `PO_NOT_EDITABLE` once receiving started.
  Future<({bool success, String? message, String? code, PurchaseOrder? order})> updateSupplyOrder(String storeId, String orderId, Map<String, dynamic> payload) async {
    final r = await _supplyWrite('supplyOrderUpdate', 'PATCH', '${_sup(storeId, 'orders')}/$orderId', payload);
    return (success: r.success, message: r.message, code: r.code, order: _poOf(r.data));
  }

  /// [action]: approve | send | cancel | close-short. Approving above the store's limit needs the owner; [approverToken] answers `POS_APPROVAL_REQUIRED`.
  Future<({bool success, String? message, String? code, PurchaseOrder? order})> supplyOrderAction(String storeId, String orderId, String action, {String? approverToken}) async {
    final r = await _supplyWrite('supplyOrder_$action', 'POST', '${_sup(storeId, 'orders')}/$orderId/$action', const {}, approverToken: approverToken);
    return (success: r.success, message: r.message, code: r.code, order: _poOf(r.data));
  }

  /// A goods receipt. With `purchaseOrderId` the lines are `{poItemId, qtyGood, qtyDamaged, lotNumber?, expiryDate?}` (a cashier sends NO cost);
  /// without one (managers) `{variantId, qtyGood, qtyDamaged, unitCostMinor, ...}` plus `supplierId`. `requestId` makes a retry safe.
  Future<({bool success, String? message, String? code, ReceiveResult? result})> receiveSupply(String storeId, Map<String, dynamic> payload) async {
    final r = await _supplyWrite('supplyReceive', 'POST', _sup(storeId, 'receipts'), payload);
    return (success: r.success, message: r.message, code: r.code, result: r.data == null ? null : ReceiveResult.fromJson(r.data!));
  }

  /// Managers / owners only: items `{variantId, quantity, lotId?, fromDamaged?}` back to the supplier of [receiptId] (or [supplierId]); the credit goes to the ledger.
  Future<({bool success, String? message, String? code, SupplierReturnResult? result})> createSupplierReturn(String storeId, Map<String, dynamic> payload) async {
    final r = await _supplyWrite('supplyReturn', 'POST', _sup(storeId, 'returns'), payload);
    return (success: r.success, message: r.message, code: r.code, result: r.data == null ? null : SupplierReturnResult.fromJson(r.data!));
  }

  /// Managers / owners only. [method]: cash (needs the open shift's [sessionId]) | bank | other. Above the manager's limit the owner approves
  /// (`POS_OWNER_REQUIRED` / `POS_APPROVAL_REQUIRED`); `EXCEEDS_BALANCE` when it is more than is owed. [requestId] makes a retry safe.
  Future<({bool success, String? message, String? code, SupplierPaymentResult? result})> paySupplier(
    String storeId,
    String supplierId, {
    required int amountMinor,
    required String method,
    required String requestId,
    String? reference,
    String? sessionId,
    String? approverToken,
  }) async {
    final r = await _supplyWrite('supplyPay', 'POST', '${_sup(storeId, 'payments')}/$supplierId', {
      'amountMinor': amountMinor,
      'method': method,
      'requestId': requestId,
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      if (method == 'cash' && sessionId != null) 'sessionId': sessionId,
    }, approverToken: approverToken);
    return (success: r.success, message: r.message, code: r.code, result: r.data == null ? null : SupplierPaymentResult.fromJson(r.data!));
  }

  // ── G3.5 cash & daybook: cash in / out, expenses (+ private receipt photo), the daybook ────────────────────────────────────────
  // Reads return null on failure ([lastErrorCode] holds the server's code; null = no connection). Writes return a record that also says
  // whether the failure may be retried (`retryable`: no answer, timeout, 5xx, "still in progress") or is a definite "no": the offline
  // queue keeps retrying the first kind and parks the second one under Needs attention.

  String _cash(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/cash/$path/$storeId';

  Future<CashConfig?> getCashConfig(String storeId) => _invGet('cashConfig', _cash(storeId, 'config'), CashConfig.fromJson);

  /// Managers / owners see every expense; a cashier only their own. [from] inclusive, [to] exclusive.
  Future<ExpenseList?> getExpenses(String storeId, {String status = 'all', DateTime? from, DateTime? to}) => _invGet(
    'cashExpenses',
    _cash(storeId, 'expenses'),
    ExpenseList.fromJson,
    query: {if (status != 'all') 'status': status, if (from != null) 'from': from.toUtc().toIso8601String(), if (to != null) 'to': to.toUtc().toIso8601String()},
  );

  Future<Expense?> getExpense(String storeId, String id) =>
      _invGet('cashExpense', '${_cash(storeId, 'expenses')}/$id', (d) => Expense.fromJson((d['expense'] is Map ? (d['expense'] as Map).cast<String, dynamic>() : <String, dynamic>{}), fallbackCur: InvCur.fromJson(d)));

  /// A fresh link to the private receipt, valid for at most 5 minutes. The caller shows it and drops it: it is never stored or logged.
  Future<ReceiptLink?> getExpenseReceiptLink(String storeId, String id) => _invGet('cashReceiptLink', '${_cash(storeId, 'expenses')}/$id/receipt', ReceiptLink.fromJson);

  /// The day's cash ledger: shifts that OPENED between [from] (inclusive) and [to] (exclusive). A cashier only gets their own shifts.
  Future<Daybook?> getDaybook(String storeId, {required DateTime from, required DateTime to, String? registerId}) => _invGet(
    'cashDaybook',
    _cash(storeId, 'daybook'),
    Daybook.fromJson,
    query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), if (registerId != null) 'registerId': registerId},
  );

  /// One write of the cash endpoints. [idempotencyKey] is the intent's stable key (the request id), so a retry or an offline replay can
  /// never be booked twice. [employeeToken] replays a queued request as the employee who made it; [approverToken] is a manager's approval.
  Future<({bool success, String? message, String? code, bool retryable, Map<String, dynamic>? data})> _cashWrite(
    String tag,
    String url,
    Map<String, dynamic> payload, {
    required String idempotencyKey,
    String? employeeToken,
    String? approverToken,
  }) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    try {
      final headers = {...await _writeHeaders(idempotencyKey), if (employeeToken != null) 'x-pos-employee-token': employeeToken, if (approverToken != null) 'x-pos-approver-token': approverToken};
      final res = await _client.post(url, data: payload, requiresAuth: true, headers: headers);
      final data = _data(res);
      return (success: _ok(res), message: res.data is Map ? res.data['message'] as String? : null, code: null, retryable: false, data: data is Map ? data.cast<String, dynamic>() : null);
    } on DioException catch (e) {
      _logDioError(tag, e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      return (success: false, message: _dioMessage(e), code: lastErrorCode, retryable: !_isFinalFailure(e), data: null);
    } catch (e) {
      debugPrint('❌ $tag: $e');
      return (success: false, message: 'Could not reach the server.', code: null, retryable: true, data: null);
    }
  }

  /// A cash in / out on the open shift ([sessionId]). [type]: cash_in | cash_out. [amountMinor] is minor units; [note] is required for `other_*`.
  /// Above the store's limit the server answers `POS_APPROVAL_REQUIRED`: call again with [approverToken]. `occurredAt` keeps the device's time
  /// (an offline movement replays with it). `duplicate: true` means this request id was already booked: treat it as success.
  Future<({bool success, String? message, String? code, bool retryable, CashMovementResult? result})> recordCashMovement(
    String storeId, {
    required String type,
    required String category,
    required int amountMinor,
    required String sessionId,
    required String requestId,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
    String? approverToken,
  }) async {
    final r = await _cashWrite('cashMove', _cash(storeId, 'movements'), {
      'type': type,
      'category': category,
      'amountMinor': amountMinor,
      'sessionId': sessionId,
      'requestId': requestId,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String(),
    }, idempotencyKey: 'cash-$requestId', employeeToken: employeeToken, approverToken: approverToken);
    return (success: r.success, message: r.message, code: r.code, retryable: r.retryable, result: r.data == null ? null : CashMovementResult.fromJson(r.data!));
  }

  /// Records an expense. A `cash` expense comes out of the open shift's drawer ([sessionId] needed); bank / other are only recorded.
  Future<({bool success, String? message, String? code, bool retryable, ExpenseSaved? result})> recordExpense(
    String storeId, {
    required String category,
    required String method,
    required int amountMinor,
    required String requestId,
    String? sessionId,
    String? payee,
    String? note,
    DateTime? occurredAt,
    String? employeeToken,
    String? approverToken,
  }) async {
    final r = await _cashWrite('cashExpense', _cash(storeId, 'expenses'), {
      'category': category,
      'method': method,
      'amountMinor': amountMinor,
      'requestId': requestId,
      if (method == 'cash' && sessionId != null) 'sessionId': sessionId,
      if (payee != null && payee.trim().isNotEmpty) 'payee': payee.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      if (occurredAt != null) 'occurredAt': occurredAt.toUtc().toIso8601String(),
    }, idempotencyKey: 'exp-$requestId', employeeToken: employeeToken, approverToken: approverToken);
    return (success: r.success, message: r.message, code: r.code, retryable: r.retryable, result: r.data == null ? null : ExpenseSaved.fromJson(r.data!));
  }

  /// Managers only: approve or reject an expense after the fact (a rejection needs a [note]). Moves no cash.
  Future<({bool success, String? message, String? code, Expense? expense})> decideExpense(String storeId, String id, {required bool approve, String? note}) async {
    final payload = {'decision': approve ? 'approve' : 'reject', if (note != null && note.trim().isNotEmpty) 'note': note.trim()};
    final fp = IdempotencyIntentStore.fingerprint('cashDecide:$id', payload);
    final r = await _cashWrite('cashDecide', '${_cash(storeId, 'expenses')}/$id/decision', payload, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (
      success: r.success,
      message: r.message,
      code: r.code,
      expense: r.data?['expense'] is Map ? Expense.fromJson((r.data!['expense'] as Map).cast<String, dynamic>(), fallbackCur: InvCur.fromJson(r.data!)) : null,
    );
  }

  /// G5.1: a receipt photo on a CASH MOVEMENT (by its requestId); same rules as an expense photo.
  Future<({bool success, String? message, String? code, bool retryable})> uploadCashMovementReceipt(String storeId, String requestId, File file) async {
    lastErrorCode = null;
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last)});
      final res = await _client.post('${_cash(storeId, 'movements')}/${Uri.encodeComponent(requestId)}/receipt', data: form, requiresAuth: true, headers: await _employeeAuthHeaders());
      return (success: _ok(res), message: null, code: null, retryable: false);
    } on DioException catch (e) {
      _logDioError('cashMovementReceiptUpload', e);
      lastErrorCode = _dioCode(e);
      return (success: false, message: _dioMessage(e), code: lastErrorCode, retryable: !_isFinalFailure(e));
    } catch (e) {
      debugPrint('❌ cashMovementReceiptUpload: $e');
      return (success: false, message: 'Could not upload the photo.', code: null, retryable: true);
    }
  }

  /// G5.1: a 5-minute link to a cash movement's receipt photo.
  Future<ReceiptLink?> getCashMovementReceiptLink(String storeId, String requestId) => _invGet('cashMovementReceiptLink', '${_cash(storeId, 'movements')}/${Uri.encodeComponent(requestId)}/receipt', ReceiptLink.fromJson);

  /// Uploads the receipt photo of an expense (multipart field `file`; the server checks the real file type, max 5 MB by default).
  Future<({bool success, String? message, String? code, bool retryable})> uploadExpenseReceipt(String storeId, String id, File file, {String? employeeToken}) async {
    lastErrorCode = null;
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last)});
      final headers = {...await _employeeAuthHeaders(), if (employeeToken != null) 'x-pos-employee-token': employeeToken};
      final res = await _client.post('${_cash(storeId, 'expenses')}/$id/receipt', data: form, requiresAuth: true, headers: headers);
      return (success: _ok(res), message: null, code: null, retryable: false);
    } on DioException catch (e) {
      _logDioError('cashReceiptUpload', e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      return (success: false, message: _dioMessage(e), code: lastErrorCode, retryable: !_isFinalFailure(e));
    } catch (e) {
      debugPrint('❌ cashReceiptUpload: $e');
      return (success: false, message: 'Could not upload the photo.', code: null, retryable: true);
    }
  }

  // ── G3.6 team: attendance, corrections, anomalies, roster, report ───────────────────────────────────────────────────────────────
  // Reads return null on failure ([lastErrorCode] = the server's code; null = no connection). Writes return a record that also says whether the
  // failure may be retried (`retryable`) and carries the rest of the error body in `extra` (a roster overlap names the shift it clashes with).

  String _team(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/team/$path/$storeId';

  Future<({bool success, String? message, String? code, bool retryable, Map<String, dynamic>? data, Map<String, dynamic>? extra})> _teamWrite(
    String tag,
    String method,
    String url,
    Map<String, dynamic> payload, {
    required String idempotencyKey,
    String? employeeToken,
    String? approverToken,
  }) async {
    lastErrorCode = null;
    lastErrorReasons = const [];
    try {
      final headers = {...await _writeHeaders(idempotencyKey), if (employeeToken != null) 'x-pos-employee-token': employeeToken, if (approverToken != null) 'x-pos-approver-token': approverToken};
      final res = method == 'PATCH' ? await _client.patch(url, data: payload, requiresAuth: true, headers: headers) : await _client.post(url, data: payload, requiresAuth: true, headers: headers);
      final data = _data(res);
      return (success: _ok(res), message: res.data is Map ? res.data['message'] as String? : null, code: null, retryable: false, data: data is Map ? data.cast<String, dynamic>() : null, extra: null);
    } on DioException catch (e) {
      _logDioError(tag, e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      final body = e.response?.data;
      return (success: false, message: _dioMessage(e), code: lastErrorCode, retryable: !_isFinalFailure(e), data: null, extra: body is Map ? body.cast<String, dynamic>() : null);
    } catch (e) {
      debugPrint('❌ $tag: $e');
      return (success: false, message: 'Could not reach the server.', code: null, retryable: true, data: null, extra: null);
    }
  }

  /// G5.1: the team list a REGISTERED TILL can read (device + PIN session) — the owner-session [getEmployees] is refused there. Null on failure.
  Future<List<PosEmployeeModel>?> getTeamMembers(String storeId) => _invGet<List<PosEmployeeModel>>(
    'teamMembers',
    '${ApiConstants.apiPrefix}/pos/team/members/$storeId',
    (d) => [
      for (final m in (d['members'] as List? ?? const []))
        if (m is Map) PosEmployeeModel(id: '${m['id'] ?? ''}', storeId: storeId, sellerId: '', name: m['name'] as String? ?? '', email: m['email'] as String? ?? '', role: m['role'] as String? ?? 'cashier', shiftIds: const [], status: m['status'] as String? ?? 'active', createdAt: DateTime.fromMillisecondsSinceEpoch(0)),
    ],
  );

  /// G5.1: a team member's profile (managers: anyone; a cashier: themself).
  Future<StaffProfile?> getStaffProfile(String storeId, String employeeId) => _invGet('teamProfile', '${ApiConstants.apiPrefix}/pos/team/profile/$storeId/$employeeId', StaffProfile.fromJson);

  /// The signed-in person: are they clocked in / on a break, their next rostered shifts and the server's time.
  Future<TeamMe?> getTeamMe(String storeId) => _invGet('teamMe', _team(storeId, 'me'), TeamMe.fromJson);

  /// clock_in | clock_out | break_start | break_end for the PIN-signed-in person. [deviceAt] is the till's time at the tap (an offline event keeps it);
  /// [requestId] makes a retry or replay a no-op (`duplicate: true` is success). [employeeToken] replays a queued event as the person who made it.
  Future<({bool success, String? message, String? code, bool retryable, ClockResult? result})> teamClock(
    String storeId, {
    required String action,
    required String requestId,
    required DateTime deviceAt,
    String? note,
    String? employeeToken,
    String? onBehalfOf, // G5.4: another team member's id — needs [approverToken] = their PIN session or a manager's
    String? approverToken,
  }) async {
    final r = await _teamWrite('teamClock', 'POST', _team(storeId, 'clock'), {
      'action': action,
      'requestId': requestId,
      'deviceAt': deviceAt.toUtc().toIso8601String(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'employeeId': ?onBehalfOf,
    }, idempotencyKey: 'clk-$requestId', employeeToken: employeeToken, approverToken: approverToken);
    return (success: r.success, message: r.message, code: r.code, retryable: r.retryable, result: r.data == null ? null : ClockResult.fromJson(r.data!));
  }

  /// A cashier gets only their own records (the server enforces); a manager may pass [employeeId]. [from] inclusive, [to] exclusive.
  Future<List<AttendanceRecord>?> getAttendanceRecords(String storeId, {required DateTime from, required DateTime to, String? employeeId}) => _invGet(
    'teamRecords',
    _team(storeId, 'records'),
    (d) => [for (final e in (d['records'] as List? ?? const [])) if (e is Map) AttendanceRecord.fromJson(e.cast<String, dynamic>())],
    query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), if (employeeId != null) 'employeeId': employeeId},
  );

  /// One record with its raw punches and correction history. A cashier may open their own; the server enforces who may open whose.
  Future<AttendanceRecordDetail?> getAttendanceRecordDetail(String storeId, {required String employeeId, required String recordId}) =>
      _invGet('teamRecordDetail', '${_team(storeId, 'records')}/$employeeId/$recordId', AttendanceRecordDetail.fromJson);

  /// Managers only.
  Future<List<AttendanceAnomaly>?> getAttendanceAnomalies(String storeId) =>
      _invGet('teamAnomalies', _team(storeId, 'anomalies'), (d) => [for (final e in (d['anomalies'] as List? ?? const [])) if (e is Map) AttendanceAnomaly.fromJson(e.cast<String, dynamic>())]);

  /// Managers only: "seen, no action needed".
  Future<({bool success, String? message, String? code})> ackAttendanceAnomaly(String storeId, {required String employeeId, required String eventId, required String kind, String? note}) async {
    final payload = {'employeeId': employeeId, 'eventId': eventId, 'kind': kind, if (note != null && note.trim().isNotEmpty) 'note': note.trim()};
    final fp = IdempotencyIntentStore.fingerprint('teamAck:$eventId:$kind', payload);
    final r = await _teamWrite('teamAck', 'POST', '${_team(storeId, 'anomalies')}/ack', payload, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (success: r.success, message: r.message, code: r.code);
  }

  /// Managers only: a NEW correction on a record (set the times, add a missing clock-out, or void it). A reason is required; the raw punches stay.
  Future<({bool success, String? message, String? code, AttendanceRecord? record})> correctAttendance(
    String storeId, {
    required String employeeId,
    required String recordId,
    required String reason,
    DateTime? clockInAt,
    DateTime? clockOutAt,
    bool voided = false,
  }) async {
    final payload = {
      'employeeId': employeeId,
      'recordId': recordId,
      'reason': reason.trim(),
      if (clockInAt != null) 'clockInAt': clockInAt.toUtc().toIso8601String(),
      if (clockOutAt != null) 'clockOutAt': clockOutAt.toUtc().toIso8601String(),
      if (voided) 'voided': true,
    };
    final fp = IdempotencyIntentStore.fingerprint('teamCorrect:$recordId', payload);
    final r = await _teamWrite('teamCorrect', 'POST', _team(storeId, 'corrections'), payload, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (success: r.success, message: r.message, code: r.code, record: r.data?['record'] is Map ? AttendanceRecord.fromJson((r.data!['record'] as Map).cast<String, dynamic>()) : null);
  }

  /// Shifts that START in [from, to). Everyone may read.
  Future<List<RosterShift>?> getRoster(String storeId, {required DateTime from, required DateTime to, String? employeeId}) => _invGet(
    'teamRoster',
    _team(storeId, 'roster'),
    (d) => [for (final e in (d['shifts'] as List? ?? const [])) if (e is Map) RosterShift.fromJson(e.cast<String, dynamic>())],
    query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), if (employeeId != null) 'employeeId': employeeId},
  );

  RosterShift? _shiftOf(Map<String, dynamic>? d) => d?['shift'] is Map ? RosterShift.fromJson((d!['shift'] as Map).cast<String, dynamic>()) : null;

  /// Managers only. ROSTER_OVERLAP / SHIFT_TOO_LONG come back as the code; `extra` names the clashing shift; the saved shift carries `warnings`.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? extra, RosterShift? shift})> createRosterShift(
    String storeId, {
    required String employeeId,
    required DateTime startAt,
    required DateTime endAt,
    String? locationId,
    String? note,
  }) async {
    final payload = {'employeeId': employeeId, 'startAt': startAt.toUtc().toIso8601String(), 'endAt': endAt.toUtc().toIso8601String(), if (locationId != null) 'locationId': locationId, if (note != null && note.trim().isNotEmpty) 'note': note.trim()};
    final fp = IdempotencyIntentStore.fingerprint('rosterCreate', payload);
    final r = await _teamWrite('rosterCreate', 'POST', _team(storeId, 'roster'), payload, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (success: r.success, message: r.message, code: r.code, extra: r.extra, shift: _shiftOf(r.data));
  }

  /// Managers only: change any of person / times / location / note of a shift.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? extra, RosterShift? shift})> updateRosterShift(
    String storeId,
    String shiftId, {
    String? employeeId,
    DateTime? startAt,
    DateTime? endAt,
    String? locationId,
    String? note,
  }) async {
    final payload = {
      if (employeeId != null) 'employeeId': employeeId,
      if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
      if (endAt != null) 'endAt': endAt.toUtc().toIso8601String(),
      if (locationId != null) 'locationId': locationId,
      if (note != null) 'note': note.trim(),
    };
    final fp = IdempotencyIntentStore.fingerprint('rosterUpdate:$shiftId', payload);
    final r = await _teamWrite('rosterUpdate', 'PATCH', '${_team(storeId, 'roster')}/$shiftId', payload, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (success: r.success, message: r.message, code: r.code, extra: r.extra, shift: _shiftOf(r.data));
  }

  /// Managers only.
  Future<({bool success, String? message, String? code})> cancelRosterShift(String storeId, String shiftId) async {
    final fp = IdempotencyIntentStore.fingerprint('rosterCancel:$shiftId', const {});
    final r = await _teamWrite('rosterCancel', 'POST', '${_team(storeId, 'roster')}/$shiftId/cancel', const {}, idempotencyKey: await _intents.keyFor(fp));
    if (!r.retryable) await _intents.release(fp);
    return (success: r.success, message: r.message, code: r.code);
  }

  /// Hours, days, breaks, late arrivals (vs the roster, with the server's grace), missing clock-outs and corrections per person. A cashier gets only
  /// themself. [tzOffsetMinutes] is the device's offset in the JavaScript convention (minutes BEHIND UTC: UTC+5 is -300), used to count days.
  Future<TeamReport?> getTeamReport(String storeId, {required DateTime from, required DateTime to, String? employeeId, int tzOffsetMinutes = 0}) => _invGet(
    'teamReport',
    _team(storeId, 'report'),
    TeamReport.fromJson,
    // G4.0: the server counts days in the STORE's time zone now; [tzOffsetMinutes] is accepted for compatibility and no longer sent
    query: {'from': from.toUtc().toIso8601String(), 'to': to.toUtc().toIso8601String(), if (employeeId != null) 'employeeId': employeeId},
  );

  // ── G4.0 / G4.1 · business pulse, reports, store time zone ──────────────────────────────────────────────────────────────────────────────────
  String _reports(String kind, String storeId) => '${ApiConstants.apiPrefix}/pos/reports/$kind/$storeId';

  /// Today so far vs the same weekday last week (managers / owner; a cashier is refused). [date] is a STORE day (`YYYY-MM-DD`), today when null.
  Future<BusinessPulse?> getBusinessPulse(String storeId, {String? date}) => _invGet('reportPulse', _reports('pulse', storeId), BusinessPulse.fromJson, query: {if (date != null) 'date': date});

  /// One of the eight reports for store days [ReportQuery.from] … [ReportQuery.to] (inclusive). Products also take a [sort] (`net` | `qty` | `margin`) and a [limit].
  Future<BizReport?> getBizReport(String storeId, ReportKind kind, ReportQuery q, {String? sort, int? limit}) => _invGet(
    'report_${kind.path}',
    _reports(kind.path, storeId),
    (d) => parseBizReport(kind, d),
    query: {...q.toQuery(), if (sort != null) 'sort': sort, if (limit != null) 'limit': limit},
  );

  /// The store's time zone and today's store date. Anyone signed in may read it.
  Future<StoreTimeZone?> getStoreTimeZone(String storeId) => _invGet('storeTimeZone', '${ApiConstants.apiPrefix}/pos/store/time-zone/$storeId', StoreTimeZone.fromJson);

  /// Owner only (the server refuses everyone else with POS_ACTION_FORBIDDEN; a junk zone is INVALID_TIME_ZONE).
  Future<({bool success, String? message, String? code, StoreTimeZone? zone})> setStoreTimeZone(String storeId, String timeZone) async {
    final r = await _teamWrite('setStoreTimeZone', 'PATCH', '${ApiConstants.apiPrefix}/pos/store/time-zone/$storeId', {'timeZone': timeZone}, idempotencyKey: 'tz-${DateTime.now().microsecondsSinceEpoch}');
    return (success: r.success, message: r.message, code: r.code, zone: r.data == null ? null : StoreTimeZone.fromJson(r.data!));
  }

  // ── G4.1 follow-up · the sales of one STORE day (a report's day drills down here) ─────────────────────────────────────────────────────────
  /// Null on failure (with the server's code in [lastErrorCode]) — unlike [getSales], nothing is toasted, so the screen shows its own error.
  Future<PagedResult<PosSaleModel>?> getSalesForDay(String storeId, String date, {int page = 1}) async {
    lastErrorCode = null;
    try {
      final res = await _client.get(ApiConstants.posSales, queryParameters: {'storeId': storeId, 'date': date, 'page': page}, requiresAuth: true, headers: await _employeeAuthHeaders());
      if (!_ok(res)) return null;
      final data = _data(res);
      return data is Map ? _page(data.cast<String, dynamic>(), 'sales', PosSaleModel.fromJson) : null;
    } on DioException catch (e) {
      _logDioError('getSalesForDay', e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      return null;
    } catch (e) {
      debugPrint('❌ getSalesForDay: $e');
      return null;
    }
  }

  /// G4.3: one page of the activity log with the screen's filters (store days). Null on failure (code in [lastErrorCode]); nothing is toasted.
  Future<PagedResult<PosAuditLogModel>?> getAuditLogsFiltered(String storeId, {int page = 1, int limit = 30, String? employeeId, String? targetType, String? from, String? to}) async {
    lastErrorCode = null;
    try {
      final res = await _client.get(
        ApiConstants.posAuditLogs(storeId),
        queryParameters: {'page': page, 'limit': limit, 'employeeId': ?employeeId, 'targetType': ?targetType, 'from': ?from, 'to': ?to},
        requiresAuth: true,
        headers: await _employeeAuthHeaders(), // G4.8: a manager-PIN route on a till (RequireManagerPin)
      );
      if (!_ok(res)) return null;
      final data = _data(res);
      return data is Map ? _page(data.cast<String, dynamic>(), 'logs', PosAuditLogModel.fromJson) : null;
    } on DioException catch (e) {
      _logDioError('getAuditLogsFiltered', e);
      lastErrorCode = _dioCode(e);
      return null;
    } catch (e) {
      debugPrint('❌ getAuditLogsFiltered: $e');
      return null;
    }
  }

  // ── G4.2 – G4.4 · permissions, audit seals, store settings ──────────────────────────────────────────────────────────────────────────────────
  /// One owner / manager write: PUT / POST / PATCH with the employee token and an Idempotency-Key. `extra` = the error body.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data, Map<String, dynamic>? extra})> _adminWrite(String tag, String verb, String url, Map<String, dynamic> payload) async {
    lastErrorCode = null;
    try {
      final headers = await _writeHeaders('$tag-${DateTime.now().microsecondsSinceEpoch}');
      final res = switch (verb) {
        'PUT' => await _client.put(url, data: payload, requiresAuth: true, headers: headers),
        'PATCH' => await _client.patch(url, data: payload, requiresAuth: true, headers: headers),
        _ => await _client.post(url, data: payload, requiresAuth: true, headers: headers),
      };
      final data = _data(res);
      return (success: _ok(res), message: res.data is Map ? res.data['message'] as String? : null, code: null, data: data is Map ? data.cast<String, dynamic>() : null, extra: null);
    } on DioException catch (e) {
      _logDioError(tag, e);
      _noteEntitlement(e);
      lastErrorCode = _dioCode(e);
      final body = e.response?.data;
      return (success: false, message: _dioMessage(e), code: lastErrorCode, data: null, extra: body is Map ? body.cast<String, dynamic>() : null);
    } catch (e) {
      debugPrint('❌ $tag: $e');
      return (success: false, message: 'Could not reach the server.', code: null, data: null, extra: null);
    }
  }

  String _perms(String storeId) => '${ApiConstants.apiPrefix}/pos/permissions/$storeId';

  /// The store's permission matrix (managers read it; `canEdit` is true for the owner; a cashier is refused).
  Future<PermissionMatrix?> getPermissionMatrix(String storeId) => _invGet('permissions', _perms(storeId), PermissionMatrix.fromJson);

  /// Owner only. [changes] = `{action: {roles?, approval?}}`. With [preview] the server only returns the diff; otherwise it saves when the version
  /// still is [expectedVersion] (else VERSION_CONFLICT) and returns the new matrix.
  Future<({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff})> updatePermissions(
    String storeId,
    Map<String, dynamic> changes, {
    bool preview = false,
    int? expectedVersion,
  }) async {
    final r = await _adminWrite('permissionsUpdate', 'PUT', _perms(storeId), {'changes': changes, if (preview) 'preview': true, 'expectedVersion': ?expectedVersion});
    return _permResult(r, preview);
  }

  /// Owner only: back to the documented defaults ([preview] = the diff only).
  Future<({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff})> resetPermissions(String storeId, {bool preview = false}) async {
    final r = await _adminWrite('permissionsReset', 'POST', '${_perms(storeId)}/reset', {if (preview) 'preview': true});
    return _permResult(r, preview);
  }

  /// G5.6 owner only: apply a role preset ([preview] = the diff only; otherwise saved when the version still is [expectedVersion]).
  Future<({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff})> applyRolePreset(String storeId, String preset, {bool preview = false, int? expectedVersion}) async {
    final r = await _adminWrite('permissionsPreset', 'POST', '${_perms(storeId)}/preset', {'preset': preset, if (preview) 'preview': true, 'expectedVersion': ?expectedVersion});
    return _permResult(r, preview);
  }

  ({bool success, String? code, String? message, PermissionMatrix? matrix, List<PermDiff> diff}) _permResult(
    ({bool success, String? message, String? code, Map<String, dynamic>? data, Map<String, dynamic>? extra}) r,
    bool preview,
  ) {
    final d = r.data;
    final diff = d != null && d['diff'] is List ? [for (final x in d['diff'] as List) if (x is Map) PermDiff.fromJson(x.cast<String, dynamic>())] : <PermDiff>[];
    return (success: r.success, code: r.code, message: r.message, matrix: d != null && !preview && d['actions'] is List ? PermissionMatrix.fromJson(d) : null, diff: diff);
  }

  /// G4.3: recompute every sealed store day in [from] … [to] (store days) and compare (managers / owner; the check itself is audited).
  Future<AuditVerify?> verifyAuditSeals(String storeId, {String? from, String? to}) =>
      _invGet('auditVerify', '${ApiConstants.apiPrefix}/pos/audit/verify/$storeId', AuditVerify.fromJson, query: {'from': ?from, 'to': ?to});

  /// G4.4: receipt designer, in-app alerts, security, profile (managers read; `canEdit` for the owner).
  Future<StoreSettings?> getStoreSettings(String storeId) => _invGet('storeSettings', '${ApiConstants.apiPrefix}/pos/store/settings/$storeId', StoreSettings.fromJson);

  /// Owner only. [patch] = `{receipt?: {...}, alerts?: {...}, security?: {...}}` — only the keys that change.
  Future<({bool success, String? code, String? message, StoreSettings? settings})> updateStoreSettings(String storeId, Map<String, dynamic> patch) async {
    final r = await _adminWrite('storeSettingsUpdate', 'PATCH', '${ApiConstants.apiPrefix}/pos/store/settings/$storeId', patch);
    return (success: r.success, code: r.code, message: r.extra?['message'] as String? ?? r.message, settings: r.data == null ? null : StoreSettings.fromJson(r.data!));
  }

  /// G5.6: the receipt logo (owner only). The server checks the file by content and resizes it; tills make the printable bitmap.
  Future<({bool success, String? code, String? message, StoreSettings? settings})> uploadReceiptLogo(String storeId, File file) async {
    lastErrorCode = null;
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last)});
      final res = await _client.post('${ApiConstants.apiPrefix}/pos/store/settings/$storeId/receipt-logo', data: form, requiresAuth: true, headers: await _employeeAuthHeaders());
      final d = _data(res);
      return (success: _ok(res) && d is Map, code: null, message: null, settings: d is Map ? StoreSettings.fromJson(d.cast<String, dynamic>()) : null);
    } on DioException catch (e) {
      _logDioError('receiptLogoUpload', e);
      lastErrorCode = _dioCode(e);
      return (success: false, code: lastErrorCode, message: _dioMessage(e), settings: null);
    }
  }

  Future<({bool success, String? code, String? message, StoreSettings? settings})> removeReceiptLogo(String storeId) async {
    final r = await _adminWrite('receiptLogoRemove', 'POST', '${ApiConstants.apiPrefix}/pos/store/settings/$storeId/receipt-logo/remove', const {});
    return (success: r.success, code: r.code, message: r.extra?['message'] as String? ?? r.message, settings: r.data == null ? null : StoreSettings.fromJson(r.data!));
  }

  /// G4.4: the server's time, devices with when each was last seen, the latest audit seal.
  Future<SyncStatus?> getSyncStatus(String storeId) => _invGet('syncStatus', '${ApiConstants.apiPrefix}/pos/store/sync-status/$storeId', SyncStatus.fromJson);

  /// G4.6: what the register's last closed shift left behind (counted, expected, variance, who) — null when it was never closed or on failure.
  Future<LastClose?> getLastClose(String storeId, String registerId) =>
      _invGet<LastClose?>('lastClose', '${ApiConstants.apiPrefix}/pos/sessions/last-close', LastClose.fromJson, query: {'storeId': storeId, 'registerId': registerId});

  // ── G4.8 · reprints ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  /// Records a reprint ([documentType]: sale | invoice | credit_note). With "require PIN to reprint" a cashier's call needs [approverToken] (a manager's
  /// PIN token) — `POS_APPROVAL_REQUIRED` otherwise. Returns the reprint number the print shows ("REPRINT #n").
  /// G4.9: [kind] (original | reprint) is what the till expects to print; the answer's `kind` is what the server recorded — print THAT.
  Future<({bool success, String? code, String? message, int? reprintNumber, String? kind})> recordReprint(String storeId, {required String documentType, required String documentId, String? reason, String? approverToken, String? kind}) async {
    final r = await _supplyWrite('reprint', 'POST', '${ApiConstants.apiPrefix}/pos/reprints/$storeId', {'documentType': documentType, 'documentId': documentId, 'reason': ?reason, 'kind': ?kind}, approverToken: approverToken);
    final n = r.data?['reprintNumber'];
    return (success: r.success, code: r.code, message: r.message, reprintNumber: n is num ? n.toInt() : null, kind: r.data?['kind'] as String?);
  }

  // ── G4.6 · transfers, expiry + write-off, low stock → draft PO ───────────────────────────────────────────────────────────────────────────
  /// [status]: all | in_transit | partially_received | received | cancelled (newest first, 200 at most).
  Future<List<StockTransfer>?> getTransfers(String storeId, {String status = 'all'}) =>
      _invGet('transfers', _inv(storeId, 'transfers'), StockTransfer.listFrom, query: {'status': status}, dataIsList: true);

  /// Ships [quantity] of a variant from one location to another (it leaves the first now, arrives when received). Matrix: inventory.transfer.create.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> shipTransfer(String storeId, {required String variantId, required String fromLocationId, required String toLocationId, required int quantity, String? note}) =>
      _supplyWrite('transferShip', 'POST', _inv(storeId, 'transfers'), {
        'variantId': variantId,
        'fromLocationId': fromLocationId,
        'toLocationId': toLocationId,
        'quantity': quantity,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// Receives (part of) a transfer at its destination. Matrix: inventory.transfer.receive.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> receiveTransfer(String storeId, String transferId, int receivedQty) =>
      _supplyWrite('transferReceive', 'POST', '${_inv(storeId, 'transfers')}/$transferId/receive', {'receivedQty': receivedQty});

  /// Cancels a transfer nothing of which has arrived (the stock goes back to where it left).
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> cancelTransfer(String storeId, String transferId) =>
      _supplyWrite('transferCancel', 'POST', '${_inv(storeId, 'transfers')}/$transferId/cancel', const {});

  /// Lots by how soon they expire (store time zone).
  Future<ExpiryBuckets?> getExpiry(String storeId) => _invGet('expiry', _inv(storeId, 'expiry'), ExpiryBuckets.fromJson);

  /// Writes off (part of) a lot — [quantity] null = all that is left; [reason]: expired | damaged. Matrix: inventory.writeoff.
  Future<({bool success, String? message, String? code, Map<String, dynamic>? data})> writeOffLot(String storeId, String lotId, {int? quantity, String reason = 'expired', String? note}) =>
      _supplyWrite('lotWriteOff', 'POST', '${_inv(storeId, 'lots')}/$lotId/write-off', {
        'quantity': ?quantity,
        'reason': reason,
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      });

  /// A DRAFT purchase order from the store's low-stock suggestions for one supplier (or only [variantIds]); nothing is approved or sent.
  Future<({bool success, String? message, String? code, PurchaseOrder? order})> draftPoFromLowStock(String storeId, String supplierId, {List<String>? variantIds}) async {
    final r = await _supplyWrite('poFromLowStock', 'POST', '${_sup(storeId, 'orders')}/from-low-stock', {'supplierId': supplierId, if (variantIds != null && variantIds.isNotEmpty) 'variantIds': variantIds});
    return (success: r.success, message: r.message, code: r.code, order: _poOf(r.data));
  }

  // ── G5.3 · receipts out of the app ─────────────────────────────────────────────────────────────────────────────────────────────────────
  /// Which delivery channels the store has switched on (each is off until the admin / owner turns it on). Null on failure.
  Future<({bool email, bool sms})?> getReceiptChannels(String storeId) =>
      _invGet('receiptChannels', '${ApiConstants.apiPrefix}/pos/receipt-delivery/$storeId', (d) => (email: d['email'] == true, sms: d['sms'] == true));

  /// Sends the receipt's public link (store name + total + link only). [to] omitted = the contact on the customer's record; another contact needs
  /// [givenForSale] (the customer gave it for this receipt).
  Future<({bool success, String? code, String? message})> sendReceipt(String storeId, String saleId, {required String channel, String? to, bool givenForSale = false}) async {
    final r = await _adminWrite('receiptSend', 'POST', '${ApiConstants.apiPrefix}/pos/receipt-delivery/$storeId/$saleId', {'channel': channel, if (to != null && to.trim().isNotEmpty) 'to': to.trim(), if (givenForSale) 'consent': 'given_for_sale'});
    return (success: r.success, code: r.code, message: (r.extra?['message'] is String ? r.extra!['message'] as String : null) ?? r.message);
  }

  /// G5.4 / G5.7: the store's provider-dependent switches + provider status (read-only; switches change via store settings `connectors`, owner only).
  Future<ConnectorsStatus?> getConnectors(String storeId) =>
      _invGet('connectors', '${ApiConstants.apiPrefix}/pos/connectors/$storeId', (d) => ConnectorsStatus.fromJson(d as Map));

  /// Owner: flips one or more connector switches (audited server-side).
  Future<({bool success, String? code, String? message})> setConnectors(String storeId, Map<String, bool> patch) async {
    final r = await updateStoreSettings(storeId, {'connectors': patch});
    return (success: r.success, code: r.code, message: r.message);
  }

  // ── G5.2 · the product page and editing an existing product ─────────────────────────────────────────────────────────────────────────
  String _prod(String storeId, String productId) => '${ApiConstants.apiPrefix}/pos/catalog-admin/products/$storeId/$productId';

  Future<ProductPage?> getProductPage(String storeId, String productId) => _invGet('productPage', _prod(storeId, productId), ProductPage.fromJson);

  /// [body]: name, description, categoryId, status (only what changes).
  Future<({bool success, String? code, String? message, ProductPage? data})> updateProductDetails(String storeId, String productId, Map<String, dynamic> body) async =>
      _catResult(await _adminWrite('productUpdate', 'PATCH', _prod(storeId, productId), body), ProductPage.fromJson);

  /// [body]: sku, costMinor (int or null), reorderPoint (int or null).
  Future<({bool success, String? code, String? message, ProductPage? data})> updateProductVariant(String storeId, String productId, String variantId, Map<String, dynamic> body) async =>
      _catResult(await _adminWrite('productVariantUpdate', 'PATCH', '${_prod(storeId, productId)}/variants/$variantId', body), ProductPage.fromJson);

  Future<({bool success, String? code, String? message, ProductPage? data})> removeProductImage(String storeId, String productId, String url) async =>
      _catResult(await _adminWrite('productImageRemove', 'POST', '${_prod(storeId, productId)}/images/remove', {'url': url}), ProductPage.fromJson);

  Future<({bool success, String? code, String? message, ProductPage? data})> makeProductImagePrimary(String storeId, String productId, String url) async =>
      _catResult(await _adminWrite('productImagePrimary', 'POST', '${_prod(storeId, productId)}/images/primary', {'url': url}), ProductPage.fromJson);

  /// A product photo (multipart `file`; JPEG / PNG / WebP checked by content on the server, ≤ 8 MB; stored resized).
  Future<({bool success, String? code, String? message, ProductPage? data})> uploadProductImage(String storeId, String productId, File file) async {
    lastErrorCode = null;
    try {
      final form = FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last)});
      final res = await _client.post('${_prod(storeId, productId)}/images', data: form, requiresAuth: true, headers: await _employeeAuthHeaders());
      final d = _data(res);
      return (success: _ok(res) && d is Map, code: null, message: null, data: d is Map ? ProductPage.fromJson(d.cast<String, dynamic>()) : null);
    } on DioException catch (e) {
      _logDioError('productImageUpload', e);
      lastErrorCode = _dioCode(e);
      return (success: false, code: lastErrorCode, message: _dioMessage(e), data: null);
    } catch (e) {
      debugPrint('❌ productImageUpload: $e');
      return (success: false, code: null, message: 'Could not upload the photo.', data: null);
    }
  }

  // ── G4.5 · products & pricing (catalog-admin) ──────────────────────────────────────────────────────────────────────────────────────────
  String _cat(String storeId, String path) => '${ApiConstants.apiPrefix}/pos/catalog-admin/$path/$storeId';

  /// A write's outcome: the parsed data, or the server's code and words.
  ({bool success, String? code, String? message, T? data}) _catResult<T>(({bool success, String? message, String? code, Map<String, dynamic>? data, Map<String, dynamic>? extra}) r, T Function(Map<String, dynamic>) parse) =>
      (success: r.success && r.data != null, code: r.code, message: (r.extra?['message'] is String ? r.extra!['message'] as String : null) ?? r.message, data: r.success && r.data != null ? parse(r.data!) : null);

  /// The modifier groups the till sells with (active only, unless [all] for the editor).
  Future<ModifierGroups?> getModifierGroups(String storeId, {bool all = false}) => _invGet('modifierGroups', _cat(storeId, 'modifiers'), ModifierGroups.fromJson, query: {if (all) 'all': 'true'});

  Future<({bool success, String? code, String? message, ModifierGroup? data})> saveModifierGroup(String storeId, ModifierGroup g) async {
    final r = g.id.isEmpty
        ? await _adminWrite('modifierCreate', 'POST', _cat(storeId, 'modifiers'), g.toWrite())
        : await _adminWrite('modifierUpdate', 'PATCH', '${_cat(storeId, 'modifiers')}/${g.id}', g.toWrite());
    return _catResult(r, (d) => ModifierGroup.fromJson((d['group'] as Map).cast<String, dynamic>()));
  }

  Future<PriceBooks?> getPriceBooks(String storeId) => _invGet('priceBooks', _cat(storeId, 'price-books'), PriceBooks.fromJson);

  /// [body] = name, active, startsAt, endsAt, note, entries [{variantId, priceMinor}] (only the keys that change on an update).
  Future<({bool success, String? code, String? message, PriceBook? data})> savePriceBook(String storeId, Map<String, dynamic> body, {String? id}) async {
    final r = id == null
        ? await _adminWrite('priceBookCreate', 'POST', _cat(storeId, 'price-books'), body)
        : await _adminWrite('priceBookUpdate', 'PATCH', '${_cat(storeId, 'price-books')}/$id', body);
    return _catResult(r, (d) => PriceBook.fromJson((d['book'] as Map).cast<String, dynamic>()));
  }

  /// Gives a customer a price book (null clears it).
  Future<({bool success, String? code, String? message, String? data})> assignPriceBook(String storeId, String customerId, String? priceBookId) async {
    final r = await _adminWrite('priceBookAssign', 'POST', '${_cat(storeId, 'price-books')}/customers/$customerId', {'priceBookId': priceBookId});
    return _catResult<String?>(r, (d) => d['priceBookId'] as String?);
  }

  Future<List<CatalogCategory>?> getCatalogCategories(String storeId) => _invGet('catalogCategories', _cat(storeId, 'categories'), CatalogCategory.listFrom);

  Future<({bool success, String? code, String? message, List<CatalogCategory>? data})> createCatalogCategory(String storeId, String name) async =>
      _catResult(await _adminWrite('categoryCreate', 'POST', _cat(storeId, 'categories'), {'name': name}), CatalogCategory.listFrom);

  Future<({bool success, String? code, String? message, List<CatalogCategory>? data})> updateCatalogCategory(String storeId, String id, {String? name, int? sortOrder}) async =>
      _catResult(await _adminWrite('categoryUpdate', 'PATCH', '${_cat(storeId, 'categories')}/$id', {'name': ?name, 'sortOrder': ?sortOrder}), CatalogCategory.listFrom);

  Future<({bool success, String? code, String? message, List<CatalogCategory>? data})> deleteCatalogCategory(String storeId, String id) async =>
      _catResult(await _adminWrite('categoryDelete', 'POST', '${_cat(storeId, 'categories')}/$id/delete', const {}), CatalogCategory.listFrom);

  /// [body] = name, categoryId?, description?, variants [{priceMinor, costMinor?, sku?, barcode?, stock?, options?, trackLots?, reorderPoint?}]
  Future<({bool success, String? code, String? message, CatalogProduct? data})> createCatalogProduct(String storeId, Map<String, dynamic> body) async =>
      _catResult(await _adminWrite('productCreate', 'POST', _cat(storeId, 'products'), body), CatalogProduct.fromJson);

  Future<({bool success, String? code, String? message, CatalogProduct? data})> addCatalogVariant(String storeId, String productId, Map<String, dynamic> body) async =>
      _catResult(await _adminWrite('variantAdd', 'POST', '${_cat(storeId, 'products')}/$productId/variants', body), CatalogProduct.fromJson);

  Future<({bool success, String? code, String? message, CatalogProduct? data})> archiveCatalogVariant(String storeId, String productId, String variantId) async =>
      _catResult(await _adminWrite('variantArchive', 'POST', '${_cat(storeId, 'products')}/$productId/variants/$variantId/archive', const {}), CatalogProduct.fromJson);

  /// CSV import of `products` or `categories` (the dashboard's importer: same columns, same report).
  Future<({bool success, String? code, String? message, ImportReport? data})> importCatalogCsv(String storeId, {required String kind, required String csv}) async =>
      _catResult(await _adminWrite('catalogImport', 'POST', _cat(storeId, 'import'), {'kind': kind, 'csv': csv}), ImportReport.fromJson);

  /// G4.0: the daybook of one STORE day (`YYYY-MM-DD` in the store's time zone).
  Future<Daybook?> getDaybookDay(String storeId, {required String date, String? registerId}) =>
      _invGet('cashDaybookDay', _cash(storeId, 'daybook'), Daybook.fromJson, query: {'date': date, if (registerId != null) 'registerId': registerId});
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

  /// G4.5: each line's unit price in the cart's order, and whether the server priced it with options or a price book (then it is not the list price)
  final List<({double price, bool priced})> lines;

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
    this.lines = const [],
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
        lines: [
          for (final l in (j['lines'] as List? ?? []))
            if (l is Map) (price: MoneyJson.read(l.cast<String, dynamic>(), 'price', exp: exp), priced: (l['modifiers'] is List && (l['modifiers'] as List).isNotEmpty) || l['basePriceMinor'] != null),
        ],
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
