import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';

class PosPaymentBadge extends StatelessWidget {
  final String method;

  const PosPaymentBadge({super.key, required this.method});

  @override
  Widget build(BuildContext context) {
    final style = _resolve(method);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: style.border, width: 1),
      ),
      child: CustomText(
        text: style.label,
        fontSize: AppFontSize.tiny,
        fontWeight: FontWeight.w600,
        color: style.fg,
        fontFamily: AppTextStyles.monoFontFamily,
      ),
    );
  }

  static _BadgeStyle _resolve(String method) {
    switch (method.toLowerCase()) {
      case 'card':
        return const _BadgeStyle(
          label: 'Card',
          fg: AppColors.black2,
          bg: AppColors.white,
          border: AppColors.lightGrey2,
        );
      case 'cash':
        return const _BadgeStyle(
          label: 'Cash',
          fg: AppColors.darkGreen,
          bg: AppColors.greenContainerInnerColor,
          border: AppColors.darkGreen,
        );
      default:
        return _BadgeStyle(
          label: 'Other',
          fg: AppColors.primaryColor,
          bg: AppColors.languageBg,
          border: AppColors.primaryColor,
        );
    }
  }
}

class _BadgeStyle {
  final String label;
  final Color fg;
  final Color bg;
  final Color border;

  const _BadgeStyle({
    required this.label,
    required this.fg,
    required this.bg,
    required this.border,
  });
}
