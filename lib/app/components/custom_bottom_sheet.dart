import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomBottomSheet extends StatelessWidget {
  const CustomBottomSheet({
    super.key,
    required this.title,
    required this.widget,
    this.height,
  });
  final double? height;
  final Widget widget;
  final String title;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: height ?? screenHeight * 0.85, // 👈 auto responsive
        ),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            /// 🔹 Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 12),
              height: 4,
              width: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: AppColors.lightGreyColor,
              ),
            ),

            /// 🔹 Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // const Spacer(),
                  CustomText(
                    text: title,
                    fontSize: AppFontSize.medium,
                    fontWeight: FontWeight.w600,
                  ),

                  const Spacer(),

                  GestureDetector(
                    onTap: () => Get.back(),
                    child: const CircleAvatar(
                      radius: 16,
                      child: Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),
            const Divider(),

            /// 🔥 CONTENT (Scrollable if needed)
            Flexible(
              child: Scrollbar(
                thumbVisibility:
                    true, // 👈 always visible (set false if only on scroll)
                thickness: 4,
                radius: const Radius.circular(10),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: widget,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
