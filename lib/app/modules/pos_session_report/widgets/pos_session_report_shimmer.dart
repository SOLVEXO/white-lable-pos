import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class PosSessionReportShimmer extends StatelessWidget {
  const PosSessionReportShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _headerCard(context),
          const SizedBox(height: Space.s4),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 66, radius: Radii.lg)),
              SizedBox(width: Space.s2),
              Expanded(child: SkeletonBox(height: 66, radius: Radii.lg)),
              SizedBox(width: Space.s2),
              Expanded(child: SkeletonBox(height: 66, radius: Radii.lg)),
            ],
          ),
          const SizedBox(height: Space.s4),
          _sectionCard(context, rowCount: 3),
          const SizedBox(height: Space.s4),
          _sectionCard(context, rowCount: 5),
        ],
      ),
    );
  }

  Widget _headerCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: Radii.rLg),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(height: 20, width: 70, radius: Radii.full),
          SizedBox(height: Space.s3),
          SkeletonBox(height: 12, width: 150),
          SizedBox(height: Space.s2),
          SkeletonBox(height: 12, width: 150),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, {required int rowCount}) {
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: Radii.rLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(height: 14, width: 120),
          const SizedBox(height: Space.s4),
          for (int i = 0; i < rowCount; i++) ...[
            const Row(
              children: [
                SkeletonBox(height: 12, width: 80),
                Spacer(),
                SkeletonBox(height: 12, width: 55),
              ],
            ),
            if (i != rowCount - 1) const SizedBox(height: Space.s3),
          ],
        ],
      ),
    );
  }
}
