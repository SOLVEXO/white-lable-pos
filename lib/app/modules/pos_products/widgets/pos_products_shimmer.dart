import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosProductsShimmer extends StatelessWidget {
  const PosProductsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView.separated(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        itemCount: 6,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, __) => const _ShimmerTile(),
      ),
    );
  }
}

class _ShimmerTile extends StatelessWidget {
  const _ShimmerTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
      ),
      child: Row(
        children: const [
          Skeleton(
            height: 52,
            width: 52,
            cornerRadius: AppDimen.serviceCountTileRadius,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(height: 14, width: 140),
                SizedBox(height: 6),
                Skeleton(height: 11, width: 100),
                SizedBox(height: 6),
                Skeleton(height: 13, width: 56),
              ],
            ),
          ),
          SizedBox(width: 12),
          Column(
            children: [
              Skeleton(height: 28, width: 44, cornerRadius: 20),
              SizedBox(height: 4),
              Skeleton(height: 10, width: 40),
            ],
          ),
        ],
      ),
    );
  }
}
