import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';

class PosStockBadge extends StatelessWidget {
  final int stockCount;
  final bool unlimited;

  const PosStockBadge({super.key, required this.stockCount, this.unlimited = false});

  bool get _inStock => unlimited || stockCount > 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 44),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _inStock
                ? AppColors.greenContainerInnerColor
                : AppColors.lightRed,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: CustomText(
            text: unlimited ? '∞' : (_inStock ? stockCount.toString() : 'Out'),
            fontSize: AppFontSize.verySmall,
            fontWeight: FontWeight.bold,
            color: _inStock ? AppColors.darkGreen : AppColors.red,
            fontFamily: AppTextStyles.monoFontFamily,
          ),
        ),
        const SizedBox(height: 4),
        CustomText(
          text: unlimited ? 'unlimited' : (_inStock ? 'in stock' : 'out of stock'),
          fontSize: AppFontSize.tiny,
          color: AppColors.lightGrey5,
        ),
      ],
    );
  }
}
