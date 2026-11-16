import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/components/custom_confirm_dialog.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/modules/pos_plan/views/plan_expiry_banner.dart';
import 'package:solvexo_pos/app/modules/seller_pos_management/controllers/seller_pos_management_controller.dart';
import 'package:solvexo_pos/app/modules/seller_pos_management/widgets/seller_pos_management_shimmer.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

// ── Responsive breakpoints ────────────────────────────────────────────────────
// This screen is used on phones as well as larger tablet / foldable / desktop
// windows, so layout decisions (columns, max content width) are derived from
// the available width rather than assuming a phone-sized viewport.
class _Bp {
  static const double tablet = 680;
  static const double desktop = 1080;
  static const double maxContent = 1180;
}

/// True when the OS text scale is large enough that side-by-side figures or
/// buttons should stack (the design system's 1.3 rule).
bool _largeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 19;

class SellerPosManagementView extends StatelessWidget {
  SellerPosManagementView({super.key});

  final SellerPosManagementController c = Get.find();

  @override
  Widget build(BuildContext context) {
    // This screen is always reached via Get.offAllNamed (from the store
    // picker or right after onboarding creates a store); the app bar keeps
    // the platform's default leading behaviour, as before.
    return Obx(
      () => AppPage(
        title: c.storeName.value.isEmpty ? 'POS Management' : c.storeName.value,
        maxWidth: _Bp.maxContent,
        body: Obx(() {
          if (c.isLoading.value) {
            return const SellerPosManagementShimmer();
          }
          return RefreshIndicator(
            onRefresh: c.refreshData,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final isTablet = width >= _Bp.tablet;
                final isDesktop = width >= _Bp.desktop;
                final hPad = isTablet ? Space.s6 : Space.s4;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(hPad, Space.s4, hPad, Space.s8),
                  children: [
                    PlanExpiryBanner(status: c.planStatus.value, onTap: () => Get.toNamed(Routes.posPlanStatus)),
                    _OpenPosHeroCard(c: c, isWide: isTablet),
                    const SizedBox(height: Space.s4),
                    _StatsRow(c: c, isWide: isTablet),
                    const SizedBox(height: Space.s3),
                    const _ReportsLinksRow(),
                    const SizedBox(height: Space.s6),
                    _ResponsiveSectionGrid(
                      isDesktop: isDesktop,
                      children: [
                        _EmployeesSection(c: c),
                        _RegistersSection(c: c),
                      ],
                    ),
                    const SizedBox(height: Space.s5),
                    _ResponsiveSectionGrid(
                      isDesktop: isDesktop,
                      children: [
                        _ShiftsSection(c: c),
                        _SessionsSection(c: c),
                      ],
                    ),
                  ],
                );
              },
            ),
          );
        }),
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
        children: [children[0], const SizedBox(height: Space.s5), children[1]],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: children[0]),
        const SizedBox(width: Space.s5),
        Expanded(child: children[1]),
      ],
    );
  }
}

