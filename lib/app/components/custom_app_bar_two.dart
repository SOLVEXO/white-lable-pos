import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CustomAppBarTwo extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? child;
  final Color color;
  final bool centerTitle;
  final bool showBackButton;
  final bool showLeading;
  final Color? backgroundColor;
  final Color? iconColor;
  final double appbarHeight;
  final String assetName;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  const CustomAppBarTwo({
    super.key,
    this.title,
    this.color = AppColors.black,
    this.centerTitle = false,
    this.showBackButton = true,
    this.showLeading = true,
    this.backgroundColor,
    this.iconColor,
    this.actions,
    this.onBack,
    this.appbarHeight = 50.0,
    this.child,
    this.assetName = AppIcons.home,
  });

  @override
  Size get preferredSize => Size.fromHeight(appbarHeight);

  @override
  Widget build(BuildContext context) {
    final bool isTablet = MediaQuery.of(context).size.width >= 600;

    return AppBar(
      foregroundColor: backgroundColor ?? AppColors.white,
      backgroundColor: backgroundColor ?? AppColors.white,
      centerTitle: centerTitle,
      scrolledUnderElevation: 0, // ← add this line
      elevation: 0,
      surfaceTintColor: AppColors.transparent,
      automaticallyImplyLeading: showLeading,
      leading: !showLeading
          ? null
          : showBackButton
              ? IconButton(
                  onPressed: onBack ?? () => Get.back(),
                  icon: Icon(
                    Icons.chevron_left,
                    size: isTablet ? 50 : 35,
                    color: color,
                  ),
                )
              : IconButton(
                  onPressed: onBack ?? () => Get.back(),
                  icon: SvgIcon(
                    assetName: assetName,
                    size: isTablet ? 50 : 35,
                    color: color,
                  ),
                ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            text: title ?? "",
            color: color,
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: isTablet ? 24 : AppFontSize.medium,
            fontWeight: FontWeight.w600,
          ),
          Container(child: child),
        ],
      ),
      actions: actions,
    );
  }
}
