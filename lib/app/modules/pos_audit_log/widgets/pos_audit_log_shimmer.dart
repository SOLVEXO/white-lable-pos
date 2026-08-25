import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosAuditLogShimmer extends StatelessWidget {
  const PosAuditLogShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => const _LogTileSkeleton(),
      ),
    );
  }
}

class _LogTileSkeleton extends StatelessWidget {
  const _LogTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        const Skeleton(width: 32, height: 32, cornerRadius: 8),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Skeleton(height: 13, width: 160),
            SizedBox(height: 6),
            Skeleton(height: 11, width: 90),
          ]),
        ),
      ]),
    );
  }
}
