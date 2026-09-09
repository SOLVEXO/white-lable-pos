import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingStepBar extends StatelessWidget {
  final SellerOnboardingController controller;

  const OnboardingStepBar({super.key, required this.controller});

  static const _labels = ['Store Info', 'Seller Type', 'Go Live'];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Obx(
        () => Row(
          children: List.generate(_labels.length * 2 - 1, (i) {
            if (i.isOdd) return _connector(i ~/ 2, controller.step.value);
            final index = i ~/ 2;
            return _StepNode(
              index: index,
              label: _labels[index],
              currentStep: controller.step.value,
            );
          }),
        ),
      ),
    );
  }

  Widget _connector(int afterIndex, OnboardingStep current) {
    final isDone = current.index > afterIndex;
    return Expanded(
      child: Container(
        height: 2,
        color: isDone ? AppColors.greenSuccess : AppColors.lightGrey2,
      ),
    );
  }
}

class _StepNode extends StatelessWidget {
  final int index;
  final String label;
  final OnboardingStep currentStep;

  const _StepNode({
    required this.index,
    required this.label,
    required this.currentStep,
  });

  bool get _isActive => currentStep.index == index;
  bool get _isDone => currentStep.index > index;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isDone
                ? AppColors.greenSuccess
                : _isActive
                    ? AppColors.primaryColor
                    : AppColors.background,
            border: Border.all(
              color: _isDone
                  ? AppColors.greenSuccess
                  : _isActive
                      ? AppColors.primaryColor
                      : AppColors.lightGrey2,
              width: 1.5,
            ),
          ),
          alignment: Alignment.center,
          child: _isDone
              ? const Icon(Icons.check_rounded, size: 15, color: AppColors.white)
              : CustomText(
                  text: '${index + 1}',
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.bold,
                  color: _isActive ? AppColors.white : AppColors.grey,
                ),
        ),
        const SizedBox(height: 5),
        CustomText(
          text: label,
          fontSize: 9,
          fontWeight: (_isActive || _isDone) ? FontWeight.w600 : FontWeight.w400,
          color: _isDone
              ? AppColors.greenSuccess
              : _isActive
                  ? AppColors.primaryColor
                  : AppColors.grey,
        ),
      ],
    );
  }
}
