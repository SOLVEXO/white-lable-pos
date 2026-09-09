import 'dart:async';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_printer_picker_sheet.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:solvexo_pos/utils/pos_role.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ── Settings tile models (unchanged) ─────────────────────────────────────────
class PosSettingsTile {
  final String emoji;
  final String title;
  final String? trailing;
  final bool isDanger;
  final VoidCallback? onTap;

  const PosSettingsTile({
    required this.emoji,
    required this.title,
    this.trailing,
    this.isDanger = false,
    this.onTap,
  });
}

class PosSettingsSection {
  final String header;
  final List<PosSettingsTile> tiles;
  const PosSettingsSection({required this.header, required this.tiles});
}

// ── Controller ────────────────────────────────────────────────────────────────
class PosSettingsController extends GetxController {
  PosSettingsController({
    PosRepository? posRepository,
    SellerRepository? sellerRepository,
    ThermalPrinterService? printerService,
    PosSubscriptionRepository? posSubscriptionRepository,
  })  : _posRepo = posRepository ?? PosRepository(),
        _sellerRepo = sellerRepository ?? SellerRepository(),
        _printerService = printerService ?? Get.find<ThermalPrinterService>(),
        _subscriptionRepo = posSubscriptionRepository ?? PosSubscriptionRepository();

  final PosRepository _posRepo;
  final SellerRepository _sellerRepo;
  final ThermalPrinterService _printerService;
  final PosSubscriptionRepository _subscriptionRepo;

  final RxBool isLoading = true.obs;
  final RxBool isClosing = false.obs;
  final RxBool isSavingSettings = false.obs;
  final RxBool isLoadingCloseReport = false.obs;
  final RxBool isSavingCashAdjustment = false.obs;
  final Rx<PosSessionReportModel?> preCloseReport = Rx(null);

  // Profile
  final RxString name         = ''.obs;
  final RxString role         = ''.obs;
  final RxString registerName = ''.obs;
  final RxString shiftSince   = ''.obs;

  /// See PosRole.isCurrentEmployeeManager's doc comment — gates Cash
  /// Management to match the backend's real, token-verified check.
  bool get isManager => PosRole.isManagerRole(role.value);

  String get _currentPlanLabel {
    final status = subscriptionStatus.value;
    switch (status?.status) {
      case PosSubscriptionStatusValue.active:
        return status?.planName ?? 'Active';
      case PosSubscriptionStatusValue.expired:
        return 'Expired';
      case PosSubscriptionStatusValue.none:
      case null:
        return 'No plan';
    }
  }

  // POS settings (backend-tracked, per store)
  final Rx<PosSettingsModel?> settings = Rx(null);
  final Rx<PosSubscriptionStatusModel?> subscriptionStatus = Rx(null);
  final RxBool isBuyingPlan = false.obs;

  // Shift stats
  final RxDouble todaySales   = 0.0.obs;
  final RxDouble openingFloat = 0.0.obs;

  // Preferences (device-local)
  final RxBool soundEffects = true.obs;
  final RxInt autoLockMinutes = 5.obs;

  // Session context
  String _sessionId  = '';
  String _registerId = '';
  String _storeId    = '';

  final TextEditingController closingCashController =
      TextEditingController(text: '0');

  // ── Computed ─────────────────────────────────────────────────────────────
  String get initials {
    final parts = name.value.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return 'P';
  }

