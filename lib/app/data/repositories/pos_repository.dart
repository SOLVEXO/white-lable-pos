import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_audit_log_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'dart:io';

import 'package:solvexo_pos/app/data/local/pending_sale_local_store.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/network/base_client.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart' hide Response, FormData, MultipartFile;

typedef PagedResult<T> = ({List<T> items, int total, int totalPages, bool hasMore});

class PosRepository {
  PosRepository({BaseClient? client}) : _client = client ?? BaseClient();

  final BaseClient _client;

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
    try {
      final res = await _client.post(
        ApiConstants.posSessionsOpen,
        data: {
          'storeId': storeId,
          'registerId': registerId,
          'employeeId': employeeId,
          if (shiftId != null && shiftId.isNotEmpty) 'shiftId': shiftId,
          'openingCash': openingCash,
        },
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, session: PosSessionModel.fromJson(data), message: null);
      return (success: false, session: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('openSession', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, session: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ openSession: $e');
      return (success: false, session: null, message: null);
    }
  }

  Future<({bool success, PosSessionModel? session, String? message})> closeSession({
    required String sessionId,
    required double closingCash,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSessionsClose,
        data: {'sessionId': sessionId, 'closingCash': closingCash},
        requiresAuth: true,
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, session: PosSessionModel.fromJson(data), message: null);
      return (success: false, session: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('closeSession', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, session: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ closeSession: $e');
      return (success: false, session: null, message: null);
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
    try {
      final res = await _client.post(
        ApiConstants.posSessionCashAdjustment(sessionId),
        data: {'type': type, 'amount': amount, 'reason': reason, 'employeeId': employeeId},
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return data;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to record cash movement');
      return null;
    } on DioException catch (e) {
      _logDioError('cashAdjustment', e);
      DioExceptionHandler.handleDioException(e);
      return null;
    } catch (e) {
      debugPrint('❌ cashAdjustment: $e');
      ToastUtil.showToast('Failed to record cash movement.');
      return null;
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
    double? discount,
    double? tax,
    required String paymentMethod,
    String customerName = 'Walk-in',
    String? customerId,
    String? notes,
    required String status, // "completed" | "held"
    String? idempotencyKey,
  }) async {
    final payload = {
      'storeId': storeId,
      'sessionId': sessionId,
      'registerId': registerId,
      'employeeId': employeeId,
      'items': items,
      if (discount != null) 'discount': discount,
      if (tax != null) 'tax': tax,
      'paymentMethod': paymentMethod,
      'customerName': customerName,
      if (customerId != null) 'customerId': customerId,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'status': status,
      if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
    };
    try {
      final res = await _client.post(
        ApiConstants.posSales,
        data: payload,
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) {
        return (success: true, sale: PosSaleModel.fromJson(data), message: null, queued: false);
      }
      return (success: false, sale: null, message: res.data['message'] as String?, queued: false);
    } on DioException catch (e) {
      _logDioError('createSale', e);
      if (_isConnectivityError(e) && Get.isRegistered<PendingSaleSyncService>()) {
        // No route to the server at all — save it locally instead of losing
        // the sale, keyed by the same idempotencyKey the backend already
        // dedupes on, so the eventual sync can't double-record it.
        final queueId = idempotencyKey ?? '$employeeId-${DateTime.now().microsecondsSinceEpoch}';
        await Get.find<PendingSaleSyncService>().enqueue(queueId, payload);
        return (success: false, sale: null, message: null, queued: true);
      }
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, sale: null, message: _dioMessage(e), queued: false);
    } catch (e) {
      debugPrint('❌ createSale: $e');
      return (success: false, sale: null, message: null, queued: false);
    }
  }

  /// Resubmits a previously-queued sale payload as-is. Used only by
  /// [PendingSaleSyncService] once connectivity returns — see
  /// [PendingSaleLocalStore] for what's stored.
  Future<({bool success, bool connectivityError, String? message})> submitRawSale(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _client.post(
        ApiConstants.posSales,
        data: payload,
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      if (_ok(res)) return (success: true, connectivityError: false, message: null);
      return (success: false, connectivityError: false, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('submitRawSale', e);
      final connectivityError = _isConnectivityError(e);
      if (!connectivityError) DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, connectivityError: connectivityError, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ submitRawSale: $e');
      return (success: false, connectivityError: false, message: null);
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
    double? discount,
    double? tax,
    String? notes,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSaleComplete(saleId),
        data: {
          'paymentMethod': paymentMethod,
          if (discount != null) 'discount': discount,
          if (tax != null) 'tax': tax,
          if (notes != null) 'notes': notes,
        },
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      final data = _data(res) as Map<String, dynamic>?;
      if (data != null) return (success: true, sale: PosSaleModel.fromJson(data), message: null);
      return (success: false, sale: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('completeSale', e);
      DioExceptionHandler.handleDioException(e, showToast: false);
      return (success: false, sale: null, message: _dioMessage(e));
    } catch (e) {
      debugPrint('❌ completeSale: $e');
      return (success: false, sale: null, message: null);
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

  Future<bool> discardSale(String saleId) async {
    try {
      final res = await _client.delete(ApiConstants.posSaleDiscard(saleId), requiresAuth: true);
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
  Future<({bool success, double? refundedAmount, String? newStatus, String? message})> refundSale(
    String saleId, {
    List<Map<String, dynamic>>? items,
  }) async {
    try {
      final res = await _client.post(
        ApiConstants.posSaleRefund(saleId),
        data: {
          if (items != null && items.isNotEmpty) 'items': items,
        },
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      if (_ok(res)) {
        final data = res.data['data'] as Map<String, dynamic>?;
        return (
          success: true,
          refundedAmount: (data?['refundedAmount'] as num?)?.toDouble(),
          newStatus: data?['newStatus'] as String?,
          message: res.data['message'] as String?,
        );
      }
      return (success: false, refundedAmount: null, newStatus: null, message: res.data['message'] as String?);
    } on DioException catch (e) {
      _logDioError('refundSale', e);
      DioExceptionHandler.handleDioException(e);
      return (success: false, refundedAmount: null, newStatus: null, message: null);
    } catch (e) {
      debugPrint('❌ refundSale: $e');
      ToastUtil.showToast('Could not process refund.');
      return (success: false, refundedAmount: null, newStatus: null, message: null);
    }
  }

  /// Authorization comes from the current employee's signed token — see
  /// [refundSale]'s doc comment.
  Future<bool> voidSale(String saleId, {String? reason}) async {
    try {
      final res = await _client.post(
        ApiConstants.posSaleVoid(saleId),
        data: {
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
        requiresAuth: true,
        headers: await _employeeAuthHeaders(),
      );
      if (_ok(res)) return true;
      ToastUtil.showToast(res.data['message'] as String? ?? 'Failed to void sale');
      return false;
    } on DioException catch (e) {
      _logDioError('voidSale', e);
      DioExceptionHandler.handleDioException(e);
      return false;
    } catch (e) {
      debugPrint('❌ voidSale: $e');
      ToastUtil.showToast('Failed to void sale.');
      return false;
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
      return data != null ? PosSettingsModel.fromJson(data) : null;
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
}
