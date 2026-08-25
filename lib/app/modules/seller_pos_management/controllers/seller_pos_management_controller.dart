import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SellerPosManagementController extends GetxController {
  final _posRepo    = PosRepository();
  final _sellerRepo = SellerRepository();

  // ── Loading ───────────────────────────────────────────────────────────────
  final RxBool isLoading         = true.obs;
  final RxBool isSavingEmployee  = false.obs;
  final RxBool isSavingRegister  = false.obs;
  final RxBool isSavingShift     = false.obs;

  // ── Data ──────────────────────────────────────────────────────────────────
  final RxList<PosEmployeeModel>  employees       = <PosEmployeeModel>[].obs;
  final RxList<StoreRegister>     registers       = <StoreRegister>[].obs;
  final RxList<StoreShift>        shifts          = <StoreShift>[].obs;
  final RxList<PosSessionModel>   recentSessions  = <PosSessionModel>[].obs;
  final Rx<PosDailyReportModel?>  dailyReport     = Rx(null);

  // ── Processing states ─────────────────────────────────────────────────────
  final RxString deletingEmployeeId = ''.obs;
  final RxString processingRegisterId = ''.obs;
  final RxString processingShiftId = ''.obs;

  // ── Store context ─────────────────────────────────────────────────────────
  final RxString storeId   = ''.obs;
  final RxString storeName = ''.obs;

  // ── Add Employee form controllers ─────────────────────────────────────────
  final empNameCtrl  = TextEditingController();
  final empEmailCtrl = TextEditingController();
  final empPinCtrl   = TextEditingController();
  final RxString empRole    = 'cashier'.obs;
  final RxString empShiftId = ''.obs;

  // ── Add Register form ──────────────────────────────────────────────────────
  final regNameCtrl = TextEditingController();

  // ── Add Shift form ─────────────────────────────────────────────────────────
  final shiftNameCtrl  = TextEditingController();
  final shiftStartCtrl = TextEditingController();
  final shiftEndCtrl   = TextEditingController();

  // ── Computed ──────────────────────────────────────────────────────────────
  int get activeSessionCount =>
      recentSessions.where((s) => s.isOpen).length;

  @override
  void onInit() {
    super.onInit();
    _loadAll();
  }

  @override
  void onClose() {
    empNameCtrl.dispose();
    empEmailCtrl.dispose();
    empPinCtrl.dispose();
    regNameCtrl.dispose();
    shiftNameCtrl.dispose();
    shiftStartCtrl.dispose();
    shiftEndCtrl.dispose();
    super.onClose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    isLoading.value = true;
    try {
      final sid = await AppPreferences.getStoreId() ?? '';
      storeId.value = sid;
      if (sid.isEmpty) return;

      final results = await Future.wait([
        _posRepo.getEmployees(sid),
        _sellerRepo.getStoreById(sid),
        _posRepo.getSessionHistory(storeId: sid),
        _posRepo.getDailyReport(sid),
      ]);

      employees.assignAll(results[0] as List<PosEmployeeModel>);

      final store = results[1] as StoreModel?;
      if (store != null) {
        storeName.value = store.name;
        registers.assignAll(store.registers);
        shifts.assignAll(store.shifts);
        if (empShiftId.value.isEmpty && store.shifts.isNotEmpty) {
          empShiftId.value = store.shifts.first.id;
        }
      }

      recentSessions.assignAll((results[2] as PagedResult<PosSessionModel>).items);
      dailyReport.value = results[3] as PosDailyReportModel?;
    } catch (e) {
      CustomAppSnackbar.error('Failed to load POS data.');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> refreshData() => _loadAll();

  // ── Add Employee ──────────────────────────────────────────────────────────
  Future<void> addEmployee() async {
    final name  = empNameCtrl.text.trim();
    final email = empEmailCtrl.text.trim();
    final pin   = empPinCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || pin.isEmpty) {
      CustomAppSnackbar.warning('Fill in name, email and PIN.');
      return;
    }
    if (pin.length != 4 || int.tryParse(pin) == null) {
      CustomAppSnackbar.warning('PIN must be exactly 4 digits.');
      return;
    }

    isSavingEmployee.value = true;
    try {
      final emp = await _posRepo.createEmployee(
        storeId:  storeId.value,
        name:     name,
        email:    email,
        role:     empRole.value,
        pin:      pin,
        shiftIds: empShiftId.value.isNotEmpty ? [empShiftId.value] : [],
      );
      if (emp != null) {
        employees.add(emp);
        _clearEmpForm();
        Get.back();
        CustomAppSnackbar.success('Employee added successfully.');
      }
    } finally {
      isSavingEmployee.value = false;
    }
  }

  Future<void> updateEmployee(
    PosEmployeeModel emp, {
    String? name,
    String? role,
    List<String>? shiftIds,
  }) async {
    final updated = await _posRepo.updateEmployee(
      storeId: storeId.value,
      employeeId: emp.id,
      name: name,
      role: role,
      shiftIds: shiftIds,
    );
    if (updated == null) return;
    final idx = employees.indexWhere((e) => e.id == emp.id);
    if (idx >= 0) employees[idx] = updated;
    CustomAppSnackbar.success('Employee updated.');
  }

  Future<void> resetEmployeePin(PosEmployeeModel emp, String newPin) async {
    final ok = await _posRepo.resetEmployeePin(
      storeId: storeId.value,
      employeeId: emp.id,
      newPin: newPin,
    );
    if (ok) CustomAppSnackbar.success('PIN reset successfully.');
  }

  Future<void> deleteEmployee(PosEmployeeModel emp) async {
    deletingEmployeeId.value = emp.id;
    try {
      final ok = await _posRepo.deleteEmployee(storeId.value, emp.id);
      if (ok) {
        employees.remove(emp);
        CustomAppSnackbar.success('Employee removed.');
      }
    } finally {
      deletingEmployeeId.value = '';
    }
  }

  void _clearEmpForm() {
    empNameCtrl.clear();
    empEmailCtrl.clear();
    empPinCtrl.clear();
    empRole.value = 'cashier';
  }

  // ── Registers ────────────────────────────────────────────────────────────
  Future<void> addRegister() async {
    final name = regNameCtrl.text.trim();
    if (name.isEmpty) {
      CustomAppSnackbar.warning('Enter a register name.');
      return;
    }
    isSavingRegister.value = true;
    try {
      final ok = await _posRepo.createRegister(
          storeId: storeId.value, name: name);
      if (ok) {
        regNameCtrl.clear();
        Get.back();
        CustomAppSnackbar.success('Register added.');
        await _loadAll();
      }
    } finally {
      isSavingRegister.value = false;
    }
  }

  Future<void> updateRegister(StoreRegister reg, {String? name, String? status}) async {
    processingRegisterId.value = reg.id;
    try {
      final updated = await _posRepo.updateRegister(
        storeId: storeId.value,
        registerId: reg.id,
        name: name,
        status: status,
      );
      if (updated == null) return;
      final idx = registers.indexWhere((r) => r.id == reg.id);
      if (idx >= 0) registers[idx] = updated;
      CustomAppSnackbar.success('Register updated.');
    } finally {
      processingRegisterId.value = '';
    }
  }

  Future<void> deleteRegister(StoreRegister reg) async {
    processingRegisterId.value = reg.id;
    try {
      final ok = await _posRepo.deleteRegister(storeId.value, reg.id);
      if (ok) {
        registers.remove(reg);
        CustomAppSnackbar.success('Register removed.');
      }
    } finally {
      processingRegisterId.value = '';
    }
  }

  // ── Shifts ───────────────────────────────────────────────────────────────
  Future<void> addShift() async {
    final name  = shiftNameCtrl.text.trim();
    final start = shiftStartCtrl.text.trim();
    final end   = shiftEndCtrl.text.trim();
    if (name.isEmpty || start.isEmpty || end.isEmpty) {
      CustomAppSnackbar.warning('Fill in shift name, start and end times.');
      return;
    }
    isSavingShift.value = true;
    try {
      final ok = await _posRepo.createShift(
        storeId:   storeId.value,
        name:      name,
        startTime: start,
        endTime:   end,
      );
      if (ok) {
        shiftNameCtrl.clear();
        shiftStartCtrl.clear();
        shiftEndCtrl.clear();
        Get.back();
        CustomAppSnackbar.success('Shift added.');
        await _loadAll();
      }
    } finally {
      isSavingShift.value = false;
    }
  }

  Future<void> updateShift(StoreShift shift, {String? name, String? startTime, String? endTime}) async {
    processingShiftId.value = shift.id;
    try {
      final updated = await _posRepo.updateShift(
        storeId: storeId.value,
        shiftId: shift.id,
        name: name,
        startTime: startTime,
        endTime: endTime,
      );
      if (updated == null) return;
      final idx = shifts.indexWhere((s) => s.id == shift.id);
      if (idx >= 0) shifts[idx] = updated;
      CustomAppSnackbar.success('Shift updated.');
    } finally {
      processingShiftId.value = '';
    }
  }

  /// Tries a plain delete first; if the backend reports assigned employees,
  /// the caller can retry with [force] after confirming with the user.
  Future<bool> deleteShift(StoreShift shift, {bool force = false}) async {
    processingShiftId.value = shift.id;
    try {
      final ok = await _posRepo.deleteShift(storeId.value, shift.id, force: force);
      if (ok) {
        shifts.remove(shift);
        CustomAppSnackbar.success('Shift removed.');
      }
      return ok;
    } finally {
      processingShiftId.value = '';
    }
  }

  // ── Launch POS terminal ───────────────────────────────────────────────────
  void openPosTerminal() => Get.toNamed(Routes.posPinLogin);
}
