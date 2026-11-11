import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';

class StoresShimmer extends StatelessWidget {
  const StoresShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final topPad = MediaQuery.of(context).padding.top;
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        children: [
          // Hero skeleton
          Container(
            color: p.accentFill,
            padding: EdgeInsets.fromLTRB(
              Space.s5,
              topPad + Space.s3,
              Space.s5,
              Space.s12,
            ),
            child: const SkeletonShimmer(
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SkeletonBox(width: 36, height: 36),
                  ),
                  SizedBox(height: Space.s5),
                  SkeletonBox(width: 80, height: 80, radius: 40),
                  SizedBox(height: Space.s3),
                  SkeletonBox(height: 18, width: 140),
                  SizedBox(height: 6),
                  SkeletonBox(height: 12, width: 180),
                  SizedBox(height: Space.s3),
                  SkeletonBox(height: 24, width: 120, radius: Radii.full),
                  SizedBox(height: Space.s6),
                  SkeletonBox(
                    height: 56,
                    width: double.infinity,
                    radius: Radii.lg,
                  ),
                ],
              ),
            ),
          ),
          // Content skeleton
          Transform.translate(
            offset: const Offset(0, -Space.s6),
            child: Container(
              decoration: BoxDecoration(
                color: p.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(Radii.xl),
                ),
              ),
              padding: const EdgeInsets.all(Space.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Space.s2),
                  const SkeletonShimmer(
                    child: SkeletonBox(height: 18, width: 120),
                  ),
                  const SizedBox(height: Space.s4),
                  ...List.generate(
                    2,
                    (_) => Padding(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      child: Container(
                        padding: const EdgeInsets.all(Space.s3 + 2),
                        decoration: BoxDecoration(
                          color: p.surface,
                          borderRadius: Radii.rLg,
                          border: Border.all(color: p.border),
                        ),
                        child: SkeletonShimmer(
                          child: Column(
                            children: [
                              const Row(
                                children: [
                                  SkeletonBox(width: 48, height: 48),
                                  SizedBox(width: Space.s3),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        SkeletonBox(
                                          height: 14,
                                          width: double.infinity,
                                        ),
                                        SizedBox(height: 6),
                                        SkeletonBox(height: 11, width: 100),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: Space.s2 + 2),
                                  SkeletonBox(height: 36, width: 60),
                                ],
                              ),
                              const SizedBox(height: Space.s2 + 2),
                              Divider(height: 1, color: p.border),
                              const SizedBox(height: Space.s2 + 2),
                              const SkeletonBox(
                                height: 11,
                                width: double.infinity,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