  List<PosSettingsSection> get sections => [
    PosSettingsSection(
      header: 'REGISTER',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Register Name',
          trailing: registerName.value,
        ),
        PosSettingsTile(
          emoji: AppIcons.taxesIcon,
          title: 'Tax Rate',
          trailing: settings.value?.taxRatePercentLabel ?? '0%',
          onTap: _editTaxRate,
        ),
      ],
    ),
    PosSettingsSection(
      header: 'RECEIPT',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Business Name',
          trailing: settings.value?.businessName?.isNotEmpty == true ? settings.value!.businessName : 'Not set',
          onTap: () => _editTextSetting(
            title: 'Business Name',
            initial: settings.value?.businessName ?? '',
            onSave: (v) => _posRepo.updatePosSettings(_storeId, {'businessName': v}),
          ),
        ),
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Receipt Header',
          trailing: settings.value?.receiptHeader?.isNotEmpty == true ? 'Set' : 'Not set',
          onTap: () => _editTextSetting(
            title: 'Receipt Header',
            initial: settings.value?.receiptHeader ?? '',
            onSave: (v) => _posRepo.updatePosSettings(_storeId, {'receiptHeader': v}),
          ),
        ),
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Receipt Footer',
          trailing: settings.value?.receiptFooter?.isNotEmpty == true ? 'Set' : 'Not set',
          onTap: () => _editTextSetting(
            title: 'Receipt Footer',
            initial: settings.value?.receiptFooter ?? '',
            onSave: (v) => _posRepo.updatePosSettings(_storeId, {'receiptFooter': v}),
          ),
        ),
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Receipt Printer',
          trailing: _printerService.hasSavedPrinter
              ? _printerService.savedPrinterName.value
              : 'Not connected',
          onTap: showPrinterPicker,
        ),
      ],
    ),
    PosSettingsSection(
      header: 'STORE',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.barcodeIcon,
          title: 'Inventory',
          trailing: 'Stock levels & adjustments',
          onTap: () => Get.toNamed(Routes.posInventory),
        ),
        PosSettingsTile(
          emoji: AppIcons.anylaticsIcon,
          title: 'Stock Activity',
          onTap: () => Get.toNamed(Routes.posStockActivity),
        ),
        PosSettingsTile(
          emoji: AppIcons.profileIcon,
          title: 'Customers',
          onTap: () => Get.toNamed(Routes.posCustomers),
        ),
      ],
    ),
    PosSettingsSection(
      header: 'SHIFT',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.anylaticsIcon,
          title: "Today's Sales",
          trailing: '\$${todaySales.value.toStringAsFixed(2)}',
          onTap: () => Get.toNamed(Routes.posDailyReport),
        ),
        PosSettingsTile(
          emoji: AppIcons.cashIcon,
          title: 'Opening Float',
          trailing: '\$${openingFloat.value.toStringAsFixed(2)}',
        ),
        PosSettingsTile(
          emoji: AppIcons.anylaticsIcon,
          title: 'Shift History',
          onTap: () => Get.toNamed(Routes.posSessionHistory),
        ),
        PosSettingsTile(
          emoji: AppIcons.cashIcon,
          title: 'Cash Management',
          trailing: isManager ? 'Cash in / out' : 'Managers only',
          onTap: showCashAdjustmentDialog,
        ),
        PosSettingsTile(
          emoji: AppIcons.logoutIcon,
          title: 'Close Shift',
          onTap: showCloseShiftDialog,
        ),
      ],
    ),
    PosSettingsSection(
      header: 'CURRENT PLAN',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.cardIcon,
          title: 'Plan',
          trailing: _currentPlanLabel,
        ),
        if (subscriptionStatus.value?.status == PosSubscriptionStatusValue.active) ...[
          PosSettingsTile(
            emoji: AppIcons.cardIcon,
            title: 'Purchased',
            trailing: _formatDate(subscriptionStatus.value?.purchasedAt),
          ),
          PosSettingsTile(
            emoji: AppIcons.cardIcon,
            title: 'Expires',
            trailing: _formatDate(subscriptionStatus.value?.expiresAt),
          ),
          PosSettingsTile(
            emoji: AppIcons.cardIcon,
            title: 'Days Remaining',
            trailing: subscriptionStatus.value?.daysRemaining?.toString() ?? '—',
          ),
        ] else
          PosSettingsTile(
            emoji: AppIcons.cardIcon,
            title: 'Buy a Plan',
            trailing: isBuyingPlan.value ? 'Opening…' : null,
            onTap: isBuyingPlan.value ? null : _buyPlan,
          ),
      ],
    ),
    PosSettingsSection(
      header: 'PREFERENCES',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.notificationIcon,
          title: 'Sound Effects',
          trailing: soundEffects.value ? 'On' : 'Off',
          onTap: _toggleSoundEffects,
        ),
        PosSettingsTile(
          emoji: AppIcons.settingIcon,
          title: 'Auto-Lock',
          trailing: '${autoLockMinutes.value} min',
          onTap: _cycleAutoLock,
        ),
      ],
    ),
  ];

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _load();
  }

  @override
  void onClose() {
    closingCashController.dispose();
    super.onClose();
  }

  Future<void> _load() async {
    isLoading.value = true;
    try {
      _sessionId  = await AppPreferences.getPosSessionId()  ?? '';
      _registerId = await AppPreferences.getPosRegisterId() ?? '';
      _storeId    = await AppPreferences.getStoreId()       ?? '';

      name.value = await AppPreferences.getPosEmployeeName() ?? '';
      role.value = await AppPreferences.getPosEmployeeRole() ?? '';
      soundEffects.value = await AppPreferences.getPosSoundEffects();
      autoLockMinutes.value = await AppPreferences.getPosAutoLockMinutes();

      if (name.value.isEmpty) {
        final userName = await AppPreferences.getUserName();
        if (userName != null && userName.isNotEmpty) name.value = userName;
      }

      await Future.wait([
        if (_sessionId.isNotEmpty) _loadSessionStats(),
        if (_storeId.isNotEmpty) _loadRegisterName(),
        if (_storeId.isNotEmpty) _loadSettings(),
        if (_storeId.isNotEmpty) _loadSubscriptionStatus(),
      ]);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _loadSessionStats() async {
    final report = await _posRepo.getSessionReport(_sessionId);
    if (report != null) {
      todaySales.value   = report.totalSales;
      openingFloat.value = report.openingCash;
    }
  }

  Future<void> _loadRegisterName() async {
    final store = await _sellerRepo.getStoreById(_storeId);
    if (store == null || _registerId.isEmpty) return;
    final register = store.registers.where((r) => r.id == _registerId).firstOrNull;
    registerName.value = register?.name ?? 'Register';
  }

  Future<void> _loadSettings() async {
    settings.value = await _posRepo.getPosSettings(_storeId);
  }

  Future<void> _loadSubscriptionStatus() async {
    subscriptionStatus.value = await _subscriptionRepo.getStatus(_storeId);
  }

  Future<void> refreshData() => _load();

  // ── Subscription ──────────────────────────────────────────────────────────
  String _formatDate(DateTime? date) {
    if (date == null) return '—';
    return '${date.month}/${date.day}/${date.year}';
  }

  /// Routes into the plan-selection paywall so the seller can buy a plan
  /// for this store (no active one, or the last one expired) — fixed-term
  /// one-time purchase, no billing portal to manage between purchases.
  Future<void> _buyPlan() async {
    if (_storeId.isEmpty) return;
    isBuyingPlan.value = true;
    try {
      final storeName = await AppPreferences.getStoreName() ?? 'this store';
      final status = subscriptionStatus.value;
      await Get.toNamed(
        Routes.posSubscriptionPaywall,
        arguments: {
          'storeId': _storeId,
          'storeName': storeName,
          'isExpired': status?.status == PosSubscriptionStatusValue.expired,
          'expiresAt': status?.expiresAt?.toIso8601String(),
        },
      );
      await _loadSubscriptionStatus();
    } finally {
      isBuyingPlan.value = false;
    }
  }

  // ── Editable settings ─────────────────────────────────────────────────────
  void _editTaxRate() {
    final ctrl = TextEditingController(
      text: settings.value != null ? (settings.value!.taxRate * 100).toStringAsFixed(1) : '0',
    );
    final ctx = Get.context;
    if (ctx == null) return;
    CustomConfirmDialog.show(
      ctx,
      title: 'Tax Rate',
      confirmLabel: 'Save',
      contentBuilder: (_) => CustomTextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        isborder: true,
        fillColor: AppColors.background,
        suffixIcon: const Padding(
          padding: EdgeInsets.only(right: 12),
          child: CustomText(text: '%', fontSize: AppFontSize.verySmall, color: AppColors.iosGrey),
        ),
      ),
      onConfirm: () async {
        final pct = double.tryParse(ctrl.text.trim());
        if (pct == null || pct < 0 || pct > 100) {
          CustomAppSnackbar.warning('Enter a tax rate between 0 and 100.');
          return;
        }
        isSavingSettings.value = true;
        final updated = await _posRepo.updatePosSettings(_storeId, {'taxRate': pct / 100});
        isSavingSettings.value = false;
        if (updated != null) {
          settings.value = updated;
          CustomAppSnackbar.success('Tax rate updated.');
        }
      },
    );
  }

  void showPrinterPicker() {
    Get.bottomSheet(
      PosPrinterPickerSheet(service: _printerService),
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
    );
  }

  void _editTextSetting({
    required String title,
    required String initial,
    required Future<PosSettingsModel?> Function(String value) onSave,
  }) {
    final ctrl = TextEditingController(text: initial);
    final ctx = Get.context;
    if (ctx == null) return;
    CustomConfirmDialog.show(
      ctx,
      title: title,
      confirmLabel: 'Save',
      contentBuilder: (_) => CustomTextField(
        controller: ctrl,
        maxLines: 3,
        isborder: true,
        fillColor: AppColors.background,
      ),
      onConfirm: () async {
        isSavingSettings.value = true;
        final updated = await onSave(ctrl.text.trim());
        isSavingSettings.value = false;
        if (updated != null) {
          settings.value = updated;
          CustomAppSnackbar.success('$title updated.');
        }
      },
    );
  }

  Future<void> _toggleSoundEffects() async {
    soundEffects.value = !soundEffects.value;
    await AppPreferences.setPosSoundEffects(soundEffects.value);
  }

  static const _autoLockOptions = [1, 5, 10, 15, 30];

  Future<void> _cycleAutoLock() async {
    final idx = _autoLockOptions.indexOf(autoLockMinutes.value);
    final next = _autoLockOptions[(idx + 1) % _autoLockOptions.length];
    autoLockMinutes.value = next;
    await AppPreferences.setPosAutoLockMinutes(next);
  }

  // ── Close shift ───────────────────────────────────────────────────────────
  /// Fetches a live cash-flow breakdown (opening/cash sales/cash in/cash
  /// out/expected) before showing the dialog, so the cashier sees what's
  /// expected in the drawer *before* they count and enter a number — the
  /// backend already computes this on the fly via getSessionReport even for
  /// a still-open session (see PosSessionReportModel.cashFlow); it just used
  /// to only surface after closing, via a separate screen.
  Future<void> showCloseShiftDialog() async {
    if (_sessionId.isEmpty) {
      CustomAppSnackbar.error('No active session found.');
      return;
    }
    isLoadingCloseReport.value = true;
    final report = await _posRepo.getSessionReport(_sessionId);
    isLoadingCloseReport.value = false;
    preCloseReport.value = report;

    final ctx = Get.context;
    if (ctx == null) return;
    closingCashController.text = '';
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimen.dialogRadius)),
        title: const CustomText(
          text: 'Close Shift',
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (report != null) ...[
              _CashFlowRow(label: 'Opening Cash', amount: report.cashFlow.openingCash),
              _CashFlowRow(label: 'Cash Sales', amount: report.cashFlow.cashSales),
              _CashFlowRow(label: 'Cash In', amount: report.cashFlow.cashIn),
              _CashFlowRow(label: 'Cash Out', amount: -report.cashFlow.cashOut),
              const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: AppColors.lightGrey2)),
              _CashFlowRow(label: 'Expected Cash', amount: report.cashFlow.expectedCash, bold: true),
              const SizedBox(height: 14),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: CustomText(
                  text: "Couldn't load the expected-cash breakdown — you can still close, but count carefully.",
                  fontSize: AppFontSize.tiny,
                  color: AppColors.orange,
                ),
              ),
            const CustomText(
              text: 'Count the drawer and enter the actual cash amount.',
              fontSize: AppFontSize.verySmall,
              color: AppColors.grey,
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: closingCashController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              hintText: '0.00',
              isborder: true,
              fillColor: AppColors.background,
              prefixIcon: const CustomText(text: '\$', fontSize: AppFontSize.verySmall, color: AppColors.iosGrey),
            ),
            if (report != null)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: closingCashController,
                builder: (_, value, __) {
                  final counted = double.tryParse(value.text.trim());
                  if (counted == null) return const SizedBox.shrink();
                  final diff = counted - report.cashFlow.expectedCash;
                  final short = diff < 0;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(children: [
                      CustomText(
                        text: short ? 'Short by' : (diff > 0 ? 'Over by' : 'Matches exactly'),
                        fontSize: AppFontSize.tiny,
                        color: diff == 0 ? AppColors.green2 : (short ? AppColors.red : AppColors.orange),
                      ),
                      const Spacer(),
                      if (diff != 0)
                        CustomText(
                          text: '\$${diff.abs().toStringAsFixed(2)}',
                          fontSize: AppFontSize.verySmall,
                          fontWeight: FontWeight.bold,
                          color: short ? AppColors.red : AppColors.orange,
                        ),
                    ]),
                  );
                },
              ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel', fontSize: AppFontSize.verySmall, color: AppColors.grey),
          ),
          Obx(() => _DialogPillButton(
            label: 'Close Shift',
            color: AppColors.red,
            loading: isClosing.value,
            onTap: () {
              Navigator.pop(ctx);
              _closeShift();
            },
          )),
        ],
      ),
    );
  }

  Future<void> _closeShift() async {
    if (_sessionId.isEmpty) {
      CustomAppSnackbar.error('No active session found.');
      return;
    }
    final closingCash = double.tryParse(closingCashController.text.trim());
    if (closingCash == null || closingCash < 0) {
      CustomAppSnackbar.warning('Enter a valid closing cash amount.');
      return;
    }
    isClosing.value = true;
    try {
      final result = await _posRepo.closeSession(
        sessionId: _sessionId,
        closingCash: closingCash,
      );
      final session = result.session;
      if (!result.success || session == null) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }
      // Fire-and-forget — the local session close doesn't wait on this, but
      // it's the one clear point where this device's PIN session is ending.
      unawaited(_posRepo.pinLogout(_storeId));
      await AppPreferences.clearPosSession();
      _showCloseSummary(session.expectedCash, session.closingCash ?? closingCash, session.cashDifference);
    } finally {
      isClosing.value = false;
    }
  }

  void _showCloseSummary(double expected, double counted, double difference) {
    final ctx = Get.context;
    if (ctx == null) {
      Get.offAllNamed(Routes.posPinLogin);
      return;
    }
    final short = difference < 0;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimen.dialogRadius)),
        title: const CustomText(
          text: 'Shift Closed',
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _CashFlowRow(label: 'Expected Cash', amount: expected),
          _CashFlowRow(label: 'Counted Cash', amount: counted),
          const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: AppColors.lightGrey2)),
          Row(children: [
            CustomText(
              text: difference == 0 ? 'Matches exactly' : (short ? 'Short' : 'Over'),
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.bold,
              color: difference == 0 ? AppColors.green2 : (short ? AppColors.red : AppColors.orange),
            ),
            const Spacer(),
            if (difference != 0)
              CustomText(
                text: '\$${difference.abs().toStringAsFixed(2)}',
                fontSize: AppFontSize.small2,
                fontWeight: FontWeight.bold,
                color: short ? AppColors.red : AppColors.orange,
              ),
          ]),
        ]),
        actions: [
          _DialogPillButton(
            label: 'Done',
            onTap: () {
              Navigator.pop(ctx);
              Get.offAllNamed(Routes.posPinLogin);
            },
          ),
        ],
      ),
    );
  }

  // ── Cash in / cash out ───────────────────────────────────────────────────
  // Manager-only, matching the backend's real, token-verified check
  // (PosService.cashInOut now requires a verified manager token
  // unconditionally) — see PosRole's doc comment.
  void showCashAdjustmentDialog() {
    if (!isManager) {
      CustomAppSnackbar.warning('Only managers can record cash movements — ask a manager to do this from their own login.');
      return;
    }
    if (_sessionId.isEmpty) {
      CustomAppSnackbar.error('No active session found.');
      return;
    }
    final ctx = Get.context;
    if (ctx == null) return;
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final isCashIn = true.obs;

    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimen.dialogRadius)),
        title: const CustomText(
          text: 'Cash Management',
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Obx(() => Row(children: [
              Expanded(
                child: _CashTypeChip(
                  label: 'Cash In',
                  selected: isCashIn.value,
                  color: AppColors.green2,
                  onTap: () => isCashIn.value = true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _CashTypeChip(
                  label: 'Cash Out',
                  selected: !isCashIn.value,
                  color: AppColors.red,
                  onTap: () => isCashIn.value = false,
                ),
              ),
            ])),
            const SizedBox(height: 12),
            CustomTextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              hintText: 'Amount',
              isborder: true,
              fillColor: AppColors.background,
              prefixIcon: const CustomText(text: '\$', fontSize: AppFontSize.verySmall, color: AppColors.iosGrey),
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: reasonController,
              hintText: 'Reason (e.g. petty cash, till top-up)',
              isborder: true,
              fillColor: AppColors.background,
            ),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel', fontSize: AppFontSize.verySmall, color: AppColors.grey),
          ),
          Obx(() => _DialogPillButton(
            label: 'Save',
            loading: isSavingCashAdjustment.value,
            onTap: () {
              final amount = double.tryParse(amountController.text.trim());
              final reason = reasonController.text.trim();
              if (amount == null || amount <= 0) {
                CustomAppSnackbar.warning('Enter a valid amount.');
                return;
              }
              if (reason.isEmpty) {
                CustomAppSnackbar.warning('Enter a reason for this cash movement.');
                return;
              }
              Navigator.pop(ctx);
              _recordCashAdjustment(isCashIn.value ? 'cash_in' : 'cash_out', amount, reason);
            },
          )),
        ],
      ),
    );
  }

  Future<void> _recordCashAdjustment(String type, double amount, String reason) async {
    isSavingCashAdjustment.value = true;
    try {
      final employeeId = await AppPreferences.getPosEmployeeId() ?? '';
      final result = await _posRepo.cashAdjustment(
        sessionId: _sessionId,
        type: type,
        amount: amount,
        reason: reason,
        employeeId: employeeId,
      );
      if (result == null) return;
      CustomAppSnackbar.success(type == 'cash_in' ? 'Cash in recorded.' : 'Cash out recorded.');
      await _loadSessionStats();
    } finally {
      isSavingCashAdjustment.value = false;
    }
  }

  String _friendlyError(String raw) {
    if (raw.toLowerCase().contains('held')) {
      return 'Cannot close: complete or discard held sales first.';
    }
    return 'Could not close shift. Please try again.';
  }
}

