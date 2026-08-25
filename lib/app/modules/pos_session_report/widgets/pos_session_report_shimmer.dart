import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosSessionReportShimmer extends StatelessWidget {
  const PosSessionReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _headerCard(),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 66, width: double.infinity, cornerRadius: 12)),
          ]),
          const SizedBox(height: 16),
          _sectionCard(rowCount: 3),
          const SizedBox(height: 16),
          _sectionCard(rowCount: 5),
        ],
      ),
    );
  }

  Widget _headerCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Skeleton(height: 20, width: 70, cornerRadius: 8),
        SizedBox(height: 12),
        Skeleton(height: 12, width: 150),
        SizedBox(height: 6),
        Skeleton(height: 12, width: 150),
      ]),
    );
  }

  Widget _sectionCard({required int rowCount}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Skeleton(height: 14, width: 120),
        const SizedBox(height: 14),
        for (int i = 0; i < rowCount; i++) ...[
          Row(children: const [
            Skeleton(height: 12, width: 80),
            Spacer(),
            Skeleton(height: 12, width: 55),
          ]),
          if (i != rowCount - 1) const SizedBox(height: 12),
        ],
      ]),
    );
  }
}
