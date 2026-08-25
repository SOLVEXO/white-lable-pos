import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';

class PosStatusBadge extends StatelessWidget {
  final String status;
  const PosStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final style = _resolve(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: style.bg, borderRadius: BorderRadius.circular(6)),
      child: CustomText(
        text: style.label,
        fontSize: AppFontSize.tiny,
        fontWeight: FontWeight.w700,
        color: style.fg,
        fontFamily: AppTextStyles.monoFontFamily,
      ),
    );
  }

  static _Style _resolve(String status) {
    switch (status) {
      case 'held':
        return const _Style('Held', AppColors.orange, Color(0xFFFFF1E6));
      case 'refunded':
        return const _Style('Refunded', AppColors.red, AppColors.lightRed);
      case 'partially_refunded':
        return const _Style('Partial refund', AppColors.red, AppColors.lightRed);
      case 'voided':
        return const _Style('Voided', AppColors.iosGrey, AppColors.background);
      case 'completed':
      default:
        return const _Style('Completed', AppColors.darkGreen, AppColors.greenContainerInnerColor);
    }
  }
}

class _Style {
  final String label;
  final Color fg;
  final Color bg;
  const _Style(this.label, this.fg, this.bg);
}
