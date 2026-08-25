import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/components/comp_controllers/toast_controller.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_images.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomToast extends StatelessWidget {
  final String message;
  final String? imagePath;
  final Color bgColor;
  final Color textColor;

  CustomToast({
    super.key,
    required this.message,
    this.imagePath,
    required this.bgColor,
    required this.textColor,
  });

  final controller = Get.put(ToastControllerX());

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: controller.fade,
      child: SlideTransition(
        position: controller.slide,
        child: Material(
          color: AppColors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              // gradient: AppColors.appbarGradient,
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 28,
                  width: 28,
                  margin: const EdgeInsets.only(right: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: CommonImageView(
                      imagePath: AppImages.logoImage,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                /// 🔹 Text
                Flexible(
                  child: CustomText(
                    text: message,
                    color: textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
