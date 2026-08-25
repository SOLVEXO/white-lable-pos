import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosPinLoginController extends GetxController {
  final _posRepo = PosRepository();
  final _sellerRepo = SellerRepository();

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

      final activeSession = result.activeSession;

      if (activeSession != null && activeSession.isOpen) {
        // Session already open → skip Open Register, go straight to POS
        await _persistSession(activeSession);
        Get.offAllNamed(Routes.posHome);
      } else {
        // No open session → go to Open Register screen
        Get.offNamed(
          Routes.posOpenRegister,
          arguments: {
            'employee': employee,
            'registerId': selectedRegister.value!['id']!,
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
