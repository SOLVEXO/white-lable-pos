import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class PosRangeReportShimmer extends StatelessWidget {
  const PosRangeReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 66, radius: Radii.md)),
              SizedBox(width: Space.s2),
              Expanded(child: SkeletonBox(height: 66, radius: Radii.md)),
              SizedBox(width: Space.s2),
              Expanded(child: SkeletonBox(height: 66, radius: Radii.md)),
            ],
          ),
          const SizedBox(height: Space.s5),
          _card(
            context,
            rows: [
              for (int i = 0; i < 5; i++)
                const Row(
                  children: [
                    SkeletonBox(height: 10, width: 40),
                    SizedBox(width: Space.s3),
                    Expanded(child: SkeletonBox(height: 8, radius: Radii.full)),
                    SizedBox(width: Space.s2),
                    SkeletonBox(height: 10, width: 48),
                  ],
                ),
            ],
          ),
          const SizedBox(height: Space.s5),
          _card(
            context,
            rows: [
              for (int i = 0; i < 3; i++)
                const Row(
                  children: [
                    Expanded(child: SkeletonBox(height: 12)),
                    SizedBox(width: Space.s4),
                    SkeletonBox(height: 12, width: 55),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, {required List<Widget> rows}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(height: 18, width: 120),
        const SizedBox(height: Space.s3),
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: Radii.rMd),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: Space.s3), rows[i]],
            ],
          ),
        ),
      ],
    );
  }
}
