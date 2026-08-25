import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosHeldSalesShimmer extends StatelessWidget {
  const PosHeldSalesShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 4,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const _HeldSaleTileSkeleton(),
      ),
    );
  }
}

class _HeldSaleTileSkeleton extends StatelessWidget {
  const _HeldSaleTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Skeleton(width: 36, height: 36, cornerRadius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Skeleton(height: 13, width: 120),
              SizedBox(height: 6),
              Skeleton(height: 11, width: 80),
            ]),
          ),
          const Skeleton(height: 22, width: 60, cornerRadius: 8),
        ]),
        const SizedBox(height: 12),
        const Skeleton(height: 44, width: double.infinity, cornerRadius: 8),
        const SizedBox(height: 12),
        const Skeleton(height: 12, width: 90),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.lightGrey2),
        const SizedBox(height: 10),
        Row(children: const [
          Expanded(child: Skeleton(height: 34, cornerRadius: 10)),
          SizedBox(width: 8),
          Expanded(child: Skeleton(height: 34, cornerRadius: 10)),
          SizedBox(width: 8),
          Expanded(child: Skeleton(height: 34, cornerRadius: 10)),
        ]),
      ]),
    );
  }
}
