import 'package:solvexo_pos/utils/unsynced_guard.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/manager_approval_sheet.dart';
import 'package:solvexo_pos/app/data/services/pending_sale_sync_service.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'dart:async';

import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/denomination_sheet.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_subscription_status_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/data/services/idle_lock_service.dart';
import 'package:solvexo_pos/app/data/services/owner_gate.dart';
import 'package:solvexo_pos/app/data/services/pos_device_service.dart';
import 'package:solvexo_pos/app/data/services/thermal_printer_service.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_printer_picker_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_settings/widgets/pos_printer_settings_sheet.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart' show StoreDay;
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/core/design/design.dart';
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

  /// G4.6: the notes / coins counted at close (sent only while they add up to the closing amount)
  final RxList<Denomination> closingDenominations = <Denomination>[].obs;

  Future<void> countClosingCash() async {
    final rows = await DenominationSheet.open(initial: closingDenominations, title: 'Count the drawer');
    if (rows == null) return;
    closingDenominations.assignAll(rows);
    closingCashController.text = Money.plain(Money.fromMinor(denominationTotal(rows)));
  }

  List<Map<String, int>>? _closingDenoms(double amount) =>
      closingDenominations.isNotEmpty && denominationTotal(closingDenominations) == Money.toMinor(amount) ? denominationsJson(closingDenominations) : null;

  final TextEditingController closingCashController =
      TextEditingController(text: '0');

  /// G2.4: the card total printed on the terminal's settlement slip (optional). A difference from what the till recorded needs a manager.
  final TextEditingController cardSlipController = TextEditingController();

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
          title: 'Business Tax ID',
          trailing: settings.value?.businessTaxId?.isNotEmpty == true ? settings.value!.businessTaxId : (isManager ? 'Not set' : 'Managers only'),
          onTap: () {
            // Printed on every receipt, so owner/manager only (the backend stores it with the other POS settings).
            if (!isManager) {
              CustomAppSnackbar.warning('Only a manager can change the business tax ID.');
              return;
            }
            _editTextSetting(
              title: 'Business Tax ID',
              initial: settings.value?.businessTaxId ?? '',
              onSave: (v) => _posRepo.updatePosSettings(_storeId, {'businessTaxId': v}),
            );
          },
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
        PosSettingsTile(
          emoji: AppIcons.settingIcon,
          title: 'Printer settings',
          trailing: '${_printerService.paperMm.value} mm · ${_printerService.autoPrint.value ? 'auto-print' : 'manual'}',
          onTap: showPrinterSettings,
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
          trailing: Money.format(todaySales.value),
          onTap: () => Get.toNamed(Routes.posDailyReport),
        ),
        PosSettingsTile(
          emoji: AppIcons.cashIcon,
          title: 'Opening Float',
          trailing: Money.format(openingFloat.value),
        ),
        PosSettingsTile(
          emoji: AppIcons.anylaticsIcon,
          title: 'Shift History',
          onTap: () => Get.toNamed(Routes.posSessionHistory),
        ),
        PosSettingsTile(
          emoji: AppIcons.cashIcon,
          title: 'Cash Management',
          trailing: 'Cash in / out, expenses',
          onTap: showCashAdjustmentDialog,
        ),
        PosSettingsTile(
          emoji: AppIcons.anylaticsIcon,
          title: 'Sync & needs attention',
          trailing: Get.isRegistered<PendingSaleSyncService>() && Get.find<PendingSaleSyncService>().unresolvedCount.value > 0
              ? '${Get.find<PendingSaleSyncService>().unresolvedCount.value} unsynced'
              : 'All synced',
          onTap: () => Get.toNamed(Routes.posNeedsAttention),
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
          title: 'Plan status',
          trailing: _currentPlanLabel, // read-only; the details screen is owner-only
          onTap: () => Get.toNamed(Routes.posPlanStatus),
        ),
      ],
    ),
    PosSettingsSection(
      header: 'PREFERENCES',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.settingIcon,
          title: 'Store time zone',
          trailing: StoreDay.cached?.timeZone,
          onTap: () => Get.toNamed(Routes.posStoreTimeZone),
        ),
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
    PosSettingsSection(
      header: 'THIS DEVICE',
      tiles: [
        PosSettingsTile(
          emoji: AppIcons.settingIcon,
          title: 'Devices',
          trailing: 'Owner only',
          onTap: () => Get.toNamed(Routes.posDevices),
        ),
        PosSettingsTile(
          emoji: AppIcons.logoutIcon,
          title: 'Delete account',
          trailing: 'Owner only',
          onTap: () => Get.toNamed(Routes.posDeleteAccount),
        ),
        PosSettingsTile(
          emoji: AppIcons.logoutIcon,
          title: 'Sign out this device',
          trailing: isManager ? null : 'Managers only',
          onTap: signOutDevice,
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
    cardSlipController.dispose();
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
    final m = settings.value?.autoLockMinutes;
    if (m != null) {
      autoLockMinutes.value = m;
      await _applyAutoLock(m);
    }
  }

  Future<void> _loadSubscriptionStatus() async {
    subscriptionStatus.value = await _subscriptionRepo.getStatus(_storeId);
  }

  Future<void> refreshData() => _load();

  // ── Subscription ──────────────────────────────────────────────────────────

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
      contentBuilder: (c) => AppTextField(
        label: 'Tax rate',
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        mono: true,
        suffix: Padding(
          padding: const EdgeInsets.only(right: Space.s3),
          child: Text('%', style: c.type.body.copyWith(color: c.palette.textMuted)),
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

  /// The palette of the app's current theme (the sheets are opened without a BuildContext).
  AppPalette get _sheetPalette => Get.theme.extension<AppPalette>() ?? AppPalette.light;

  void showPrinterSettings() {
    Get.bottomSheet(
      PosPrinterSettingsSheet(service: _printerService, canEdit: isManager),
      backgroundColor: _sheetPalette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      isScrollControlled: true,
    );
  }

  void showPrinterPicker() {
    Get.bottomSheet(
      PosPrinterPickerSheet(service: _printerService),
      backgroundColor: _sheetPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _editTextSetting({
    required String title,
    required String initial,
    required Future<PosSettingsModel?> Function(String value) onSave,
  }) async {
    final ctx = Get.context;
    if (ctx == null) return;
    // Changing store configuration is the owner's: on a registered device that means re-entering the owner password.
    if (!await OwnerGate.ensure() || !ctx.mounted) return;
    final ctrl = TextEditingController(text: initial);
    CustomConfirmDialog.show(
      ctx,
      title: title,
      confirmLabel: 'Save',
      contentBuilder: (_) => AppTextField(
        label: title,
        controller: ctrl,
        maxLines: 3,
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

  /// The idle time is the OWNER's setting (stored with the store's POS settings, so every device follows it).
  Future<void> _cycleAutoLock() async {
    if (!await OwnerGate.ensure()) return;
    final idx = _autoLockOptions.indexOf(autoLockMinutes.value);
    final next = _autoLockOptions[(idx + 1) % _autoLockOptions.length];
    final saved = await _posRepo.updatePosSettings(_storeId, {'autoLockMinutes': next});
    if (saved == null) {
      CustomAppSnackbar.error("Couldn't save the auto-lock time.");
      return;
    }
    autoLockMinutes.value = next;
    await _applyAutoLock(next);
  }

  Future<void> _applyAutoLock(int minutes) async {
    await AppPreferences.setPosAutoLockMinutes(minutes);
    if (Get.isRegistered<IdleLockService>()) await Get.find<IdleLockService>().setMinutes(minutes);
  }

  // ── Device (5D) ───────────────────────────────────────────────────────────
  /// Full sign-out / reset of this terminal. Managers/owner only, and never while sales are still unsynced.
  Future<void> signOutDevice() async {
    if (!isManager) {
      CustomAppSnackbar.warning('Only a manager can sign this device out.');
      return;
    }
    final ctx = Get.context;
    if (ctx == null) return;
    if (await UnsyncedGuard.blockIfUnsynced(action: 'sign this device out') || !ctx.mounted) return;
    CustomConfirmDialog.show(
      ctx,
      title: 'Sign out this device?',
      message: 'This removes the device from the store and clears everything stored on it. Someone will need the owner password to set it up again.',
      confirmLabel: 'Sign out',
      destructive: true,
      onConfirm: () async {
        unawaited(_posRepo.pinLogout(_storeId));
        final r = await Get.find<PosDeviceService>().reset();
        if (r == DeviceResetResult.blockedByUnsyncedSales) {
          CustomAppSnackbar.error('Some sales have not synced yet — they are still on this device.');
          return;
        }
        Get.offAllNamed(Routes.posLogin);
      },
    );
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
    // The queue is the only copy of any sale not yet on the server: the shift can't close over it. (A manager
    // resolves each item from Needs attention — retry, or discard with a reason.)
    if (await UnsyncedGuard.blockIfUnsynced(action: 'close the shift', sessionId: _sessionId)) return;
    isLoadingCloseReport.value = true;
    final report = await _posRepo.getSessionReport(_sessionId);
    isLoadingCloseReport.value = false;
    preCloseReport.value = report;

    final ctx = Get.context;
    if (ctx == null || !ctx.mounted) return;
    closingCashController.text = '';
    cardSlipController.text = '';
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _ShiftDialogFrame(
        child: AppDialogCard(
          title: 'Close Shift',
          content: Builder(
            builder: (dctx) {
              final p = dctx.palette;
              final t = dctx.type;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (report != null) ...[
                    _CashFlowRow(label: 'Opening Cash', amount: report.cashFlow.openingCash),
                    _CashFlowRow(label: 'Cash Sales', amount: report.cashFlow.cashSales),
                    _CashFlowRow(label: 'Cash In', amount: report.cashFlow.cashIn),
                    _CashFlowRow(label: 'Cash Out', amount: -report.cashFlow.cashOut),
                    Padding(padding: const EdgeInsets.symmetric(vertical: Space.s2), child: Divider(height: 1, color: p.border)),
                    _CashFlowRow(label: 'Expected Cash', amount: report.cashFlow.expectedCash, bold: true),
                    const SizedBox(height: Space.s4),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      child: Text(
                        "Couldn't load the expected-cash breakdown — you can still close, but count carefully.",
                        style: t.bodySmall.copyWith(color: p.warningFg),
                      ),
                    ),
                  Text('Count the drawer and enter the actual cash amount.', style: t.bodySmall.copyWith(color: p.textSecondary)),
                  const SizedBox(height: Space.s3),
                  AppTextField(
                    label: 'Counted cash (${Money.symbol()})',
                    controller: closingCashController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    hint: '0.00',
                    mono: true,
                  ),
                  // G4.6: count the drawer note by note (the server checks the notes add up to the amount)
                  if (denominationsFor(Money.currency) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s2),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Obx(
                          () => AppButton(
                            key: const Key('countClosingCash'),
                            variant: AppButtonVariant.ghost,
                            expand: false,
                            icon: Icons.calculate_outlined,
                            label: closingDenominations.isEmpty ? 'Count notes & coins' : 'Counted ${closingDenominations.fold<int>(0, (n, d) => n + d.count)} notes & coins · edit',
                            onPressed: countClosingCash,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: Space.s4),
                  Text('Card total from the terminal slip (optional).', style: t.bodySmall.copyWith(color: p.textSecondary)),
                  const SizedBox(height: Space.s3),
                  AppTextField(
                    key: const Key('cardSlipField'),
                    label: 'Card total (${Money.symbol()})',
                    controller: cardSlipController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    hint: 'Leave empty to skip',
                    mono: true,
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
                          padding: const EdgeInsets.only(top: Space.s3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  short ? 'Short by' : (diff > 0 ? 'Over by' : 'Matches exactly'),
                                  style: t.bodySmall.copyWith(color: diff == 0 ? p.successFg : (short ? p.dangerFg : p.warningFg), fontWeight: FontWeight.w600),
                                ),
                              ),
                              if (diff != 0)
                                Flexible(
                                  child: AmountText(
                                    Money.format(diff.abs()),
                                    style: t.amountMd,
                                    color: short ? p.dangerFg : p.warningFg,
                                    animate: false,
                                    alignment: MainAxisAlignment.end,
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
          actions: [
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(ctx),
            ),
            Obx(() => AppButton(
              label: 'Close Shift',
              variant: AppButtonVariant.danger,
              loading: isClosing.value,
              onPressed: () {
                Navigator.pop(ctx);
                _closeShift();
              },
            )),
          ],
        ),
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
    final slipText = cardSlipController.text.trim();
    final slip = slipText.isEmpty ? null : double.tryParse(slipText);
    if (slipText.isNotEmpty && (slip == null || slip < 0)) {
      CustomAppSnackbar.warning('Enter a valid card total from the slip, or leave it empty.');
      return;
    }
    if (isClosing.value) return; // double-submit protection
    isClosing.value = true;
    try {
      final denoms = _closingDenoms(closingCash);
      var result = slip == null
          ? await _posRepo.closeSession(sessionId: _sessionId, closingCash: closingCash, denominations: denoms)
          : await _posRepo.closeSession(sessionId: _sessionId, closingCash: closingCash, cardTotalFromSlip: slip, denominations: denoms);
      if (!result.success && _posRepo.lastErrorCode == 'CARD_VARIANCE_APPROVAL_REQUIRED' && slip != null) {
        // the slip total differs from what the till recorded: only a manager may close the shift with that difference
        final token = await ManagerApproval.request(reason: result.message ?? 'The card total on the slip differs from the card total recorded at the till. A manager must approve closing the shift with this difference.', repository: _posRepo);
        if (token == null) return;
        result = await _posRepo.closeSession(sessionId: _sessionId, closingCash: closingCash, cardTotalFromSlip: slip, approverToken: token, denominations: denoms);
      }
      final session = result.session;
      if (!result.success || session == null) {
        if (_posRepo.lastErrorCode == 'DENOMINATION_MISMATCH' || _posRepo.lastErrorCode == 'DENOMINATION_TWICE') {
          closingDenominations.clear();
          CustomAppSnackbar.error('The notes and coins counted do not add up to the closing cash. Count again, or enter the amount only.');
          return;
        }
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }
      closingDenominations.clear();
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
      builder: (_) => _ShiftDialogFrame(
        child: AppDialogCard(
          title: 'Shift Closed',
          content: Builder(
            builder: (dctx) {
              final p = dctx.palette;
              final t = dctx.type;
              final tone = difference == 0 ? p.successFg : (short ? p.dangerFg : p.warningFg);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CashFlowRow(label: 'Expected Cash', amount: expected),
                  _CashFlowRow(label: 'Counted Cash', amount: counted),
                  Padding(padding: const EdgeInsets.symmetric(vertical: Space.s2), child: Divider(height: 1, color: p.border)),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          difference == 0 ? 'Matches exactly' : (short ? 'Short' : 'Over'),
                          style: t.subtitle.copyWith(color: tone),
                        ),
                      ),
                      if (difference != 0)
                        Flexible(
                          child: AmountText(Money.format(difference.abs()), style: t.amountLg, color: tone, animate: false, alignment: MainAxisAlignment.end),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            AppButton(
              label: 'Done',
              onPressed: () {
                Navigator.pop(ctx);
                Get.offAllNamed(Routes.posPinLogin);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Cash in / cash out ───────────────────────────────────────────────────
  // G3.5: cash in / out always has a category (and a note for "other"), works offline, and is open to every role (the SERVER decides what each
  // role may do and asks a manager's PIN above the store's limit). The old free-text dialog is gone; this entry point now opens the new screen.
  void showCashAdjustmentDialog() => Get.toNamed(Routes.posCash);

  String _friendlyError(String raw) {
    if (raw.toLowerCase().contains('held')) {
      return 'Cannot close: complete or discard held sales first.';
    }
    return 'Could not close shift. Please try again.';
  }
}

/// Holds a shift dialog card: transparent, lifted above the keyboard and scrollable when the form does not fit.
class _ShiftDialogFrame extends StatelessWidget {
  final Widget child;
  const _ShiftDialogFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s6),
      child: SingleChildScrollView(child: child),
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
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: t.body.copyWith(color: p.textPrimary, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            flex: 2,
            child: AmountText(Money.format(amount), style: t.amountMd, color: p.textPrimary, animate: false, alignment: MainAxisAlignment.end),
          ),
        ],
      ),
    );
  }
}

/// Cash In / Cash Out selector chip for the cash-adjustment dialog.
