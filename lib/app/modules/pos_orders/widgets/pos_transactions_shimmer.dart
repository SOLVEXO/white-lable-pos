import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosTransactionsShimmer extends StatelessWidget {
  const PosTransactionsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: Column(
        children: [
          _statsRowSkeleton(),
          const Divider(height: 1, color: AppColors.lightGrey2),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppDimen.allPadding),
              itemCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, __) => const _ShimmerCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRowSkeleton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimen.allPadding,
        12,
        AppDimen.allPadding,
        12,
      ),
      child: Row(
        children: const [
          Expanded(
            flex: 2,
            child: Skeleton(
              height: 68,
              width: double.infinity,
              cornerRadius: AppDimen.serviceCountTileRadius,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Skeleton(
              height: 68,
              width: double.infinity,
              cornerRadius: AppDimen.serviceCountTileRadius,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Skeleton(
              height: 68,
              width: double.infinity,
              cornerRadius: AppDimen.serviceCountTileRadius,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Skeleton(height: 14, width: 80),
              Skeleton(height: 14, width: 52),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              Skeleton(height: 12, width: 60),
              SizedBox(width: 8),
              Skeleton(height: 22, width: 50, cornerRadius: 20),
              Spacer(),
              Skeleton(height: 12, width: 55),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.lightGrey2),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: Skeleton(height: 36, cornerRadius: AppDimen.borderRadius)),
              SizedBox(width: 10),
              Expanded(child: Skeleton(height: 36, cornerRadius: AppDimen.borderRadius)),
            ],
          ),
        ],
      ),
    );
  }
}
