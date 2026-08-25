import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_button.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/components/custom_refresh_wrapper.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/modules/seller_pos_management/controllers/seller_pos_management_controller.dart';
import 'package:solvexo_pos/app/modules/seller_pos_management/widgets/seller_pos_management_shimmer.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class SellerPosManagementView extends StatelessWidget {
  SellerPosManagementView({super.key});

  final SellerPosManagementController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Obx(
          () => CustomAppBarTwo(
            title: c.storeName.value.isEmpty
                ? 'POS Management'
                : c.storeName.value,
            color: AppColors.black2,
            // This screen is always reached via Get.offAllNamed (from the
            // store picker or right after onboarding creates a store), so
            // the nav stack is empty here — a leading button would show but
            // Get.back() would silently do nothing. Same convention as
            // seller_stores/pos_home, the app's other stack-root screens:
            // no leading button at all.
            showLeading: false,
            actions: [
              GestureDetector(
                onTap: c.refreshData,
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(
                    Icons.refresh_rounded,
                    color: AppColors.primaryColor,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const SellerPosManagementShimmer();
        }
        return CustomRefreshWrapper(
          onRefresh: c.refreshData,

          child: ListView(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            children: [
              _OpenPosButton(c: c),
              const SizedBox(height: 16),
              _StatsRow(c: c),
              const SizedBox(height: 12),
              const _ReportsLinksRow(),
              const SizedBox(height: 20),
              _EmployeesSection(c: c),
              const SizedBox(height: 20),
              _RegistersSection(c: c),
              const SizedBox(height: 20),
              _ShiftsSection(c: c),
              const SizedBox(height: 20),
              _SessionsSection(c: c),
              const SizedBox(height: 20),
            ],
          ),
        );
      }),
    );
  }
}

// ── Open POS button ──────────────────────────────────────────────────────────
class _OpenPosButton extends StatelessWidget {
  final SellerPosManagementController c;
  const _OpenPosButton({required this.c});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: c.openPosTerminal,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFd97757), Color(0xFFE8956A)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryColor.withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.point_of_sale_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            CustomText(
              text: 'Open POS Terminal',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Stats row ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final SellerPosManagementController c;
  const _StatsRow({required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.people_outline_rounded,
            label: 'Employees',
            value: '${c.employees.length}',
            color: AppColors.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.point_of_sale_outlined,
            label: 'Registers',
            value: '${c.registers.length}',
            color: AppColors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.attach_money_rounded,
            label: "Today's Sales",
            value:
                '\$${(c.dailyReport.value?.totalRevenue ?? 0).toStringAsFixed(0)}',
            color: AppColors.green2,
          ),
        ),
      ],
    );
  }
}

class _ReportsLinksRow extends StatelessWidget {
  const _ReportsLinksRow();