// ── Open POS launch card ──────────────────────────────────────────────────────
class _OpenPosHeroCard extends StatelessWidget {
  final SellerPosManagementController c;
  final bool isWide;
  const _OpenPosHeroCard({required this.c, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final horizontal = isWide && !_largeText(context);
    return Obx(() {
      final isChecking = c.isCheckingPosAccess.value;
      final icon = Container(
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(color: p.accentSoft, borderRadius: Radii.rMd),
        child: Icon(Icons.point_of_sale_rounded, color: p.accentFg, size: IconSizes.lg),
      );
      final texts = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Open POS Terminal', style: t.title.copyWith(color: p.textPrimary)),
          const SizedBox(height: Space.s1),
          Text(
            'Start a new sales session on this device',
            style: t.bodySmall.copyWith(color: p.textSecondary),
          ),
        ],
      );
      final button = AppButton(
        label: 'Launch',
        icon: Icons.arrow_forward_rounded,
        loading: isChecking,
        expand: !horizontal,
        onPressed: isChecking ? null : c.openPosTerminal,
      );
      return AppCard(
        raised: true,
        padding: EdgeInsets.all(isWide ? Space.s6 : Space.s5),
        child: horizontal
            ? Row(
                children: [
                  icon,
                  const SizedBox(width: Space.s5),
                  Expanded(child: texts),
                  const SizedBox(width: Space.s5),
                  button,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(height: Space.s3),
                  texts,
                  const SizedBox(height: Space.s4),
                  button,
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

  static String _count(double v) => '${v.round()}';

  @override
  Widget build(BuildContext context) {
    final large = _largeText(context);
    return Obx(() {
      final employees = StatTile(
        icon: Icons.people_alt_rounded,
        label: 'Employees',
        value: c.employees.length.toDouble(),
        formatter: _count,
      );
      final registers = StatTile(
        icon: Icons.point_of_sale_rounded,
        label: 'Registers',
        value: c.registers.length.toDouble(),
        formatter: _count,
      );
      final sales = StatTile(
        icon: Icons.trending_up_rounded,
        label: "Today's Sales",
        value: (c.dailyReport.value?.totalRevenue ?? 0).toDouble(),
        formatter: (v) => Money.format(v),
      );
      if (large) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [employees, const SizedBox(height: Space.s2), registers, const SizedBox(height: Space.s2), sales],
        );
      }
      if (isWide) {
        return Row(
          children: [
            Expanded(child: employees),
            const SizedBox(width: Space.s2),
            Expanded(child: registers),
            const SizedBox(width: Space.s2),
            Expanded(child: sales),
          ],
        );
      }
      // Phones: two counts side by side, the money figure full width so it
      // never has to shrink.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: employees),
              const SizedBox(width: Space.s2),
              Expanded(child: registers),
            ],
          ),
          const SizedBox(height: Space.s2),
          sales,
        ],
      );
    });
  }
}

// ── Quick links row ────────────────────────────────────────────────────────────
class _ReportsLinksRow extends StatelessWidget {
  const _ReportsLinksRow();

  @override
  Widget build(BuildContext context) {
    const showAuditLog = true;
    final links = <_LinkChip>[
      _LinkChip(
        icon: Icons.bar_chart_rounded,
        label: 'Reports',
        onTap: () => Get.toNamed(Routes.posRangeReport),
      ),
      if (showAuditLog)
        _LinkChip(
          icon: Icons.history_rounded,
          label: 'Activity Log',
          onTap: () => Get.toNamed(Routes.posAuditLog),
        ),
      _LinkChip(
        icon: Icons.store_mall_directory_rounded,
        label: 'Locations',
        onTap: () => Get.toNamed(Routes.sellerPosLocations),
      ),
    ];
    if (_largeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < links.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            AppListRow(icon: links[i].icon, title: links[i].label, onTap: links[i].onTap),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < links.length; i++) ...[
          if (i > 0) const SizedBox(width: Space.s2),
          Expanded(child: links[i]),
        ],
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
    final p = context.palette;
    return AppCard(
      onTap: onTap,
      semanticLabel: label,
      radius: Radii.rMd,
      padding: const EdgeInsets.symmetric(vertical: Space.s3, horizontal: Space.s2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.minTouch - Space.s3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: IconSizes.sm, color: p.accentFg),
            const SizedBox(height: Space.s1),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.type.label.copyWith(color: p.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared row pieces ─────────────────────────────────────────────────────────

/// One entry in a section list: a leading tile, title (+ optional badge),
/// subtitle and a trailing widget (menu, spinner or figures), on an AppCard.
class _ManageRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget? titleBadge;
  final String? subtitle;
  final Widget? trailing;
  const _ManageRow({
    required this.leading,
    required this.title,
    this.titleBadge,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s2, Space.s2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.minTouch),
        child: Row(
          children: [
            leading,
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(title, style: t.subtitle.copyWith(color: p.textPrimary)),
                      ?titleBadge,
                    ],
                  ),
                  if (subtitle != null)
                    Text(subtitle!, style: t.bodySmall.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.s2), trailing!],
          ],
        ),
      ),
    );
  }
}

/// The 40 dp icon tile used at the start of a row.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final bool muted;
  const _IconTile(this.icon, {this.muted = false});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: muted ? p.fill : p.accentSoft, borderRadius: Radii.rMd),
      child: Icon(icon, size: IconSizes.md, color: muted ? p.textSecondary : p.accentFg),
    );
  }
}

/// A small spinner in a 48 dp slot, shown while a row's action runs.
class _RowSpinner extends StatelessWidget {
  final Color color;
  const _RowSpinner({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: Space.minTouch,
      height: Space.minTouch,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        ),
      ),
    );
  }
}

