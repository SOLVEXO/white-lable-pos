import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingBottomBar extends StatelessWidget {
  final SellerOnboardingController controller;

  const OnboardingBottomBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final p = context.palette;
    return Obx(() {
      final showBack = !controller.isFirstStep && !controller.isLastStep;
      final canProceed = controller.canProceed;
      final isSaving = controller.isSaving.value;
      final label = controller.primaryButtonLabel;
      final isLast = controller.isLastStep;

      return Container(
        padding: EdgeInsets.fromLTRB(
          Space.s4,
          Space.s3,
          Space.s4,
          Space.s3 + bottomInset,
        ),
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border)),
          boxShadow: context.softShadow,
        ),
        child: Row(
          children: [
            if (showBack) ...[
              AppButton(
                label: 'Back',
                icon: Icons.arrow_back_rounded,
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.lg,
                expand: false,
                onPressed: controller.goBack,
              ),
              const SizedBox(width: Space.s3),
            ],
            Expanded(
              child: AppButton(
                label: label,
                size: AppButtonSize.lg,
                loading: isSaving,
                icon: canProceed
                    ? (isLast
                          ? Icons.dashboard_rounded
                          : Icons.arrow_forward_rounded)
                    : null,
                onPressed: canProceed
                    ? (isLast ? controller.complete : controller.goNext)
                    : null,
              ),
            ),
          ],
        ),
      );
    });
  }
}
