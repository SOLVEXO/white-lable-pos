import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosDailyReportShimmer extends StatelessWidget {
  const PosDailyReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _metricGrid(),
          const SizedBox(height: 10),
          _metricGrid(),
          const SizedBox(height: 16),
          _sectionCard(rowCount: 3),
          const SizedBox(height: 16),
          _sectionCard(rowCount: 3),
        ],
      ),
    );
  }

  Widget _metricGrid() {
    return Row(children: const [
      Expanded(child: Skeleton(height: 72, width: double.infinity, cornerRadius: AppDimen.serviceCountTileRadius)),
      SizedBox(width: 10),
      Expanded(child: Skeleton(height: 72, width: double.infinity, cornerRadius: AppDimen.serviceCountTileRadius)),
    ]);
  }

  Widget _sectionCard({required int rowCount}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Skeleton(height: 14, width: 110),
        const SizedBox(height: 14),
        for (int i = 0; i < rowCount; i++) ...[
          Row(children: const [
            Skeleton(height: 12, width: 70),
            Spacer(),
            Skeleton(height: 12, width: 50),
          ]),
          if (i != rowCount - 1) const SizedBox(height: 12),
        ],
      ]),
    );
  }
}