/// A menu entry: (value, label, destructive).
typedef _MenuEntry = (String value, String label, bool danger);

/// The "more" menu at the end of a row.
class _RowMenu extends StatelessWidget {
  final List<_MenuEntry> entries;
  final ValueChanged<String> onSelected;
  const _RowMenu({required this.entries, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: p.textSecondary, size: IconSizes.sm),
      color: p.surface,
      shape: RoundedRectangleBorder(borderRadius: Radii.rMd),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (value, label, danger) in entries)
          PopupMenuItem(
            value: value,
            child: Text(
              label,
              style: context.type.body.copyWith(color: danger ? p.dangerFg : p.textPrimary),
            ),
          ),
      ],
    );
  }
}

/// A list of rows with the standard gap between them.
class _RowList extends StatelessWidget {
  final List<Widget> children;
  const _RowList({required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Space.s2),
          children[i],
        ],
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
        SectionHeader(
          'Employees',
          actionLabel: 'Add',
          onAction: () => _showAddEmployeeSheet(context),
        ),
        Obx(() {
          if (c.employees.isEmpty) {
            return const _EmptyCard(
              icon: Icons.person_add_outlined,
              message: 'No employees yet. Add one to get started.',
            );
          }
          return _RowList(
            children: c.employees
                .map((emp) => _EmployeeTile(emp: emp, c: c))
                .toList(),
          );
        }),
      ],
    );
  }

  void _showAddEmployeeSheet(BuildContext context) {
    AppBottomSheet.showGet(_AddEmployeeSheet(c: c), title: 'Add Employee');
  }
}

class _EmployeeTile extends StatelessWidget {
  final PosEmployeeModel emp;
  final SellerPosManagementController c;
  const _EmployeeTile({required this.emp, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final isDeleting = c.deletingEmployeeId.value == emp.id;
      return _ManageRow(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: p.accentSoft,
          child: Text(emp.initials, style: context.type.label.copyWith(color: p.accentFg)),
        ),
        title: emp.name,
        subtitle: '${emp.role.capitalizeFirst ?? emp.role}  ·  ${emp.email}',
        trailing: isDeleting
            ? _RowSpinner(color: p.dangerFg)
            : _RowMenu(
                entries: const [
                  ('edit', 'Edit', false),
                  ('reset_pin', 'Reset PIN', false),
                  ('remove', 'Remove', true),
                ],
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
              ),
      );
    });
  }

  void _showEditEmployeeSheet(BuildContext context, PosEmployeeModel emp) {
    AppBottomSheet.showGet(_EditEmployeeSheet(c: c, emp: emp), title: 'Edit Employee');
  }

  void _showResetPinDialog(BuildContext context, PosEmployeeModel emp) {
    final ctrl = TextEditingController();
    CustomConfirmDialog.show(
      context,
      title: 'Reset PIN',
      confirmLabel: 'Reset',
      contentBuilder: (_) => AppTextField(
        label: 'New 4-digit PIN',
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [LengthLimitingTextInputFormatter(4)],
        obscureText: true,
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
      destructive: true,
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
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Full Name',
          controller: c.empNameCtrl,
          prefixIcon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          label: 'Email Address',
          controller: c.empEmailCtrl,
          keyboardType: TextInputType.emailAddress,
          prefixIcon: Icons.email_outlined,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          label: '4-Digit PIN',
          controller: c.empPinCtrl,
          keyboardType: TextInputType.number,
          inputFormatters: [LengthLimitingTextInputFormatter(4)],
          obscureText: true,
          prefixIcon: Icons.pin_outlined,
        ),
        const SizedBox(height: Space.s3),
        // Role picker
        Obx(
          () => DropdownButtonFormField<String>(
            initialValue: c.empRole.value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Role'),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
            dropdownColor: p.surface,
            onChanged: (v) {
              if (v != null) c.empRole.value = v;
            },
            items: _roles
                .map(
                  (r) => DropdownMenuItem(
                    value: r,
                    child: Text(r.capitalizeFirst ?? r, style: t.body.copyWith(color: p.textPrimary)),
                  ),
                )
                .toList(),
          ),
        ),
        // Shift picker
        Obx(
          () => c.shifts.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: DropdownButtonFormField<String>(
                    initialValue: c.empShiftId.value.isNotEmpty ? c.empShiftId.value : null,
                    hint: Text('Assign Shift (optional)', style: t.body.copyWith(color: p.textMuted)),
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
                    dropdownColor: p.surface,
                    onChanged: (v) {
                      if (v != null) c.empShiftId.value = v;
                    },
                    items: c.shifts
                        .map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.name, style: t.body.copyWith(color: p.textPrimary)),
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
        const SizedBox(height: Space.s5),
        Obx(
          () => AppButton(
            label: 'Add Employee',
            loading: c.isSavingEmployee.value,
            onPressed: c.isSavingEmployee.value ? null : c.addEmployee,
          ),
        ),
      ],
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
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Full Name',
          controller: _nameCtrl,
          prefixIcon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: Space.s3),
        DropdownButtonFormField<String>(
          initialValue: _role,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Role'),
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: p.textSecondary),
          dropdownColor: p.surface,
          onChanged: (v) {
            if (v != null) setState(() => _role = v);
          },
          items: _roles
              .map(
                (r) => DropdownMenuItem(
                  value: r,
                  child: Text(r.capitalizeFirst ?? r, style: t.body.copyWith(color: p.textPrimary)),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: Space.s5),
        AppButton(
          label: 'Save Changes',
          loading: _saving,
          onPressed: _saving
              ? null
              : () async {
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
        SectionHeader(
          'Registers',
          actionLabel: 'Add',
          onAction: () => _showAddRegisterSheet(context),
        ),
        Obx(() {
          if (c.registers.isEmpty) {
            return const _EmptyCard(
              icon: Icons.point_of_sale_outlined,
              message: 'No registers. Add one to start processing sales.',
            );
          }
          return _RowList(
            children: c.registers
                .map((reg) => _RegisterTile(reg: reg, c: c))
                .toList(),
          );
        }),
      ],
    );
  }

  void _showAddRegisterSheet(BuildContext context) {
    AppBottomSheet.showGet(_AddRegisterSheet(c: c), title: 'Add Register');
  }
}

