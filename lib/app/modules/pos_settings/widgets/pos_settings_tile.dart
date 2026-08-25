import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/modules/pos_settings/controllers/pos_settings_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class PosSettingsTileWidget extends StatelessWidget {
  final PosSettingsTile tile;

  const PosSettingsTileWidget({super.key, required this.tile});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: tile.onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimen.allPadding,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tile.isDanger
                    ? AppColors.lightRed
                    : AppColors.background,
                borderRadius: BorderRadius.circular(AppDimen.borderRadius),
              ),
              alignment: Alignment.center,
              child: SvgIcon(
                assetName: tile.emoji,
                size: 22,
                color: AppColors.black,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: CustomText(
                text: tile.title,
                fontSize: AppFontSize.extraSmall,
                fontWeight: FontWeight.w500,
                color: tile.isDanger ? AppColors.red : AppColors.black,
              ),
            ),
            if (tile.trailing != null) ...[
              const SizedBox(width: 8),
              CustomText(
                text: tile.trailing!,
                fontSize: AppFontSize.verySmall,
                color: tile.isDanger ? AppColors.red : AppColors.lightGrey5,
              ),
            ],
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: tile.isDanger ? AppColors.red : AppColors.lightGrey5,
            ),
          ],
        ),
      ),
    );
  }
}