/// A colored pill-style dialog action button — mirrors the destructive
/// action style already used across the app's confirm dialogs, with an
/// optional inline loading state.
class _DialogPillButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool loading;

  const _DialogPillButton({
    required this.label,
    required this.onTap,
    this.color,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primaryColor;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: loading ? effectiveColor.withOpacity(0.5) : effectiveColor,
          borderRadius: BorderRadius.circular(AppDimen.borderRadius),
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
              )
            : CustomText(
                text: label,
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.w600,
                color: AppColors.white,
              ),
      ),
    );
  }
}

/// One line of a cash-flow breakdown (opening/sales/in/out/expected) —
/// shared between the close-shift preview dialog and the post-close summary.
class _CashFlowRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool bold;
  const _CashFlowRow({required this.label, required this.amount, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        CustomText(
          text: label,
          fontSize: AppFontSize.verySmall,
          fontWeight: bold ? FontWeight.bold : FontWeight.w400,
          color: AppColors.black2,
        ),
        const Spacer(),
        CustomText(
          text: '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}',
          fontSize: AppFontSize.verySmall,
          fontWeight: bold ? FontWeight.bold : FontWeight.w600,
          color: AppColors.black2,
        ),
      ]),
    );
  }
}

/// Cash In / Cash Out selector chip for the cash-adjustment dialog.
class _CashTypeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _CashTypeChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(AppDimen.borderRadius),
          border: Border.all(color: selected ? color : AppColors.lightGrey2),
        ),
        alignment: Alignment.center,
        child: CustomText(
          text: label,
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: selected ? color : AppColors.black2,
        ),
      ),
    );
  }
}
