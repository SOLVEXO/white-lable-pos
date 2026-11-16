import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Loading placeholder shaped like the "Team & registers" screen: launch card,
/// stat tiles, quick links, then the employees / registers / shifts lists.
class SellerPosManagementShimmer extends StatelessWidget {
  const SellerPosManagementShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.all(Space.s4),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SkeletonBox(height: 140, radius: Radii.lg),
          const SizedBox(height: Space.s4),
          const Row(children: [
            Expanded(child: SkeletonBox(height: 92, radius: Radii.lg)),
            SizedBox(width: Space.s2),
            Expanded(child: SkeletonBox(height: 92, radius: Radii.lg)),
          ]),
          const SizedBox(height: Space.s2),
          const SkeletonBox(height: 92, radius: Radii.lg),
          const SizedBox(height: Space.s3),
          const Row(children: [
            Expanded(child: SkeletonBox(height: 64, radius: Radii.md)),
            SizedBox(width: Space.s2),
            Expanded(child: SkeletonBox(height: 64, radius: Radii.md)),
            SizedBox(width: Space.s2),
            Expanded(child: SkeletonBox(height: 64, radius: Radii.md)),
          ]),
          const SizedBox(height: Space.s6),
          _section(rowCount: 3),
          const SizedBox(height: Space.s5),
          _section(rowCount: 2),
          const SizedBox(height: Space.s5),
          _section(rowCount: 2),
        ],
      ),
    );
  }

  Widget _section({required int rowCount}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SkeletonBox(height: 18, width: 110),
      const SizedBox(height: Space.s3),
      for (var i = 0; i < rowCount; i++) ...[
        if (i > 0) const SizedBox(height: Space.s2),
        const SkeletonBox(height: 64, radius: Radii.lg),
      ],
    ]);
  }
}
