import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class PosDailyReportShimmer extends StatelessWidget {
  const PosDailyReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const SkeletonBox(height: 18, width: 90),
          const SizedBox(height: Space.s3),
          _metricGrid(),
          const SizedBox(height: Space.s2),
          _metricGrid(),
          const SizedBox(height: Space.s2),
          _metricGrid(),
          const SizedBox(height: Space.s5),
          _sectionCard(context, rowCount: 3),
          const SizedBox(height: Space.s5),
          _sectionCard(context, rowCount: 3),
        ],
      ),
    );
  }

  Widget _metricGrid() {
    return const Row(
      children: [
        Expanded(child: SkeletonBox(height: 96, radius: Radii.md)),
        SizedBox(width: Space.s2),
        Expanded(child: SkeletonBox(height: 96, radius: Radii.md)),
      ],
    );
  }

  Widget _sectionCard(BuildContext context, {required int rowCount}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SkeletonBox(height: 18, width: 130),
        const SizedBox(height: Space.s3),
        Container(
          padding: const EdgeInsets.all(Space.s4),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: Radii.rMd),
          child: Column(
            children: [
              for (int i = 0; i < rowCount; i++) ...[
                const Row(
                  children: [
                    SkeletonBox(height: 12, width: 70),
                    Spacer(),
                    SkeletonBox(height: 12, width: 55),
                  ],
                ),
                const SizedBox(height: Space.s1),
                const SkeletonBox(height: 6, radius: Radii.full),
                if (i != rowCount - 1) const SizedBox(height: Space.s3),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
