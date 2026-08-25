import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class PosTransactionsEmpty extends StatelessWidget {
  const PosTransactionsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            decoration: const BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: AppColors.lightGrey,
            ),
          ),
          const SizedBox(height: 16),
          const CustomText(
            text: 'No transactions today',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.w600,
            color: AppColors.black2,
          ),
          const SizedBox(height: 6),
          const CustomText(
            text: 'Completed sales will appear here',
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
          ),
        ],
      ),
    );
  }
}
