import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/data/repositories/seller_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
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
  final _posRepo = PosRepository();
  final _sellerRepo = SellerRepository();

  final RxBool isLoading = true.obs;
  final RxBool isClosing = false.obs;
  final RxBool isSavingSettings = false.obs;

  // Profile
  final RxString name         = ''.obs;
  final RxString role         = ''.obs;
  final RxString registerName = ''.obs;
  final RxString shiftSince   = ''.obs;

  // POS settings (backend-tracked, per store)
  final Rx<PosSettingsModel?> settings = Rx(null);

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
          emoji: AppIcons.logoutIcon,
          title: 'Close Shift',
          onTap: showCloseShiftDialog,
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

  Future<void> refreshData() => _load();

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
  void showCloseShiftDialog() {
    final ctx = Get.context;
    if (ctx == null) return;
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const CustomText(
            text: 'Enter the closing cash amount in the drawer.',
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
          ),
          const SizedBox(height: 14),
          CustomTextField(
            controller: closingCashController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            hintText: '0.00',
            isborder: true,
            fillColor: AppColors.background,
            prefixIcon: const CustomText(text: '\$', fontSize: AppFontSize.verySmall, color: AppColors.iosGrey),
          ),
        ]),
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
    isClosing.value = true;
    try {
      final closingCash =
          double.tryParse(closingCashController.text.trim()) ?? 0.0;
      final result = await _posRepo.closeSession(
        sessionId: _sessionId,
        closingCash: closingCash,
      );
      if (!result.success) {
        CustomAppSnackbar.error(_friendlyError(result.message ?? ''));
        return;
      }
      await AppPreferences.clearPosSession();
      CustomAppSnackbar.success('Shift closed successfully.');
      Get.offAllNamed(Routes.posPinLogin);
    } finally {
      isClosing.value = false;
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
