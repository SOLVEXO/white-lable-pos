import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresSectionHeader extends StatelessWidget {
  final SellerStoresController controller;

  const StoresSectionHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimen.allPadding),
      child: Row(
        children: [
          const CustomText(
            text: 'Your Stores',
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.black,
          ),
          const SizedBox(width: 10),
          Obx(
            () => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: CustomText(
                text: '${controller.stores.length}',
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
