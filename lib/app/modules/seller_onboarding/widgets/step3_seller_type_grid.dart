import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step3SellerTypeGrid extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step3SellerTypeGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const CustomText(
            text: 'What kind of seller are you?',
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: AppFontSize.veryLarge,
            fontWeight: FontWeight.bold,
            color: AppColors.black,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const CustomText(
            text: "We'll personalise your dashboard and tools based on your answer.",
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Column(
            children: [
              for (int i = 0; i < kSellerTypes.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i + 2 < kSellerTypes.length ? 10 : 0,
                  ),
                  child: _TypeCardRow(
                    first: kSellerTypes[i],
                    second: i + 1 < kSellerTypes.length
                        ? kSellerTypes[i + 1]
                        : null,
                    controller: controller,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Pairs two cards per row. Deliberately NOT `IntrinsicHeight` +
// `CrossAxisAlignment.stretch` — that combo mismeasures here: IntrinsicHeight
// computes each card's height from `Text.maxLines`-wrapped descriptions at a
// width that doesn't match the Expanded's actual constrained width, so it
// under-allocates by about one text line and every card overflows at the
// bottom by a fixed ~20px regardless of content. Letting each card size to
// its own natural height (`.start`, no IntrinsicHeight) avoids that
// class of bug entirely — the tradeoff is a row's two cards may differ in
// height when their descriptions wrap differently, which reads fine here.
class _TypeCardRow extends StatelessWidget {
  final SellerTypeData first;
  final SellerTypeData? second;
  final SellerOnboardingController controller;

  const _TypeCardRow({
    required this.first,
    required this.second,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // The `.value` reads below must happen inside this Obx's own builder
    // call to be tracked — reading them one widget down (inside _TypeCard's
    // build) is outside the scope Obx watches and throws "improper use of
    // GetX" the moment nothing else in this subtree is read directly here.
    return Obx(
      () => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _TypeCard(
              data: first,
              isSelected: controller.sellerType.value == first.type,
              onTap: () => controller.selectSellerType(first.type),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _TypeCard(
                    data: second!,
                    isSelected: controller.sellerType.value == second!.type,
                    onTap: () => controller.selectSellerType(second!.type),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  final SellerTypeData data;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeCard({required this.data, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryColor.withOpacity(0.05) : AppColors.white,
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
          border: Border.all(
            color: isSelected ? AppColors.primaryColor : AppColors.lightGrey2,
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CustomText(text: data.emoji, fontSize: 28),
                _RadioDot(isSelected: isSelected),
              ],
            ),
            const SizedBox(height: 8),
            CustomText(
              text: data.name,
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.primaryColor : AppColors.black,
            ),
            const SizedBox(height: 3),
            CustomText(
              text: data.description,
              fontSize: AppFontSize.verySmall,
              color: AppColors.grey,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool isSelected;
  const _RadioDot({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? AppColors.primaryColor : AppColors.white,
        border: Border.all(
          color: isSelected ? AppColors.primaryColor : AppColors.lightGrey2,
          width: 1.5,
        ),
      ),
      alignment: Alignment.center,
      child: isSelected
          ? const Icon(Icons.check_rounded, size: 11, color: AppColors.white)
          : null,
    );
  }
}
