// ignore_for_file: deprecated_member_use

import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
// import 'package:hifzpro_app/apptheme/app_colors.dart';

class AppButton extends StatelessWidget {
  final String label;
  final void Function()? onPressed;
  final IconData? icon;
  final Widget? iconWidget;
  final bool isOutlined;
  final Color? backgroundColor;
  final Color? textColor;
  final double height;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconWidget,
    this.isOutlined = false,
    this.height = 45,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    final btnColor =
        backgroundColor ??
        (isOutlined ? AppColors.transparent : AppColors.accentColor);

    final borderColor = backgroundColor;

    return SizedBox(
      height: height,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon:
            iconWidget ??
            (icon != null
                ? Icon(
                    icon,
                    color: textColor ?? AppColors.white,
                    size: isTablet ? 24 : 20,
                  )
                : const SizedBox()),
        // No Flexible wrapper here — ElevatedButton.icon's own internal
        // implementation already wraps icon/label in a Flexible on current
        // Flutter SDKs; wrapping it again caused a "competing
        // ParentDataWidgets" crash (two Flexibles claiming the same slot).
        label: CustomText(
          text: label,
          color:
              textColor ?? (isOutlined ? AppColors.accentColor : AppColors.white),
          fontSize: isTablet ? 20 : 16,
          fontWeight: FontWeight.w600,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(45),
          disabledBackgroundColor: AppColors.buttonDisableColor,
          disabledForegroundColor: AppColors.buttonDisableColor,
          backgroundColor: btnColor,
          foregroundColor: btnColor,
          elevation: 0,
          side: BorderSide(
            width: isOutlined ? 0.8 : 0,
            color: isOutlined
                ? borderColor ?? AppColors.accentColor
                : AppColors.transparent,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            side: BorderSide(
              color: isOutlined
                  ? borderColor ?? AppColors.accentColor
                  : AppColors.transparent,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
