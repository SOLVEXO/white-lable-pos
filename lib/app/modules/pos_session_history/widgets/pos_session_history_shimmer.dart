import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosSessionHistoryShimmer extends StatelessWidget {
  const PosSessionHistoryShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const _SessionTileSkeleton(),
      ),
    );
  }
}

class _SessionTileSkeleton extends StatelessWidget {
  const _SessionTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        const Skeleton(width: 36, height: 36, cornerRadius: 10),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Skeleton(height: 13, width: 150),
            SizedBox(height: 6),
            Skeleton(height: 11, width: 100),
          ]),
        ),
        const Skeleton(height: 14, width: 50),
      ]),
    );
  }
}
