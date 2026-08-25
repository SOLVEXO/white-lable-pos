import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosRangeReportShimmer extends StatelessWidget {
  const PosRangeReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Row(children: const [
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
          ]),
          const SizedBox(height: 16),
          _dailyBreakdownCard(),
          const SizedBox(height: 16),
          _topProductsCard(),
        ],
      ),
    );
  }

  Widget _dailyBreakdownCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Skeleton(height: 14, width: 110),
        const SizedBox(height: 14),
        for (int i = 0; i < 5; i++) ...[
          Row(children: const [
            Skeleton(height: 10, width: 40),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 8, width: double.infinity, cornerRadius: 4)),
            SizedBox(width: 8),
            Skeleton(height: 10, width: 40),
          ]),
          if (i != 4) const SizedBox(height: 10),
        ],
      ]),
    );
  }

  Widget _topProductsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Skeleton(height: 14, width: 110),
        const SizedBox(height: 12),
        for (int i = 0; i < 3; i++) ...[
          Row(children: const [
            Expanded(child: Skeleton(height: 12, width: double.infinity)),
            SizedBox(width: 10),
            Skeleton(height: 12, width: 50),
            SizedBox(width: 10),
            Skeleton(height: 12, width: 45),
          ]),
          if (i != 2) const SizedBox(height: 10),
        ],
      ]),
    );
  }
}
