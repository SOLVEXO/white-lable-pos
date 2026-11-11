import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/views/pos_pin_login_view.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:get/get.dart';

class PosOpenRegisterView extends StatelessWidget {
  PosOpenRegisterView({super.key});

  final PosOpenRegisterController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPinBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Back ──────────────────────────────────────────────
              GestureDetector(
                onTap: () => Get.back(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kPinSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kPinBorder),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: kPinText,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // ── Header ────────────────────────────────────────────
              const CustomText(
                text: 'Open Register',
                fontSize: AppFontSize.veryLarge,
                fontWeight: FontWeight.bold,
                color: kPinText,
              ),
              const SizedBox(height: 8),
              CustomText(
                text: 'Starting shift on ${c.registerName}',
                fontSize: AppFontSize.verySmall,
                color: kPinSub,
              ),
              const SizedBox(height: 32),

              // ── Employee card ──────────────────────────────────────
              _InfoCard(
                icon: Icons.person_outline_rounded,
                label: 'Employee',
                value: c.employee.name,
                sub: c.employee.role.capitalizeFirst ?? c.employee.role,
              ),
              const SizedBox(height: 12),
              _InfoCard(
                icon: Icons.point_of_sale_outlined,
                label: 'Register',
                value: c.registerName,
                sub:
                    'Shift: ${c.shiftId.isEmpty ? "Not assigned" : "Assigned"}',
              ),
              // ── G4.6: how the last shift on this register closed ───
              Obx(() => c.lastClose.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 12), child: _LastCloseCard(c: c))),
              const SizedBox(height: 28),

              // ── Opening cash ───────────────────────────────────────
              const CustomText(
                text: 'Opening Float (Cash in Drawer)',
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.w600,
                color: kPinText,
              ),
              const SizedBox(height: 10),
              CustomTextField(
                controller: c.openingCashController,
                hintText: '0.00',
                textColor: AppColors.white,
                borderRadius: BorderRadius.circular(AppDimen.borderRadius),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                fillColor: kPinSurface,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: CustomText(
                    text: '\$',
                    fontSize: AppFontSize.medium,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const CustomText(
                text: 'Enter 0 if starting with an empty drawer.',
                fontSize: AppFontSize.tiny,
                color: kPinSub,
              ),
              // G4.6: count it note by note (the server checks the notes add up to the float)
              Obx(
                () => !c.canCount
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const Key('countFloat'),
                          onPressed: c.countFloat,
                          icon: Icon(Icons.calculate_outlined, size: 18, color: AppColors.primaryColor),
                          label: CustomText(
                            text: c.denominations.isEmpty ? 'Count notes & coins' : 'Counted ${c.denominations.fold<int>(0, (n, d) => n + d.count)} notes & coins · edit',
                            fontSize: AppFontSize.verySmall,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      ),
              ),

              const Spacer(),

              // ── Open button ────────────────────────────────────────
              Obx(
                () => LegacyAppButton(
                  label: c.isOpening.value
                      ? 'Opening...'
                      : 'Open Register & Start Shift',
                  onPressed: c.isOpening.value ? null : c.openRegister,
                ),
              ),
              const SizedBox(height: AppDimen.allPadding),
            ],
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
    final l = c.lastClose.value!;
    String m(int? v) => v == null ? '—' : Money.format(Money.fromMinor(v, l.exponent), currency: l.currency, exponent: l.exponent);
    final v = l.varianceMinor ?? 0;
    final when = l.closedAt == null ? '' : DateFormat('d MMM, HH:mm').format(l.closedAt!);
    return Container(
      key: const Key('lastCloseCard'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPinSurface,
        borderRadius: BorderRadius.circular(AppDimen.borderRadius),
        border: Border.all(color: v == 0 ? kPinBorder : (v < 0 ? AppColors.red : AppColors.orange)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(text: 'Last close${l.forced ? ' (forced)' : ''}${l.closedByName != null ? ' · ${l.closedByName}' : ''}${when.isEmpty ? '' : ' · $when'}', fontSize: AppFontSize.tiny, color: kPinSub),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: CustomText(text: 'Counted ${m(l.countedMinor)}  ·  Expected ${m(l.expectedMinor)}', fontSize: AppFontSize.verySmall, color: kPinText)),
              CustomText(
                key: const Key('lastCloseVariance'),
                text: v == 0 ? 'Matched' : '${v < 0 ? 'Short' : 'Over'} ${m(v.abs())}',
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.bold,
                color: v == 0 ? AppColors.green2 : (v < 0 ? AppColors.red : AppColors.orange),
              ),
            ],
          ),
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

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPinSurface,
        borderRadius: BorderRadius.circular(AppDimen.borderRadius),
        border: Border.all(color: kPinBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primaryColor, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomText(
                text: label,
                fontSize: AppFontSize.tiny,
                color: kPinSub,
              ),
              const SizedBox(height: 3),
              CustomText(
                text: value,
                fontSize: AppFontSize.verySmall,
                fontWeight: FontWeight.bold,
                color: kPinText,
              ),
              CustomText(text: sub, fontSize: AppFontSize.tiny, color: kPinSub),
            ],
          ),
        ],
      ),
    );
  }
}
