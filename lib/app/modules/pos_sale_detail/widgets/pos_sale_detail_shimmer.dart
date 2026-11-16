import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosSaleDetailShimmer extends StatelessWidget {
  const PosSaleDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.all(Space.s4),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                SkeletonBox(height: 14, width: 100),
                SkeletonBox(height: 20, width: 70, radius: Radii.full),
              ]),
              SizedBox(height: Space.s3),
              SkeletonBox(height: 11, width: 130),
              SizedBox(height: Space.s3),
              Row(children: [
                SkeletonBox(height: 20, width: 60, radius: Radii.full),
                SizedBox(width: Space.s2),
                SkeletonBox(height: 12, width: 80),
              ]),
            ]),
          ),
          const SizedBox(height: Space.s4),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SkeletonBox(height: 13, width: 50),
              const SizedBox(height: Space.s4),
              for (int i = 0; i < 3; i++) ...[
                const Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SkeletonBox(height: 12, width: 140),
                      SizedBox(height: 6),
                      SkeletonBox(height: 10, width: 90),
                    ]),
                  ),
                  SkeletonBox(height: 12, width: 45),
                ]),
                if (i != 2) const SizedBox(height: Space.s4),
              ],
            ]),
          ),
          const SizedBox(height: Space.s4),
          AppCard(
            child: Column(children: [
              for (int i = 0; i < 3; i++) ...[
                const Row(children: [
                  SkeletonBox(height: 12, width: 70),
                  Spacer(),
                  SkeletonBox(height: 12, width: 55),
                ]),
                if (i != 2) const SizedBox(height: Space.s3),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}
