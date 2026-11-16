import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosTransactionsShimmer extends StatelessWidget {
  const PosTransactionsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        children: [
          _statsRowSkeleton(),
          Divider(height: 1, color: context.palette.border),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(Space.s4),
              itemCount: 4,
              physics: const NeverScrollableScrollPhysics(),
              separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
              itemBuilder: (_, __) => const _ShimmerCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRowSkeleton() {
    return const Padding(
      padding: EdgeInsets.all(Space.s4),
      child: Row(
        children: [
          Expanded(flex: 2, child: SkeletonBox(height: 68, radius: Radii.lg)),
          SizedBox(width: Space.s3),
          Expanded(child: SkeletonBox(height: 68, radius: Radii.lg)),
          SizedBox(width: Space.s3),
          Expanded(child: SkeletonBox(height: 68, radius: Radii.lg)),
        ],
      ),
    );
  }
}

class _ShimmerCard extends StatelessWidget {
  const _ShimmerCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SkeletonBox(height: 14, width: 80),
              SkeletonBox(height: 14, width: 52),
            ],
          ),
          const SizedBox(height: Space.s3),
          const Row(
            children: [
              SkeletonBox(height: 12, width: 60),
              SizedBox(width: Space.s2),
              SkeletonBox(height: 22, width: 50, radius: Radii.full),
              Spacer(),
              SkeletonBox(height: 12, width: 55),
            ],
          ),
          const SizedBox(height: Space.s3),
          Divider(height: 1, color: context.palette.border),
          const SizedBox(height: Space.s3),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: Space.minTouch, radius: Radii.md)),
              SizedBox(width: Space.s3),
              Expanded(child: SkeletonBox(height: Space.minTouch, radius: Radii.md)),
            ],
          ),
        ],
      ),
    );
  }
}
