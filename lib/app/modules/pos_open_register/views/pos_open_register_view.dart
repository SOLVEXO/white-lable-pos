import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class PosOpenRegisterView extends StatelessWidget {
  PosOpenRegisterView({super.key});

  final PosOpenRegisterController c = Get.find();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(Space.s6, Space.s4, Space.s6, Space.s4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Back ──────────────────────────────────────────────
                        Material(
                          color: p.surface,
                          shape: RoundedRectangleBorder(borderRadius: Radii.rSm, side: BorderSide(color: p.border)),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => Get.back(),
                            child: SizedBox(
                              width: Space.minTouch,
                              height: Space.minTouch,
                              child: Semantics(
                                button: true,
                                label: 'Back',
                                child: Icon(Icons.arrow_back_ios_new_rounded, color: p.textPrimary, size: IconSizes.xs),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.s6),

                        // ── Header ────────────────────────────────────────────
                        Semantics(
                          header: true,
                          child: Text('Open Register', style: t.headline.copyWith(color: p.textPrimary)),
                        ),
                        const SizedBox(height: Space.s2),
                        Text('Starting shift on ${c.registerName}', style: t.bodySmall.copyWith(color: p.textSecondary)),
                        const SizedBox(height: Space.s8),

                        // ── Employee card ──────────────────────────────────────
                        _InfoCard(
                          icon: Icons.person_outline_rounded,
                          label: 'Employee',
                          value: c.employee.name,
                          sub: c.employee.role.capitalizeFirst ?? c.employee.role,
                        ),
                        const SizedBox(height: Space.s3),
                        _InfoCard(
                          icon: Icons.point_of_sale_outlined,
                          label: 'Register',
                          value: c.registerName,
                          sub: 'Shift: ${c.shiftId.isEmpty ? "Not assigned" : "Assigned"}',
                        ),
                        // ── G4.6: how the last shift on this register closed ───
                        Obx(
                          () => c.lastClose.value == null
                              ? const SizedBox.shrink()
                              : Padding(padding: const EdgeInsets.only(top: Space.s3), child: _LastCloseCard(c: c)),
                        ),
                        const SizedBox(height: Space.s6),

                        // ── Opening cash ───────────────────────────────────────
                        Text('Opening Float (Cash in Drawer)', style: t.label.copyWith(color: p.textPrimary)),
                        const SizedBox(height: Space.s3),
                        // the store's currency (known once the last close is read), not a fixed symbol
                        Obx(
                          () => AppTextField(
                            label: 'Amount (${Money.symbol(c.currency)})',
                            controller: c.openingCashController,
                            hint: '0.00',
                            mono: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                        const SizedBox(height: Space.s2),
                        Text('Enter 0 if starting with an empty drawer.', style: t.caption.copyWith(color: p.textSecondary)),
                        // G4.6: count it note by note (the server checks the notes add up to the float)
                        Obx(
                          () => !c.canCount
                              ? const SizedBox.shrink()
                              : Padding(
                                  padding: const EdgeInsets.only(top: Space.s2),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: AppButton(
                                      key: const Key('countFloat'),
                                      variant: AppButtonVariant.ghost,
                                      expand: false,
                                      icon: Icons.calculate_outlined,
                                      label: c.denominations.isEmpty
                                          ? 'Count notes & coins'
                                          : 'Counted ${c.denominations.fold<int>(0, (n, d) => n + d.count)} notes & coins · edit',
                                      onPressed: c.countFloat,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Open button ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.s6, Space.s2, Space.s6, Space.s4),
                  child: Obx(
                    () => AppButton(
                      label: c.isOpening.value ? 'Opening...' : 'Open Register & Start Shift',
                      size: AppButtonSize.lg,
                      loading: c.isOpening.value,
                      onPressed: c.isOpening.value ? null : c.openRegister,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The last close of this register: counted, expected and the difference, by whom and when (a forced close says so).
class _LastCloseCard extends StatelessWidget {
  const _LastCloseCard({required this.c});
  final PosOpenRegisterController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final l = c.lastClose.value!;
    String m(int? v) => v == null ? '—' : Money.format(Money.fromMinor(v, l.exponent), currency: l.currency, exponent: l.exponent);
    final v = l.varianceMinor ?? 0;
    final when = l.closedAt == null ? '' : DateFormat('d MMM, HH:mm').format(l.closedAt!);
    final tone = v == 0 ? p.successFg : (v < 0 ? p.dangerFg : p.warningFg);
    final figures = Text('Counted ${m(l.countedMinor)}  ·  Expected ${m(l.expectedMinor)}', style: t.bodySmall.copyWith(color: p.textPrimary));
    final variance = Text(
      key: const Key('lastCloseVariance'),
      v == 0 ? 'Matched' : '${v < 0 ? 'Short' : 'Over'} ${m(v.abs())}',
      style: t.bodySmall.copyWith(color: tone, fontWeight: FontWeight.w700),
    );
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    return Container(
      key: const Key('lastCloseCard'),
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: v == 0 ? p.border : (v < 0 ? p.danger : p.warning)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last close${l.forced ? ' (forced)' : ''}${l.closedByName != null ? ' · ${l.closedByName}' : ''}${when.isEmpty ? '' : ' · $when'}',
            style: t.caption.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: Space.s2),
          if (stack) ...[figures, const SizedBox(height: Space.s1), variance] else Row(children: [Expanded(child: figures), const SizedBox(width: Space.s2), variance]),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;

  const _InfoCard({required this.icon, required this.label, required this.value, required this.sub});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.accentSoft, borderRadius: Radii.rMd),
            child: Icon(icon, color: p.accentFg, size: IconSizes.sm),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.caption.copyWith(color: p.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: t.subtitle.copyWith(color: p.textPrimary)),
                Text(sub, style: t.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
