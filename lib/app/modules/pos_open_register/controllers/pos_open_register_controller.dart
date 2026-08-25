import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosOpenRegisterController extends GetxController {
  final _posRepo = PosRepository();

  final RxBool isOpening = false.obs;
  final TextEditingController openingCashController = TextEditingController();

  // Passed via Get.arguments from PIN Login
  late PosEmployeeModel employee;
  late String registerId;
  late String registerName;
  late String storeId;

  // Shift — use the first shiftId from the employee record
  String get shiftId =>
      employee.shiftIds.isNotEmpty ? employee.shiftIds.first : '';

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    employee = args['employee'] as PosEmployeeModel;
    registerId = args['registerId'] as String? ?? '';
    registerName = args['registerName'] as String? ?? '';
    storeId = args['storeId'] as String? ?? '';
  }

  @override
  void onClose() {
    openingCashController.dispose();
    super.onClose();
  }

  Future<void> openRegister() async {
    final cashText = openingCashController.text.trim();
    final openingCash = double.tryParse(cashText) ?? 0.0;

    if (shiftId.isEmpty) {
      CustomAppSnackbar.error('No shift assigned to this employee.');
      return;
    }

    isOpening.value = true;
    try {
      final result = await _posRepo.openSession(
        storeId: storeId,
        registerId: registerId,
        employeeId: employee.id,
        shiftId: shiftId,
        openingCash: openingCash,
      );

      final session = result.session;
      if (!result.success || session == null) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }

      await AppPreferences.savePosSession(
        sessionId: session.id,
        registerId: session.registerId,
        shiftId: session.shiftId,
      );

      Get.offAllNamed(Routes.posHome);
    } catch (e) {
      CustomAppSnackbar.error('Could not open register. Please try again.');
    } finally {
      isOpening.value = false;
    }
  }

  String _friendlyError(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('already open') || lower.contains('session')) {
      return 'This register already has an open session.';
    }
    return 'Could not open register. Please try again.';
  }
}
