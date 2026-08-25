import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step4WhatYouSellGrid extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step4WhatYouSellGrid({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
          const CustomText(
            text: 'What will you sell?',
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: AppFontSize.veryLarge,
            fontWeight: FontWeight.bold,
            color: AppColors.black,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const CustomText(
            text: 'Select all that apply — we\'ll activate the right tools for you.',
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Column(
            children: [
              for (int i = 0; i < kWhatYouSell.length; i += 2)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i + 2 < kWhatYouSell.length ? 10 : 0,
                  ),
                  child: _SellCardRow(
                    first: kWhatYouSell[i],
                    second: i + 1 < kWhatYouSell.length
                        ? kWhatYouSell[i + 1]
                        : null,
                    controller: controller,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Obx(() {
            final tools = controller.activatedTools;
            if (tools.isEmpty) return const SizedBox.shrink();
            return _ToolsPanel(tools: tools);
          }),
          const SizedBox(height: 8),
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
// bottom by a fixed ~20px regardless of content (see Step3's identical
// `_TypeCardRow`). Letting each card size to its own natural height
// (`.start`, no IntrinsicHeight) avoids that class of bug entirely.
class _SellCardRow extends StatelessWidget {
  final WhatYouSellData first;
  final WhatYouSellData? second;
  final SellerOnboardingController controller;

  const _SellCardRow({
    required this.first,
    required this.second,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    // The `.contains` reads below must happen inside this Obx's own builder
    // call to be tracked — reading them one widget down (inside _SellCard's
    // build) is outside the scope Obx watches and throws "improper use of
    // GetX" the moment nothing else in this subtree is read directly here.
    return Obx(
      () => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _SellCard(
              data: first,
              isSelected: controller.whatYouSell.contains(first.option),
              onTap: () => controller.toggleWhatYouSell(first.option),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: second == null
                ? const SizedBox.shrink()
                : _SellCard(
                    data: second!,
                    isSelected: controller.whatYouSell.contains(second!.option),
                    onTap: () => controller.toggleWhatYouSell(second!.option),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SellCard extends StatelessWidget {
  final WhatYouSellData data;
  final bool isSelected;
  final VoidCallback onTap;

  const _SellCard({required this.data, required this.isSelected, required this.onTap});

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
                _CheckBadge(isSelected: isSelected),
              ],
            ),
            const SizedBox(height: 8),
            CustomText(
              text: data.name,
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: isSelected ? AppColors.primaryColor : AppColors.black,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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

class _CheckBadge extends StatelessWidget {
  final bool isSelected;
  const _CheckBadge({required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 20,
      height: 20,
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
          ? const Icon(Icons.check_rounded, size: 12, color: AppColors.white)
          : null,
    );
  }
}

// ── Tools activated panel ─────────────────────────────────────────────────────

class _ToolsPanel extends StatelessWidget {
  final List<ActivatedTool> tools;
  const _ToolsPanel({required this.tools});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.languageBg,
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
          border: Border.all(color: AppColors.primaryColor.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CustomText(text: '✨', fontSize: 14),
                const SizedBox(width: 6),
                CustomText(
                  text: "We'll activate these tools for you:",
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tools
                  .map(
                    (t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.bgColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: CustomText(
                        text: t.name,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.w600,
                        color: t.textColor,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
