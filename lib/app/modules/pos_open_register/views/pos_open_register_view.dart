import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/pos_open_register/controllers/pos_open_register_controller.dart';
import 'package:solvexo_pos/app/modules/pos_pin_login/views/pos_pin_login_view.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
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
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 14, right: 8),
                  child: CustomText(
                    text: '\$',
                    fontSize: AppFontSize.medium,
                    fontWeight: FontWeight.bold,
                    color: kPinOrange,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const CustomText(
                text: 'Enter 0 if starting with an empty drawer.',
                fontSize: AppFontSize.tiny,
                color: kPinSub,
              ),

              const Spacer(),

              // ── Open button ────────────────────────────────────────
              Obx(
                () => AppButton(
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
              color: kPinOrange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: kPinOrange, size: 20),
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
