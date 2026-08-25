import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresProfileSection extends StatelessWidget {
  final SellerStoresController controller;

  const StoresProfileSection({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.white.withOpacity(0.25),
              border: Border.all(
                color: AppColors.white.withOpacity(0.5),
                width: 2.5,
              ),
            ),
            child: controller.userProfileImage.value.isNotEmpty
                ? ClipOval(
                    child: CommonImageView(
                      url: controller.userProfileImage.value,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  )
                : Center(
                    child: CustomText(
                      text: controller.userInitials.value,
                      fontSize: AppFontSize.large,
                      fontWeight: FontWeight.bold,
                      color: AppColors.white,
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          CustomText(
            text: controller.userName.value,
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          CustomText(
            text: controller.userEmail.value,
            fontSize: AppFontSize.verySmall,
            color: AppColors.white.withOpacity(0.75),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.white.withOpacity(0.18),
              borderRadius: BorderRadius.circular(AppDimen.draggableBorderRadius),
              border: Border.all(color: AppColors.white.withOpacity(0.35)),
            ),
            child: const CustomText(
              text: '✨ Starter Plan — Free',
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: AppColors.white,
            ),
          ),
        ],
      ),
    );
  }
}
