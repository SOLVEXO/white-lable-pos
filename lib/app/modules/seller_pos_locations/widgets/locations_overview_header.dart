import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/store_locations_overview_model.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/core/theme/base_shadows.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';

/// Combined "all branches" stats card from the locations overview endpoint
/// (defaults to the last 30 days on the backend).
class LocationsOverviewHeader extends StatelessWidget {
  final StoreLocationsOverviewModel overview;
  const LocationsOverviewHeader({super.key, required this.overview});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(BaseSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(BaseRadius.lg),
        boxShadow: BaseShadows.forLevel(BaseElevation.level1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, size: 16, color: AppColors.primaryColor),
              SizedBox(width: BaseSpacing.xxs),
              const CustomText(
                text: 'All Branches',
                color: AppColors.black2,
                fontSize: AppFontSize.extraSmall,
                fontWeight: FontWeight.w700,
              ),
              const Spacer(),
              const CustomText(
                text: 'Last 30 days',
                color: AppColors.gray600,
                fontSize: AppFontSize.tiny,
                fontWeight: FontWeight.w600,
              ),
            ],
          ),
          SizedBox(height: BaseSpacing.sm),
          Row(
            children: [
              Expanded(
                child: _OverviewStat(
                  label: 'Total Sales',
                  value: '\$${overview.combinedTotalSales.toStringAsFixed(2)}',
                  color: AppColors.green2,
                ),
              ),
              SizedBox(width: BaseSpacing.sm),
              Expanded(
                child: _OverviewStat(
                  label: 'Transactions',
                  value: '${overview.combinedTransactionCount}',
                  color: AppColors.primaryColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _OverviewStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: BaseSpacing.sm, horizontal: BaseSpacing.sm),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(BaseRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomText(
            text: value,
            color: color,
            fontSize: AppFontSize.small,
            fontWeight: FontWeight.bold,
          ),
          SizedBox(height: BaseSpacing.xxs / 2),
          CustomText(
            text: label,
            color: AppColors.gray600,
            fontSize: AppFontSize.tiny,
            fontWeight: FontWeight.w600,
          ),
        ],
      ),
    );
  }
}
