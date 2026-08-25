import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class PosTransactionButtons extends StatelessWidget {
  final VoidCallback onReceipt;
  final VoidCallback? onRefund;
  final VoidCallback? onVoid;

  const PosTransactionButtons({
    super.key,
    required this.onReceipt,
    this.onRefund,
    this.onVoid,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TxnBtn(
            label: 'Receipt',
            onTap: onReceipt,
            color: AppColors.black2,
            bgColor: AppColors.background,
            borderColor: AppColors.lightGrey2,
          ),
        ),
        if (onVoid != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _TxnBtn(
              label: 'Void',
              onTap: onVoid!,
              color: AppColors.iosGrey,
              bgColor: AppColors.background,
              borderColor: AppColors.iosGrey,
            ),
          ),
        ],
        if (onRefund != null) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _TxnBtn(
              label: 'Refund',
              onTap: onRefund!,
              color: AppColors.red,
              bgColor: AppColors.lightRed,
              borderColor: AppColors.red,
            ),
          ),
        ],
      ],
    );
  }
}

class _TxnBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final Color bgColor;
  final Color borderColor;

  const _TxnBtn({
    required this.label,
    required this.onTap,
    required this.color,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppDimen.borderRadius),
          border: Border.all(color: borderColor.withOpacity(0.4)),
        ),
        alignment: Alignment.center,
        child: CustomText(
          text: label,
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
