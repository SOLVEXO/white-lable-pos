import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingBottomBar extends StatelessWidget {
  final SellerOnboardingController controller;

  const OnboardingBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Obx(() {
      final showBack = !controller.isFirstStep && !controller.isLastStep;
      final canProceed = controller.canProceed;
      final isSaving = controller.isSaving.value;
      final label = controller.primaryButtonLabel;

      return Container(
        padding: EdgeInsets.fromLTRB(
          AppDimen.allPadding,
          12,
          AppDimen.allPadding,
          12 + bottomInset,
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            if (showBack) ...[
              _BackBtn(onTap: controller.goBack),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: _PrimaryBtn(
                label: label,
                isEnabled: canProceed,
                isLoading: isSaving,
                isLast: controller.isLastStep,
                onTap: controller.isLastStep ? controller.complete : controller.goNext,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _BackBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _BackBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
          border: Border.all(color: AppColors.lightGrey2),
        ),
        alignment: Alignment.center,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_rounded, size: 17, color: AppColors.black2),
            SizedBox(width: 6),
            CustomText(
              text: 'Back',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.black2,
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final bool isEnabled;
  final bool isLoading;
  final bool isLast;
  final VoidCallback onTap;

  const _PrimaryBtn({
    required this.label,
    required this.isEnabled,
    required this.isLoading,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEnabled && !isLoading ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: isEnabled
              ? AppColors.primaryColor
              : AppColors.primaryColor.withOpacity(0.38),
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
        ),
        alignment: Alignment.center,
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.white,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomText(
                    text: label,
                    fontSize: AppFontSize.small2,
                    fontWeight: FontWeight.w600,
                    color: AppColors.white,
                  ),
                  if (isEnabled) ...[
                    const SizedBox(width: 8),
                    Icon(
                      isLast ? Icons.dashboard_rounded : Icons.arrow_forward_rounded,
                      size: 17,
                      color: AppColors.white,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
