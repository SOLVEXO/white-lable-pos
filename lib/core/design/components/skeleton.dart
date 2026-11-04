import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// One shimmer pass over a whole group of [SkeletonBox]es — a single shader for
/// the whole list instead of one animation per placeholder. Static when the OS
/// asks for reduced motion.
class SkeletonShimmer extends StatelessWidget {
  const SkeletonShimmer({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: Shimmer.fromColors(
          enabled: !Motion.reduced(context),
          baseColor: p.fill,
          highlightColor: p.isDark ? p.border : p.surface,
          period: const Duration(milliseconds: 1400),
          child: child,
        ),
      ),
    );
  }
}

/// A plain placeholder block. Always place inside a [SkeletonShimmer].
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.radius = Radii.sm,
  });
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.palette.fill,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// Ready-made list-row skeleton (leading block + two lines).
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(Space.s4),
  });
  final int itemCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
        itemBuilder: (_, __) => const Row(
          children: [
            SkeletonBox(width: 52, height: 52, radius: Radii.md),
            SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(height: 14),
                  SizedBox(height: Space.s2),
                  SkeletonBox(width: 120, height: 12),
                ],
              ),
            ),
            SizedBox(width: Space.s3),
            SkeletonBox(width: 56, height: 16),
          ],
        ),
      ),
    );
  }
}
