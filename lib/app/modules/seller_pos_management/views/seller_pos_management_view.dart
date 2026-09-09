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

// ── Responsive breakpoints ────────────────────────────────────────────────────
// This screen is used on phones as well as larger tablet / foldable / desktop
// windows, so layout decisions (columns, max content width) are derived from
// the available width rather than assuming a phone-sized viewport.
class _Bp {
  static const double tablet = 680;
  static const double desktop = 1080;
  static const double maxContent = 1180;
}

class SellerPosManagementView extends StatelessWidget {
  SellerPosManagementView({super.key});

  final SellerPosManagementController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
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
            showLeading: true,
            // actions: [
            //   _RefreshButton(c: c),
            //   const SizedBox(width: 6),
            // ],
          ),
        ),
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const SellerPosManagementShimmer();
        }
        return CustomRefreshWrapper(
          onRefresh: c.refreshData,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isTablet = width >= _Bp.tablet;
              final isDesktop = width >= _Bp.desktop;
              final hPad = isTablet ? 24.0 : AppDimen.allPadding;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _Bp.maxContent),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(hPad, 18, hPad, 28),
                    children: [
                      _OpenPosHeroCard(c: c, isWide: isTablet),
                      const SizedBox(height: 18),
                      _StatsRow(c: c, isWide: isTablet),
                      const SizedBox(height: 14),
                      const _ReportsLinksRow(),
                      const SizedBox(height: 26),
                      _ResponsiveSectionGrid(
                        isDesktop: isDesktop,
                        children: [
                          _EmployeesSection(c: c),
                          _RegistersSection(c: c),
                        ],
                      ),
                      const SizedBox(height: 22),
                      _ResponsiveSectionGrid(
                        isDesktop: isDesktop,
                        children: [
                          _ShiftsSection(c: c),
                          _SessionsSection(c: c),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      }),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  final SellerPosManagementController c;
  const _RefreshButton({required this.c});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryColor.withOpacity(0.1),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: c.refreshData,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            Icons.refresh_rounded,
            color: AppColors.primaryColor,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// A two-up section grid on wide screens, stacked single column on phones.
class _ResponsiveSectionGrid extends StatelessWidget {
  final bool isDesktop;
  final List<Widget> children;
  const _ResponsiveSectionGrid({
    required this.isDesktop,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDesktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [children[0], const SizedBox(height: 22), children[1]],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: children[0]),
        const SizedBox(width: 20),
        Expanded(child: children[1]),
      ],
    );
  }
}

// ── Open POS hero card ────────────────────────────────────────────────────────
// Wraps [child] in Expanded only in a horizontal Flex — the same child is
// used inside a vertical Flex on phones, where Expanded would demand an
// unbounded height and crash inside the scroll view.
class _MaybeExpanded extends StatelessWidget {
  final bool expand;
  final Widget child;
  const _MaybeExpanded({required this.expand, required this.child});

  @override
  Widget build(BuildContext context) {
    return expand ? Expanded(child: child) : child;
  }
}

