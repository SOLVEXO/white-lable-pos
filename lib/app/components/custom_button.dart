// ignore_for_file: deprecated_member_use

import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:responsive_sizer/responsive_sizer.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    this.fontFamily = AppTextStyles.fontFamily,
    this.color = AppColors.appBarColor,
    required this.onPressed,
    this.enabled = true,
    this.textColor = AppColors.white,
    this.fontSize = AppFontSize.small,
    this.fontWeight = FontWeight.w500,
    this.prefix,
    this.suffix,
    this.borderColor = AppColors.transparent,
    this.borderRadius = AppDimen.borderRadius,
    this.width,
    this.height = 45,
  });

  final String label;
  final String fontFamily;
  final Color color;
  final Color textColor;
  final Color borderColor;
  final bool enabled;
  final void Function()? onPressed;
  final double fontSize;
  final FontWeight fontWeight;
  final Widget? prefix;
  final Widget? suffix;
  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: width,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.symmetric(horizontal: 2.w),
          disabledBackgroundColor: AppColors.buttonDisableColor,
          disabledForegroundColor: AppColors.buttonDisableColor,
          foregroundColor: color,
          backgroundColor: color,
          elevation: 0,
          side: BorderSide(
            width: 0.8,
            color: enabled ? borderColor : borderColor.withOpacity(0.5),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (prefix != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: prefix,
              ),
            CustomText(
              text: label,
              color: enabled ? textColor : textColor.withOpacity(0.5),
              fontSize: fontSize,
              fontWeight: fontWeight,
              fontFamily: fontFamily,
            ),
            if (suffix != null)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: suffix,
              ),
          ],
        ),
      ),
    );
  }
}
