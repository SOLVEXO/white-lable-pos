import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class PosCloseShiftButton extends StatelessWidget {
  final VoidCallback onTap;

  const PosCloseShiftButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimen.allPadding),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: AppColors.lightRed,
            borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
            border: Border.all(
              color: AppColors.red.withOpacity(0.25),
            ),
          ),
          alignment: Alignment.center,
          child: const CustomText(
            text: 'Close Shift & Log Out',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.w600,
            color: AppColors.red,
          ),
        ),
      ),
    );
  }
}