class _OpenPosHeroCard extends StatelessWidget {
  final SellerPosManagementController c;
  final bool isWide;
  const _OpenPosHeroCard({required this.c, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isChecking = c.isCheckingPosAccess.value;
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(isWide ? 26 : 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryColor, AppColors.primaryColorLight2],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryColor.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Flex(
          direction: isWide ? Axis.horizontal : Axis.vertical,
          crossAxisAlignment: isWide
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: AppColors.white,
                size: 26,
              ),
            ),
            SizedBox(width: isWide ? 20 : 0, height: isWide ? 0 : 14),
            _MaybeExpanded(
              expand: isWide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CustomText(
                    text: 'Open POS Terminal',
                    fontSize: AppFontSize.medium,
                    fontWeight: FontWeight.bold,
                    color: AppColors.white,
                  ),
                  const SizedBox(height: 4),
                  CustomText(
                    text: 'Start a new sales session on this device',
                    fontSize: AppFontSize.tiny,
                    color: AppColors.white.withOpacity(0.85),
                  ),
                ],
              ),
            ),
            SizedBox(width: isWide ? 20 : 0, height: isWide ? 0 : 16),
            SizedBox(
              width: isWide ? null : double.infinity,
              child: Material(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: isChecking ? null : c.openPosTerminal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 22,
                    ),
                    child: isChecking
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.primaryColor,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CustomText(
                                text: 'Launch',
                                fontSize: AppFontSize.verySmall,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.arrow_forward_rounded,
                                color: AppColors.primaryColor,
                                size: 17,
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ── Stats row ────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final SellerPosManagementController c;
  final bool isWide;
  const _StatsRow({required this.c, required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Row(
        children: [
          Expanded(
            child: _StatCard(
              icon: Icons.people_alt_rounded,
              label: 'Employees',
              value: '${c.employees.length}',
              color: AppColors.primaryColor,
              isWide: isWide,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.point_of_sale_rounded,
              label: 'Registers',
              value: '${c.registers.length}',
              color: AppColors.orange,
              isWide: isWide,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _StatCard(
              icon: Icons.trending_up_rounded,
              label: "Today's Sales",
              value:
                  '\$${(c.dailyReport.value?.totalRevenue ?? 0).toStringAsFixed(0)}',
              color: AppColors.green2,
              isWide: isWide,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool isWide;
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.isWide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: isWide ? 20 : 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: isWide ? 20 : 18),
          ),
          SizedBox(height: isWide ? 12 : 8),
          CustomText(
            text: value,
            fontSize: isWide ? AppFontSize.small : AppFontSize.medium,
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

// ── Quick links row ────────────────────────────────────────────────────────────
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
            color: AppColors.primaryColor,
            onTap: () => Get.toNamed(Routes.posRangeReport),
          ),
        ),
        if (showAuditLog) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _LinkChip(
              icon: Icons.history_rounded,
              label: 'Activity Log',
              color: AppColors.orange,
              onTap: () => Get.toNamed(Routes.posAuditLog),
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: _LinkChip(
            icon: Icons.store_mall_directory_rounded,
            label: 'Locations',
            color: AppColors.green2,
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
  final Color color;
  final VoidCallback onTap;
  const _LinkChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.lightGrey2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 6),
              CustomText(
                text: label,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w600,
                color: AppColors.black2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.color,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        CustomText(
          text: title,
          fontFamily: AppTextStyles.headingFontFamily,
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          Material(
            color: AppColors.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
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
                      text: actionLabel!,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// Shared white rounded card wrapper used by every section list.
class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  const _SectionCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: children.asMap().entries.expand((entry) {
          final i = entry.key;
          return [
            if (i > 0)
              const Divider(
                height: 1,
                color: AppColors.lightGrey2,
                indent: 16,
                endIndent: 16,
              ),
            entry.value,
          ];
        }).toList(),
      ),
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
          icon: Icons.people_alt_rounded,
          color: AppColors.primaryColor,
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
          return _SectionCard(
            children: c.employees
                .map((emp) => _EmployeeTile(emp: emp, c: c))
                .toList(),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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

// ── Bottom sheet chrome shared by Add/Edit sheets ─────────────────────────────
Widget _sheetHandle() {
  return Container(
    width: 36,
    height: 4,
    decoration: BoxDecoration(
      color: AppColors.lightGrey2,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

Widget _sheetTitle(String text, IconData icon, Color color) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      const SizedBox(width: 10),
      CustomText(
        text: text,
        fontSize: AppFontSize.medium,
        fontWeight: FontWeight.bold,
        color: AppColors.black2,
      ),
    ],
  );
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: _sheetHandle()),
            const SizedBox(height: 16),
            _sheetTitle(
              'Add Employee',
              Icons.person_add_alt_1_rounded,
              AppColors.primaryColor,
            ),
            const SizedBox(height: 18),
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
            const SizedBox(height: 18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _sheetHandle()),
          const SizedBox(height: 16),
          _sheetTitle(
            'Edit Employee',
            Icons.edit_rounded,
            AppColors.primaryColor,
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
          icon: Icons.point_of_sale_rounded,
          color: AppColors.orange,
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
          return _SectionCard(
            children: c.registers
                .map((reg) => _RegisterTile(reg: reg, c: c))
                .toList(),
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
}

class _RegisterTile extends StatelessWidget {
  final StoreRegister reg;
  final SellerPosManagementController c;
  const _RegisterTile({required this.reg, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isProcessing = c.processingRegisterId.value == reg.id;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
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
        subtitle: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: reg.status == 'active'
                    ? AppColors.green2
                    : AppColors.iosGrey,
                shape: BoxShape.circle,
              ),
            ),
            CustomText(
              text: reg.status == 'active' ? 'Active' : 'Inactive',
              fontSize: AppFontSize.tiny,
              color: reg.status == 'active'
                  ? AppColors.green2
                  : AppColors.iosGrey,
            ),
          ],
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (action) {
                  switch (action) {
                    case 'rename':
                      _showRenameRegisterDialog(context, reg);
                      break;
                    case 'toggle':
                      c.updateRegister(
                        reg,
                        status: reg.status == 'active' ? 'inactive' : 'active',
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
                      text: reg.status == 'active' ? 'Deactivate' : 'Activate',
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
    });
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _sheetHandle()),
          const SizedBox(height: 16),
          _sheetTitle(
            'Add Register',
            Icons.point_of_sale_rounded,
            AppColors.orange,
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
          icon: Icons.schedule_rounded,
          color: AppColors.accentColor,
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
          return _SectionCard(
            children: c.shifts
                .map((shift) => _ShiftTile(shift: shift, c: c))
                .toList(),
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
}

class _ShiftTile extends StatelessWidget {
  final StoreShift shift;
  final SellerPosManagementController c;
  const _ShiftTile({required this.shift, required this.c});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isProcessing = c.processingShiftId.value == shift.id;
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.accentColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.schedule_rounded,
            color: AppColors.accentColor,
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
                  color: AppColors.accentColor,
                ),
              )
            : PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.iosGrey,
                  size: 20,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
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
    });
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: _sheetHandle()),
          const SizedBox(height: 16),
          _sheetTitle(
            'Add Shift',
            Icons.schedule_rounded,
            AppColors.accentColor,
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 18),
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
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.green2.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: AppColors.green2,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
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
          return _SectionCard(
            children: sessions.map((s) => _SessionTile(session: s)).toList(),
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
          borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.iosGrey, size: 20),
          ),
          const SizedBox(width: 12),
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
