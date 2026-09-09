import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_cart_sheet.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosCartBar extends StatelessWidget {
  final PosHomeController c;
  const PosCartBar({super.key, required this.c});

  void _openSheet() {
    Get.bottomSheet(
      PosCartSheet(c: c),
      isScrollControlled: true,
      backgroundColor: AppColors.transparent,
      enterBottomSheetDuration: const Duration(milliseconds: 280),
      exitBottomSheetDuration: const Duration(milliseconds: 220),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!c.hasItems) return const SizedBox.shrink();
      return GestureDetector(
        onTap: _openSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: AppColors.appbarGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryColor.withOpacity(0.45),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // ── Cart icon with badge ──────────────────────────────
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SvgIcon(
                      assetName: AppIcons.shoppingBag,
                      color: AppColors.white,
                      size: 20,
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: AppColors.white,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: CustomText(
                        text: '${c.itemCount}',
                        color: AppColors.primaryColor,
                        fontSize: AppFontSize.tiny,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 10),

              // ── Summary ───────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      text:
                          '${c.itemCount} item${c.itemCount == 1 ? '' : 's'} in cart',
                      color: AppColors.white.withOpacity(0.85),
                      fontSize: AppFontSize.tiny,
                    ),
                    CustomText(
                      text: '${c.currencySymbol.value}${c.total.toStringAsFixed(2)}',
                      color: AppColors.white,
                      fontSize: AppFontSize.small,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppTextStyles.monoFontFamily,
                    ),
                  ],
                ),
              ),

              // ── View Cart chip ────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomText(
                      text: 'View Cart',
                      color: AppColors.primaryColor,
                      fontSize: AppFontSize.verySmall,
                      fontWeight: FontWeight.bold,
                    ),
                    const SizedBox(width: 4),
                    SvgIcon(
                      assetName: AppIcons.rightArrow,
                      size: 10,
                      color: AppColors.primaryColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
