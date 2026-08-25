import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/core/theme/base_animations.dart';
import 'package:solvexo_pos/core/theme/base_shadows.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';

class LocationCard extends StatelessWidget {
  final StoreLocationModel location;
  final LocationOverviewStat? stat;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  const LocationCard({
    super.key,
    required this.location,
    this.stat,
    required this.onEdit,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = location.isActive;
    return PressableScale(
      onTap: onEdit,
      child: Container(
        padding: EdgeInsets.all(BaseSpacing.sm + 2),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(BaseRadius.lg),
          boxShadow: BaseShadows.forLevel(BaseElevation.level1),
          border: Border.all(
            color: isActive ? AppColors.primaryColor.withOpacity(0.15) : AppColors.transparent,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(BaseSpacing.xs),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(BaseRadius.sm),
                  ),
                  child: Icon(Icons.store_mall_directory_outlined,
                      color: AppColors.primaryColor, size: 18),
                ),
                SizedBox(width: BaseSpacing.xs),
                Expanded(
                  child: CustomText(
                    text: location.name,
                    color: AppColors.black2,
                    fontSize: AppFontSize.extraSmall,
                    fontWeight: FontWeight.w700,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusChip(isActive: isActive),
                if (isActive)
                  IconButton(
                    icon: Icon(Icons.archive_outlined, size: 18, color: AppColors.gray600),
                    onPressed: onArchive,
                  ),
              ],
            ),
            if (location.addressLabel.isNotEmpty) ...[
              SizedBox(height: BaseSpacing.xxs),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 13, color: AppColors.gray600),
                  SizedBox(width: BaseSpacing.xxs),
                  Expanded(
                    child: CustomText(
                      text: location.addressLabel,
                      color: AppColors.gray600,
                      fontSize: AppFontSize.tiny,
                      fontWeight: FontWeight.w600,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (location.phone != null && location.phone!.trim().isNotEmpty) ...[
              SizedBox(height: BaseSpacing.xxs / 2),
              Row(
                children: [
                  Icon(Icons.phone_outlined, size: 13, color: AppColors.gray600),
                  SizedBox(width: BaseSpacing.xxs),
                  CustomText(
                    text: location.phone!,
                    color: AppColors.gray600,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w600,
                  ),
                ],
              ),
            ],
            if (stat != null) ...[
              SizedBox(height: BaseSpacing.xs),
              Row(
                children: [
                  Icon(Icons.attach_money_rounded, size: 13, color: AppColors.green2),
                  SizedBox(width: BaseSpacing.xxs / 2),
                  CustomText(
                    text: '\$${stat!.totalSales.toStringAsFixed(2)} sales',
                    color: AppColors.gray600,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w600,
                  ),
                  SizedBox(width: BaseSpacing.sm),
                  Icon(Icons.receipt_long_outlined, size: 13, color: AppColors.gray600),
                  SizedBox(width: BaseSpacing.xxs / 2),
                  CustomText(
                    text: '${stat!.transactionCount} transactions',
                    color: AppColors.gray600,
                    fontSize: AppFontSize.tiny,
                    fontWeight: FontWeight.w600,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isActive;
  const _StatusChip({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.green2 : AppColors.gray600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: BaseSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(BaseRadius.pill),
      ),
      child: CustomText(
        text: isActive ? 'Active' : 'Archived',
        color: color,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        fontFamily: AppTextStyles.monoFontFamily,
      ),
    );
  }
}