class _RegisterTile extends StatelessWidget {
  final StoreRegister reg;
  final SellerPosManagementController c;
  const _RegisterTile({required this.reg, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final isProcessing = c.processingRegisterId.value == reg.id;
      final active = reg.status == 'active';
      return _ManageRow(
        leading: _IconTile(Icons.point_of_sale_rounded, muted: !active),
        title: reg.name,
        titleBadge: StatusBadge(
          active ? 'Active' : 'Inactive',
          tone: active ? StatusTone.success : StatusTone.neutral,
          dot: true,
        ),
        trailing: isProcessing
            ? _RowSpinner(color: p.accentFg)
            : _RowMenu(
                entries: [
                  ('rename', 'Rename', false),
                  ('toggle', active ? 'Deactivate' : 'Activate', false),
                  ('delete', 'Delete', true),
                ],
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
      contentBuilder: (_) => AppTextField(
        label: 'Register Name',
        controller: ctrl,
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
      destructive: true,
      onConfirm: () => c.deleteRegister(reg),
    );
  }
}

class _AddRegisterSheet extends StatelessWidget {
  final SellerPosManagementController c;
  const _AddRegisterSheet({required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Register Name',
          hint: 'e.g. Counter 1',
          controller: c.regNameCtrl,
          prefixIcon: Icons.point_of_sale_outlined,
        ),
        const SizedBox(height: Space.s5),
        Obx(
          () => AppButton(
            label: 'Add Register',
            loading: c.isSavingRegister.value,
            onPressed: c.isSavingRegister.value ? null : c.addRegister,
          ),
        ),
      ],
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
        SectionHeader(
          'Shifts',
          actionLabel: 'Add',
          onAction: () => _showAddShiftSheet(context),
        ),
        Obx(() {
          if (c.shifts.isEmpty) {
            return const _EmptyCard(
              icon: Icons.schedule_outlined,
              message: 'No shifts defined. Add shifts to assign to employees.',
            );
          }
          return _RowList(
            children: c.shifts
                .map((shift) => _ShiftTile(shift: shift, c: c))
                .toList(),
          );
        }),
      ],
    );
  }

  void _showAddShiftSheet(BuildContext context) {
    AppBottomSheet.showGet(_AddShiftSheet(c: c), title: 'Add Shift');
  }
}

