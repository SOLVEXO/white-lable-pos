import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/denomination_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/services/pos_entitlement_service.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosOpenRegisterController extends GetxController {
  PosOpenRegisterController({PosRepository? posRepository}) : _posRepo = posRepository ?? PosRepository();

  final PosRepository _posRepo;

  final RxBool isOpening = false.obs;
  final TextEditingController openingCashController = TextEditingController();

  /// G4.6: what the register's last shift closed with (counted / expected / variance), shown before the float is counted
  final Rxn<LastClose> lastClose = Rxn<LastClose>();

  /// G4.6: the notes / coins counted into the float (sent only while their total is still the amount in the field)
  final RxList<Denomination> denominations = <Denomination>[].obs;

  /// the store's currency (from the last-close answer; the app's configured currency until then)
  String get currency => lastClose.value?.currency ?? Money.currency;
  int get exponent => lastClose.value?.exponent ?? Money.exponent;
  bool get canCount => denominationsFor(currency) != null;

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
    final args = Get.arguments is Map ? (Get.arguments as Map).cast<String, dynamic>() : const <String, dynamic>{};
    // (only what the PIN login passed; a test sets the fields itself)
    if (args['employee'] is PosEmployeeModel) employee = args['employee'] as PosEmployeeModel;
    if (args.containsKey('registerId')) registerId = args['registerId'] as String? ?? '';
    if (args.containsKey('registerName')) registerName = args['registerName'] as String? ?? '';
    if (args.containsKey('storeId')) storeId = args['storeId'] as String? ?? '';
    _loadLastClose();
  }

  Future<void> _loadLastClose() async {
    try {
      if (storeId.isEmpty || registerId.isEmpty) return;
    } catch (_) {
      return; // not set (no arguments)
    }
    try {
      lastClose.value = await _posRepo.getLastClose(storeId, registerId);
    } catch (_) {
      /* only a read-out: opening never waits for it */
    }
  }

  /// Count the float note by note; the total goes into the field.
  Future<void> countFloat() async {
    final rows = await DenominationSheet.open(currency: currency, exponent: exponent, initial: denominations, title: 'Count the float');
    if (rows == null) return;
    denominations.assignAll(rows);
    openingCashController.text = Money.plain(Money.fromMinor(denominationTotal(rows), exponent), exponent: exponent);
  }

  /// the counted rows, when they still add up to the amount typed (an edited amount drops the breakdown)
  List<Map<String, int>>? _denomsFor(double amount) =>
      denominations.isNotEmpty && denominationTotal(denominations) == Money.toMinor(amount, exponent) ? denominationsJson(denominations) : null;

  @override
  void onClose() {
    openingCashController.dispose();
    super.onClose();
  }

  Future<void> openRegister() async {
    final cashText = openingCashController.text.trim();
    final openingCash = double.tryParse(cashText);
    if (openingCash == null || openingCash < 0) {
      CustomAppSnackbar.warning('Enter a valid opening cash amount.');
      return;
    }

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
        denominations: _denomsFor(openingCash),
      );

      final session = result.session;
      if (!result.success || session == null) {
        // The backend refused because the POS plan isn't active: the repository has switched the app to
        // restricted mode — leave Open Register for the restricted shell (close shift, reports, sign out).
        if (PosEntitlementService.isRestricted) {
          Get.offAllNamed(Routes.posHome);
          return;
        }
        if (_posRepo.lastErrorCode == 'DENOMINATION_MISMATCH' || _posRepo.lastErrorCode == 'DENOMINATION_TWICE') {
          denominations.clear();
          CustomAppSnackbar.error('The notes and coins counted do not add up to the float. Count again, or enter the amount only.');
          return;
        }
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
