import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosPinLoginController extends GetxController {
  PosPinLoginController({PosRepository? posRepository, SellerRepository? sellerRepository})
      : _posRepo = posRepository ?? PosRepository(),
        _sellerRepo = sellerRepository ?? SellerRepository();

  final PosRepository _posRepo;
  final SellerRepository _sellerRepo;

  // ── State ─────────────────────────────────────────────────────────────────────
  final RxBool isLoading = false.obs;
  final RxBool isLoadingStore = false.obs;
  final RxString pin = ''.obs;
  final RxString email = ''.obs;
  final TextEditingController emailController = TextEditingController();

  // Store & register selection
  final RxList<Map<String, String>> registers = <Map<String, String>>[].obs;
  final Rx<Map<String, String>?> selectedRegister = Rx<Map<String, String>?>(null);
  final RxString storeId = ''.obs;

  static const int _pinLength = 4;

  @override
  void onInit() {
    super.onInit();
    _loadStore();
  }

  @override
  void onClose() {
    emailController.dispose();
    super.onClose();
  }

  // ── Load store registers from StoreModel (embedded registers[]) ───────────────
  Future<void> _loadStore() async {
    isLoadingStore.value = true;
    try {
      final sid = await AppPreferences.getStoreId();
      if (sid == null || sid.isEmpty) {
        CustomAppSnackbar.error('No active store. Please select a store first.');
        return;
      }
      storeId.value = sid;
      final store = await _sellerRepo.getStoreById(sid);
      if (store != null && store.registers.isNotEmpty) {
        registers.assignAll(
          store.registers
              .map((r) => {'id': r.id, 'name': r.name})
              .toList(),
        );
        selectedRegister.value = registers.first;
      }
    } catch (e) {
      debugPrint('❌ _loadStore: $e');
    } finally {
      isLoadingStore.value = false;
    }
  }

  // ── PIN keypad ────────────────────────────────────────────────────────────────
  void appendDigit(String digit) {
    if (pin.value.length >= _pinLength) return;
    pin.value += digit;
    if (pin.value.length == _pinLength) _submit();
  }

  void backspace() {
    if (pin.value.isNotEmpty) {
      pin.value = pin.value.substring(0, pin.value.length - 1);
    }
  }

  void clearPin() => pin.value = '';

  // ── Submit ────────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final emailVal = emailController.text.trim();
    if (emailVal.isEmpty) {
      CustomAppSnackbar.warning('Enter your employee email first.');
      clearPin();
      return;
    }
    if (selectedRegister.value == null) {
      CustomAppSnackbar.warning('Select a register to continue.');
      clearPin();
      return;
    }
    isLoading.value = true;
    try {
      final result = await _posRepo.pinLogin(
        storeId: storeId.value,
        email: emailVal,
        pin: pin.value,
      );

      if (!result.success || result.employee == null) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        clearPin();
        return;
      }

      final employee = result.employee!;

      // Persist employee context
      await AppPreferences.savePosEmployee(
        id: employee.id,
        name: employee.name,
        role: employee.role,
      );
      if (result.employeeToken != null) {
        await AppPreferences.setPosEmployeeToken(result.employeeToken!);
      }

      final activeSession = result.activeSession;
      final pickedRegisterId = selectedRegister.value!['id']!;

      if (activeSession != null && activeSession.isOpen) {
        if (activeSession.registerId != pickedRegisterId) {
          // The backend's "active session" lookup for this employee isn't
          // register-scoped — don't silently resume onto a register the
          // cashier didn't pick. Name the register it's actually open on.
          final openRegisterName = registers
                  .firstWhereOrNull((r) => r['id'] == activeSession.registerId)?['name'] ??
              'another register';
          CustomAppSnackbar.warning(
            'You already have an open session on "$openRegisterName". '
            'Switch to that register to resume, or ask a manager to close it first.',
          );
          clearPin();
          return;
        }
        // Session already open on the register the cashier picked → skip
        // Open Register, go straight to POS.
        await _persistSession(activeSession);
        Get.offAllNamed(Routes.posHome);
      } else {
        // No active session for this employee — double-check the *picked*
        // register itself isn't already open (e.g. another employee opened
        // it moments ago), since pinLogin's activeSession isn't
        // register-scoped and could miss that race.
        final registerSession = await _posRepo.getActiveSession(
          storeId: storeId.value,
          registerId: pickedRegisterId,
        );
        if (registerSession != null && registerSession.isOpen) {
          await _persistSession(registerSession);
          Get.offAllNamed(Routes.posHome);
          return;
        }
        Get.offNamed(
          Routes.posOpenRegister,
          arguments: {
            'employee': employee,
            'registerId': pickedRegisterId,
            'registerName': selectedRegister.value!['name']!,
            'storeId': storeId.value,
          },
        );
      }
    } catch (e) {
      CustomAppSnackbar.error('Login failed. Please try again.');
      clearPin();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _persistSession(PosSessionModel s) async {
    await AppPreferences.savePosSession(
      sessionId: s.id,
      registerId: s.registerId,
      shiftId: s.shiftId,
    );
  }

  String _friendlyError(String raw) {
    if (raw.toLowerCase().contains('invalid') ||
        raw.toLowerCase().contains('pin')) {
      return 'Invalid PIN. Please try again.';
    }
    if (raw.toLowerCase().contains('401')) return 'Authentication failed.';
    return 'Login failed. Please try again.';
  }

  void selectRegister(Map<String, String> reg) => selectedRegister.value = reg;
}
