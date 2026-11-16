import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingStepBar extends StatelessWidget {
  final SellerOnboardingController controller;

  const OnboardingStepBar({super.key, required this.controller});

  static const _labels = ['Store Info', 'Seller Type', 'Go Live'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      child: Obx(
        () => Row(
          children: List.generate(_labels.length * 2 - 1, (i) {
            if (i.isOdd) return _connector(p, i ~/ 2, controller.step.value);
            final index = i ~/ 2;
            // Loose flex: a node keeps its natural width, but shrinks (its
            // label scales down) instead of overflowing at large text sizes.
            return Flexible(
              flex: 2,
              child: _StepNode(
                index: index,
                label: _labels[index],
                currentStep: controller.step.value,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _connector(AppPalette p, int afterIndex, OnboardingStep current) {
    final isDone = current.index > afterIndex;
    return Expanded(
      child: Container(height: 2, color: isDone ? p.success : p.border),
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
    final p = context.palette;
    final fill = _isDone
        ? p.success
        : _isActive
        ? p.accentFill
        : p.fill;
    final edge = _isDone
        ? p.success
        : _isActive
        ? p.accentFill
        : p.border;
    final labelColor = _isDone
        ? p.successFg
        : _isActive
        ? p.accentFg
        : p.textMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: Motion.of(context, Motion.base),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fill,
            border: Border.all(color: edge, width: 1.5),
          ),
          alignment: Alignment.center,
          child: _isDone
              ? Icon(
                  Icons.check_rounded,
                  size: IconSizes.xxs,
                  color: p.onAccentFill,
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${index + 1}',
                    style: context.type.label.copyWith(
                      color: _isActive ? p.onAccentFill : p.textMuted,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: Space.s1),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: context.type.caption.copyWith(
              color: labelColor,
              fontWeight: (_isActive || _isDone)
                  ? FontWeight.w600
                  : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
