import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:flutter/material.dart';

class IconBadge extends StatelessWidget {
  final String icon;
  final int count;
  final Widget? child;
  final bool ischild;
  const IconBadge({
    super.key,
    this.ischild = false,
    this.icon = AppIcons.searchIcon,
    this.count = 0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(BaseRadius.sm),
          ),
          alignment: Alignment.center,
          child: ischild
              ? child
              : SvgIcon(
                  assetName: icon,
                  size: 20,
                  color: AppColors.primaryColor,
                ),
        ),
        if (count > 0)
          Positioned(
            top: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              decoration: BoxDecoration(
                color: AppColors.red,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.white, width: 1.2),
              ),
              alignment: Alignment.center,
              child: CustomText(
                text: count > 9 ? '9+' : count.toString(),
                color: AppColors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
          ),
      ],
    );
  }
}