  @override
  Widget build(BuildContext context) {
    // UI-level only — a tenant can hide the audit log entry point via
    // white-label feature flags; the route/API still exist either way.
    final showAuditLog = Get.find<BrandingService>().isFeatureEnabled(
      'posAuditLog',
    );
    return Row(
      children: [
        Expanded(
          child: _LinkChip(
            icon: Icons.bar_chart_rounded,
            label: 'Reports',
            onTap: () => Get.toNamed(Routes.posRangeReport),
          ),
        ),
        if (showAuditLog) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _LinkChip(
              icon: Icons.history_rounded,
              label: 'Activity Log',
              onTap: () => Get.toNamed(Routes.posAuditLog),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: _LinkChip(
            icon: Icons.store_mall_directory_outlined,
            label: 'Locations',
            onTap: () => Get.toNamed(Routes.sellerPosLocations),
          ),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.lightGrey2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryColor),
            const SizedBox(width: 6),
            CustomText(
              text: label,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: AppColors.black2,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 8),
          CustomText(
            text: value,
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.black2,
          ),
          const SizedBox(height: 2),
          CustomText(
            text: label,
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback onAction;
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomText(
          text: title,
          fontFamily: AppTextStyles.headingFontFamily,
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  color: AppColors.primaryColor,
                  size: 14,
                ),
                const SizedBox(width: 4),
                CustomText(
                  text: actionLabel,
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Employees section ─────────────────────────────────────────────────────────
class _EmployeesSection extends StatelessWidget {
  final SellerPosManagementController c;
  const _EmployeesSection({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Employees',
          actionLabel: 'Add',
          onAction: () => _showAddEmployeeSheet(context),
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (c.employees.isEmpty) {
            return _EmptyCard(
              icon: Icons.person_add_outlined,
              message: 'No employees yet. Add one to get started.',
            );
          }
          return Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: c.employees.asMap().entries.map((entry) {
                final i = entry.key;
                final emp = entry.value;
                return Column(
                  children: [
                    if (i > 0)
                      const Divider(
                        height: 1,
                        color: AppColors.lightGrey2,
                        indent: 16,
                        endIndent: 16,
                      ),
                    _EmployeeTile(emp: emp, c: c),
                  ],
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  void _showAddEmployeeSheet(BuildContext context) {
    Get.bottomSheet(
      _AddEmployeeSheet(c: c),
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  final PosEmployeeModel emp;
  final SellerPosManagementController c;
  const _EmployeeTile({required this.emp, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isDeleting = c.deletingEmployeeId.value == emp.id;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: CustomText(
            text: emp.initials,
            fontSize: AppFontSize.verySmall,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
        ),
        title: CustomText(
          text: emp.name,
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.black2,
        ),
        subtitle: CustomText(
          text: '${emp.role.capitalizeFirst ?? emp.role}  ·  ${emp.email}',
          fontSize: AppFontSize.tiny,
          color: AppColors.iosGrey,
        ),
        trailing: isDeleting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.red,
                ),
              )
            : PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.iosGrey,
                  size: 20,
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      _showEditEmployeeSheet(context, emp);
                      break;
                    case 'reset_pin':
                      _showResetPinDialog(context, emp);
                      break;
                    case 'remove':
                      _confirmDelete(context, emp);
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: CustomText(
                      text: 'Edit',
                      fontSize: AppFontSize.verySmall,
                      color: AppColors.black2,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reset_pin',
                    child: CustomText(
                      text: 'Reset PIN',
                      fontSize: AppFontSize.verySmall,
                      color: AppColors.black2,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: CustomText(
                      text: 'Remove',
                      fontSize: AppFontSize.verySmall,
                      color: AppColors.red,
                    ),
                  ),
                ],
              ),
      );
    });
  }

  void _showEditEmployeeSheet(BuildContext context, PosEmployeeModel emp) {
    Get.bottomSheet(
      _EditEmployeeSheet(c: c, emp: emp),
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  void _showResetPinDialog(BuildContext context, PosEmployeeModel emp) {
    final ctrl = TextEditingController();
    CustomConfirmDialog.show(
      context,
      title: 'Reset PIN',
      confirmLabel: 'Reset',
      contentBuilder: (_) => CustomTextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        hintText: 'New 4-digit PIN',
        isborder: true,
        fillColor: AppColors.background,
      ),
      onConfirm: () {
        final pin = ctrl.text.trim();
        if (pin.length != 4 || int.tryParse(pin) == null) {
          CustomAppSnackbar.warning('PIN must be exactly 4 digits.');
          return;
        }
        c.resetEmployeePin(emp, pin);
      },
    );
  }

  void _confirmDelete(BuildContext context, PosEmployeeModel emp) {
    CustomConfirmDialog.show(
      context,
      title: 'Remove Employee',
      message: 'Remove ${emp.name}? They will no longer be able to log in.',
      confirmLabel: 'Remove',
      confirmColor: AppColors.red,
      onConfirm: () => c.deleteEmployee(emp),
    );
  }
}

// ── Add Employee bottom sheet ─────────────────────────────────────────────────
class _AddEmployeeSheet extends StatelessWidget {
  final SellerPosManagementController c;
  const _AddEmployeeSheet({required this.c});

  static const _roles = ['cashier', 'manager'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.lightGrey2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const CustomText(
              text: 'Add Employee',
              fontSize: AppFontSize.medium,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: c.empNameCtrl,
              hintText: 'Full Name',
              fillColor: AppColors.background,
              prefixIcon: const Icon(
                Icons.person_outline_rounded,
                color: AppColors.iosGrey,
                size: 18,
              ),
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: c.empEmailCtrl,
              hintText: 'Email Address',
              keyboardType: TextInputType.emailAddress,
              fillColor: AppColors.background,
              prefixIcon: const Icon(
                Icons.email_outlined,
                color: AppColors.iosGrey,
                size: 18,
              ),
            ),
            const SizedBox(height: 10),
            CustomTextField(
              controller: c.empPinCtrl,
              hintText: '4-Digit PIN',
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              fillColor: AppColors.background,
              prefixIcon: const Icon(
                Icons.pin_outlined,
                color: AppColors.iosGrey,
                size: 18,
              ),
            ),
            const SizedBox(height: 10),
            // Role picker
            Obx(
              () => Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: c.empRole.value,
                    isExpanded: true,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.iosGrey,
                    ),
                    onChanged: (v) {
                      if (v != null) c.empRole.value = v;
                    },
                    items: _roles
                        .map(
                          (r) => DropdownMenuItem(
                            value: r,
                            child: CustomText(
                              text: r.capitalizeFirst ?? r,
                              fontSize: AppFontSize.verySmall,
                              color: AppColors.black2,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Shift picker
            Obx(
              () => c.shifts.isEmpty
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: c.empShiftId.value.isNotEmpty
                              ? c.empShiftId.value
                              : null,
                          hint: const CustomText(
                            text: 'Assign Shift (optional)',
                            fontSize: AppFontSize.verySmall,
                            color: AppColors.iosGrey,
                          ),
                          isExpanded: true,
                          icon: const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: AppColors.iosGrey,
                          ),
                          onChanged: (v) {
                            if (v != null) c.empShiftId.value = v;
                          },
                          items: c.shifts
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: CustomText(
                                    text: s.name,
                                    fontSize: AppFontSize.verySmall,
                                    color: AppColors.black2,
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            Obx(
              () => CustomButton(
                label: c.isSavingEmployee.value ? '' : 'Add Employee',
                width: double.infinity,
                height: 50,
                borderRadius: 12,
                enabled: !c.isSavingEmployee.value,
                onPressed: c.addEmployee,
                prefix: c.isSavingEmployee.value
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.white,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Edit Employee bottom sheet ────────────────────────────────────────────────
class _EditEmployeeSheet extends StatefulWidget {
  final SellerPosManagementController c;
  final PosEmployeeModel emp;
  const _EditEmployeeSheet({required this.c, required this.emp});

  @override
  State<_EditEmployeeSheet> createState() => _EditEmployeeSheetState();
}

class _EditEmployeeSheetState extends State<_EditEmployeeSheet> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.emp.name,
  );
  late String _role = widget.emp.role;
  bool _saving = false;

  static const _roles = ['cashier', 'manager'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Edit Employee',
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.black2,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: _nameCtrl,
            hintText: 'Full Name',
            fillColor: AppColors.background,
            prefixIcon: const Icon(
              Icons.person_outline_rounded,
              color: AppColors.iosGrey,
              size: 18,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _role,
                isExpanded: true,
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.iosGrey,
                ),
                onChanged: (v) {
                  if (v != null) setState(() => _role = v);
                },
                items: _roles
                    .map(
                      (r) => DropdownMenuItem(
                        value: r,
                        child: CustomText(
                          text: r.capitalizeFirst ?? r,
                          fontSize: AppFontSize.verySmall,
                          color: AppColors.black2,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          CustomButton(
            label: _saving ? '' : 'Save Changes',
            width: double.infinity,
            height: 50,
            borderRadius: 12,
            enabled: !_saving,
            prefix: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.white,
                    ),
                  )
                : null,
            onPressed: () async {
              setState(() => _saving = true);
              await widget.c.updateEmployee(
                widget.emp,
                name: _nameCtrl.text.trim(),
                role: _role,
              );
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

// ── Registers section ─────────────────────────────────────────────────────────
class _RegistersSection extends StatelessWidget {
  final SellerPosManagementController c;
  const _RegistersSection({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Registers',
          actionLabel: 'Add',
          onAction: () => _showAddRegisterSheet(context),
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (c.registers.isEmpty) {
            return _EmptyCard(
              icon: Icons.point_of_sale_outlined,
              message: 'No registers. Add one to start processing sales.',
            );
          }
          return Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: c.registers.asMap().entries.map((entry) {
                final i = entry.key;
                final reg = entry.value;
                return Column(
                  children: [
                    if (i > 0)
                      const Divider(
                        height: 1,
                        color: AppColors.lightGrey2,
                        indent: 16,
                        endIndent: 16,
                      ),
                    Obx(() {
                      final isProcessing =
                          c.processingRegisterId.value == reg.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            color: AppColors.orange,
                            size: 18,
                          ),
                        ),
                        title: CustomText(
                          text: reg.name,
                          fontSize: AppFontSize.verySmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black2,
                        ),
                        subtitle: CustomText(
                          text: reg.status == 'active' ? 'Active' : 'Inactive',
                          fontSize: AppFontSize.tiny,
                          color: reg.status == 'active'
                              ? AppColors.green2
                              : AppColors.iosGrey,
                        ),
                        trailing: isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.orange,
                                ),
                              )
                            : PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.iosGrey,
                                  size: 20,
                                ),
                                onSelected: (action) {
                                  switch (action) {
                                    case 'rename':
                                      _showRenameRegisterDialog(context, reg);
                                      break;
                                    case 'toggle':
                                      c.updateRegister(
                                        reg,
                                        status: reg.status == 'active'
                                            ? 'inactive'
                                            : 'active',
                                      );
                                      break;
                                    case 'delete':
                                      _confirmDeleteRegister(context, reg);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: CustomText(
                                      text: 'Rename',
                                      fontSize: AppFontSize.verySmall,
                                      color: AppColors.black2,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'toggle',
                                    child: CustomText(
                                      text: reg.status == 'active'
                                          ? 'Deactivate'
                                          : 'Activate',
                                      fontSize: AppFontSize.verySmall,
                                      color: AppColors.black2,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: CustomText(
                                      text: 'Delete',
                                      fontSize: AppFontSize.verySmall,
                                      color: AppColors.red,
                                    ),
                                  ),
                                ],
                              ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  void _showAddRegisterSheet(BuildContext context) {
    Get.bottomSheet(
      _AddRegisterSheet(c: c),
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  void _showRenameRegisterDialog(BuildContext context, StoreRegister reg) {
    final ctrl = TextEditingController(text: reg.name);
    CustomConfirmDialog.show(
      context,
      title: 'Rename Register',
      confirmLabel: 'Save',
      contentBuilder: (_) => CustomTextField(
        controller: ctrl,
        isborder: true,
        fillColor: AppColors.background,
      ),
      onConfirm: () {
        final name = ctrl.text.trim();
        if (name.isNotEmpty) c.updateRegister(reg, name: name);
      },
    );
  }

  void _confirmDeleteRegister(BuildContext context, StoreRegister reg) {
    CustomConfirmDialog.show(
      context,
      title: 'Delete Register',
      message: 'Delete "${reg.name}"? This fails if it has an open session.',
      confirmLabel: 'Delete',
      confirmColor: AppColors.red,
      onConfirm: () => c.deleteRegister(reg),
    );
  }
}

class _AddRegisterSheet extends StatelessWidget {
  final SellerPosManagementController c;
  const _AddRegisterSheet({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Add Register',
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.black2,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: c.regNameCtrl,
            hintText: 'Register Name (e.g. Counter 1)',
            fillColor: AppColors.background,
            prefixIcon: const Icon(
              Icons.point_of_sale_outlined,
              color: AppColors.iosGrey,
              size: 18,
            ),
          ),
          const SizedBox(height: 16),
          Obx(
            () => CustomButton(
              label: c.isSavingRegister.value ? '' : 'Add Register',
              width: double.infinity,
              height: 50,
              borderRadius: 12,
              enabled: !c.isSavingRegister.value,
              onPressed: c.addRegister,
              prefix: c.isSavingRegister.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shifts section ────────────────────────────────────────────────────────────
class _ShiftsSection extends StatelessWidget {
  final SellerPosManagementController c;
  const _ShiftsSection({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(
          title: 'Shifts',
          actionLabel: 'Add',
          onAction: () => _showAddShiftSheet(context),
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (c.shifts.isEmpty) {
            return _EmptyCard(
              icon: Icons.schedule_outlined,
              message: 'No shifts defined. Add shifts to assign to employees.',
            );
          }
          return Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: c.shifts.asMap().entries.map((entry) {
                final i = entry.key;
                final shift = entry.value;
                return Column(
                  children: [
                    if (i > 0)
                      const Divider(
                        height: 1,
                        color: AppColors.lightGrey2,
                        indent: 16,
                        endIndent: 16,
                      ),
                    Obx(() {
                      final isProcessing =
                          c.processingShiftId.value == shift.id;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.schedule_rounded,
                            color: AppColors.primaryColor,
                            size: 18,
                          ),
                        ),
                        title: CustomText(
                          text: shift.name,
                          fontSize: AppFontSize.verySmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.black2,
                        ),
                        subtitle: CustomText(
                          text: '${shift.startTime} – ${shift.endTime}',
                          fontSize: AppFontSize.tiny,
                          color: AppColors.iosGrey,
                        ),
                        trailing: isProcessing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primaryColor,
                                ),
                              )
                            : PopupMenuButton<String>(
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.iosGrey,
                                  size: 20,
                                ),
                                onSelected: (action) {
                                  switch (action) {
                                    case 'rename':
                                      _showRenameShiftDialog(context, shift);
                                      break;
                                    case 'delete':
                                      _confirmDeleteShift(context, shift);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: CustomText(
                                      text: 'Edit',
                                      fontSize: AppFontSize.verySmall,
                                      color: AppColors.black2,
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: CustomText(
                                      text: 'Delete',
                                      fontSize: AppFontSize.verySmall,
                                      color: AppColors.red,
                                    ),
                                  ),
                                ],
                              ),
                      );
                    }),
                  ],
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  void _showAddShiftSheet(BuildContext context) {
    Get.bottomSheet(
      _AddShiftSheet(c: c),
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  void _showRenameShiftDialog(BuildContext context, StoreShift shift) {
    final nameCtrl = TextEditingController(text: shift.name);
    final startCtrl = TextEditingController(text: shift.startTime);
    final endCtrl = TextEditingController(text: shift.endTime);
    CustomConfirmDialog.show(
      context,
      title: 'Edit Shift',
      confirmLabel: 'Save',
      contentBuilder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomTextField(
            controller: nameCtrl,
            hintText: 'Name',
            isborder: true,
            fillColor: AppColors.background,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: startCtrl,
                  hintText: 'Start',
                  isborder: true,
                  fillColor: AppColors.background,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CustomTextField(
                  controller: endCtrl,
                  hintText: 'End',
                  isborder: true,
                  fillColor: AppColors.background,
                ),
              ),
            ],
          ),
        ],
      ),
      onConfirm: () => c.updateShift(
        shift,
        name: nameCtrl.text.trim(),
        startTime: startCtrl.text.trim(),
        endTime: endCtrl.text.trim(),
      ),
    );
  }

  void _confirmDeleteShift(BuildContext context, StoreShift shift) {
    CustomConfirmDialog.show(
      context,
      title: 'Delete Shift',
      message: 'Delete "${shift.name}"?',
      confirmLabel: 'Delete',
      confirmColor: AppColors.red,
      onConfirm: () async {
        final ok = await c.deleteShift(shift);
        if (!ok && context.mounted) _confirmForceDeleteShift(context, shift);
      },
    );
  }

  void _confirmForceDeleteShift(BuildContext context, StoreShift shift) {
    CustomConfirmDialog.show(
      context,
      title: 'Employees Assigned',
      message:
          'This shift still has employees assigned. Unassign them and delete anyway?',
      confirmLabel: 'Force Delete',
      confirmColor: AppColors.red,
      onConfirm: () => c.deleteShift(shift, force: true),
    );
  }
}

class _AddShiftSheet extends StatelessWidget {
  final SellerPosManagementController c;
  const _AddShiftSheet({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'Add Shift',
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.black2,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: c.shiftNameCtrl,
            hintText: 'Shift Name (e.g. Morning)',
            fillColor: AppColors.background,
            prefixIcon: const Icon(
              Icons.label_outline_rounded,
              color: AppColors.iosGrey,
              size: 18,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CustomTextField(
                  controller: c.shiftStartCtrl,
                  hintText: 'Start (e.g. 08:00)',
                  fillColor: AppColors.background,
                  prefixIcon: const Icon(
                    Icons.login_rounded,
                    color: AppColors.iosGrey,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CustomTextField(
                  controller: c.shiftEndCtrl,
                  hintText: 'End (e.g. 16:00)',
                  fillColor: AppColors.background,
                  prefixIcon: const Icon(
                    Icons.logout_rounded,
                    color: AppColors.iosGrey,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(
            () => CustomButton(
              label: c.isSavingShift.value ? '' : 'Add Shift',
              width: double.infinity,
              height: 50,
              borderRadius: 12,
              enabled: !c.isSavingShift.value,
              onPressed: c.addShift,
              prefix: c.isSavingShift.value
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.white,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sessions section ──────────────────────────────────────────────────────────
class _SessionsSection extends StatelessWidget {
  final SellerPosManagementController c;
  const _SessionsSection({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const CustomText(
              text: 'Recent Sessions',
              fontFamily: AppTextStyles.headingFontFamily,
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.black2,
            ),
            const SizedBox(width: 8),
            Obx(() {
              final active = c.activeSessionCount;
              if (active == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.green2.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: CustomText(
                  text: '$active active',
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w600,
                  color: AppColors.green2,
                ),
              );
            }),
          ],
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (c.recentSessions.isEmpty) {
            return _EmptyCard(
              icon: Icons.history_rounded,
              message: 'No sessions yet.',
            );
          }
          final sessions = c.recentSessions.take(5).toList();
          return Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: sessions.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Column(
                  children: [
                    if (i > 0)
                      const Divider(
                        height: 1,
                        color: AppColors.lightGrey2,
                        indent: 16,
                        endIndent: 16,
                      ),
                    _SessionTile(session: s),
                  ],
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  final PosSessionModel session;
  const _SessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final isOpen = session.isOpen;
    final dateStr = DateFormat(
      'MMM d, h:mm a',
    ).format(session.openedAt.toLocal());

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isOpen ? AppColors.green2 : AppColors.iosGrey).withOpacity(
            0.1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isOpen ? Icons.lock_open_rounded : Icons.lock_rounded,
          color: isOpen ? AppColors.green2 : AppColors.iosGrey,
          size: 18,
        ),
      ),
      title: Row(
        children: [
          CustomText(
            text: 'Session',
            fontSize: AppFontSize.verySmall,
            fontWeight: FontWeight.w600,
            color: AppColors.black2,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isOpen
                  ? AppColors.green2.withOpacity(0.1)
                  : AppColors.lightGrey2,
              borderRadius: BorderRadius.circular(6),
            ),
            child: CustomText(
              text: isOpen ? 'Open' : 'Closed',
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: isOpen ? AppColors.green2 : AppColors.iosGrey,
            ),
          ),
        ],
      ),
      subtitle: CustomText(
        text: dateStr,
        fontSize: AppFontSize.tiny,
        color: AppColors.iosGrey,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CustomText(
            text: '\$${session.totalSales.toStringAsFixed(2)}',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
          CustomText(
            text: '${session.totalTransactions} txns',
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
        ],
      ),
    );
  }
}

// ── Shared empty state card ───────────────────────────────────────────────────
class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightGrey2),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.lightGrey2, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: CustomText(
              text: message,
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
          ),
        ],
      ),
    );
  }
}