class _ShiftTile extends StatelessWidget {
  final StoreShift shift;
  final SellerPosManagementController c;
  const _ShiftTile({required this.shift, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      final isProcessing = c.processingShiftId.value == shift.id;
      return _ManageRow(
        leading: const _IconTile(Icons.schedule_rounded),
        title: shift.name,
        subtitle: '${shift.startTime} – ${shift.endTime}',
        trailing: isProcessing
            ? _RowSpinner(color: p.accentFg)
            : _RowMenu(
                entries: const [
                  ('rename', 'Edit', false),
                  ('delete', 'Delete', true),
                ],
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
      contentBuilder: (ctx) {
        final start = AppTextField(label: 'Start', controller: startCtrl);
        final end = AppTextField(label: 'End', controller: endCtrl);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Name', controller: nameCtrl),
            const SizedBox(height: Space.s3),
            if (_largeText(ctx)) ...[
              start,
              const SizedBox(height: Space.s3),
              end,
            ] else
              Row(
                children: [
                  Expanded(child: start),
                  const SizedBox(width: Space.s2),
                  Expanded(child: end),
                ],
              ),
          ],
        );
      },
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
      destructive: true,
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
      destructive: true,
      onConfirm: () => c.deleteShift(shift, force: true),
    );
  }
}

class _AddShiftSheet extends StatelessWidget {
  final SellerPosManagementController c;
  const _AddShiftSheet({required this.c});

  @override
  Widget build(BuildContext context) {
    final start = AppTextField(
      label: 'Start',
      hint: 'e.g. 08:00',
      controller: c.shiftStartCtrl,
      prefixIcon: Icons.login_rounded,
    );
    final end = AppTextField(
      label: 'End',
      hint: 'e.g. 16:00',
      controller: c.shiftEndCtrl,
      prefixIcon: Icons.logout_rounded,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Shift Name',
          hint: 'e.g. Morning',
          controller: c.shiftNameCtrl,
          prefixIcon: Icons.label_outline_rounded,
        ),
        const SizedBox(height: Space.s3),
        if (_largeText(context)) ...[
          start,
          const SizedBox(height: Space.s3),
          end,
        ] else
          Row(
            children: [
              Expanded(child: start),
              const SizedBox(width: Space.s3),
              Expanded(child: end),
            ],
          ),
        const SizedBox(height: Space.s5),
        Obx(
          () => AppButton(
            label: 'Add Shift',
            loading: c.isSavingShift.value,
            onPressed: c.isSavingShift.value ? null : c.addShift,
          ),
        ),
      ],
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
        Padding(
          padding: const EdgeInsets.only(bottom: Space.s3),
          child: Row(
            children: [
              const Flexible(child: SectionHeader('Recent Sessions', padding: EdgeInsets.zero)),
              Obx(() {
                final active = c.activeSessionCount;
                if (active == 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: Space.s2),
                  child: StatusBadge('$active active', tone: StatusTone.success),
                );
              }),
            ],
          ),
        ),
        Obx(() {
          if (c.recentSessions.isEmpty) {
            return const _EmptyCard(
              icon: Icons.history_rounded,
              message: 'No sessions yet.',
            );
          }
          final sessions = c.recentSessions.take(5).toList();
          return _RowList(
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
    final p = context.palette;
    final isOpen = session.isOpen;
    final dateStr = DateFormat(
      'MMM d, h:mm a',
    ).format(session.openedAt.toLocal());

    return _ManageRow(
      leading: _IconTile(isOpen ? Icons.lock_open_rounded : Icons.lock_rounded, muted: !isOpen),
      title: 'Session',
      titleBadge: StatusBadge(
        isOpen ? 'Open' : 'Closed',
        tone: isOpen ? StatusTone.success : StatusTone.neutral,
      ),
      subtitle: dateStr,
      trailing: Padding(
        padding: const EdgeInsets.only(right: Space.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            AmountText(
              Money.format(session.totalSales),
              style: context.type.amountMd,
              color: p.textPrimary,
              animate: false,
            ),
            Text(
              '${session.totalTransactions} txns',
              style: context.type.caption.copyWith(color: p.textSecondary),
            ),
          ],
        ),
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
    final p = context.palette;
    return AppCard(
      child: Row(
        children: [
          _IconTile(icon, muted: true),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text(message, style: context.type.bodySmall.copyWith(color: p.textSecondary)),
          ),
        ],
      ),
    );
  }
}
