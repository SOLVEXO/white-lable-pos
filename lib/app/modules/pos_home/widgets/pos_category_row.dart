import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosCategoryRow extends StatelessWidget {
  final PosHomeController c;
  const PosCategoryRow({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: c.categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final catId = c.categories[i];
            return Obx(() {
              final isSelected = c.selectedCategoryId.value == catId;
              return GestureDetector(
                onTap: () => c.selectCategory(catId),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primaryColor : AppColors.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? AppColors.primaryColor : AppColors.lightGrey2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: CustomText(
                    text: c.categoryLabel(catId),
                    fontSize: AppFontSize.verySmall,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? AppColors.white : AppColors.iosGrey,
                  ),
                ),
              );
            });
          },
        ),
      ),
    );
  }
}
