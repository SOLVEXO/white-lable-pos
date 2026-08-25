import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class StoresShimmer extends StatelessWidget {
  const StoresShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            // Hero skeleton
            Container(
              color: AppColors.lightGrey2,
              padding: EdgeInsets.fromLTRB(20, topPad + 12, 20, 48),
              child: const Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: Skeleton(width: 36, height: 36, cornerRadius: 10),
                  ),
                  SizedBox(height: 20),
                  Skeleton(width: 80, height: 80, cornerRadius: 40),
                  SizedBox(height: 12),
                  Skeleton(height: 18, width: 140),
                  SizedBox(height: 6),
                  Skeleton(height: 12, width: 180),
                  SizedBox(height: 12),
                  Skeleton(height: 24, width: 120, cornerRadius: 20),
                  SizedBox(height: 28),
                  Skeleton(height: 56, width: double.infinity, cornerRadius: 12),
                ],
              ),
            ),
            // Content skeleton
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(AppDimen.allPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Skeleton(height: 18, width: 120),
                    const SizedBox(height: 16),
                    ...List.generate(
                      2,
                      (_) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.white,
                            borderRadius: BorderRadius.circular(
                              AppDimen.serviceCountTileRadius,
                            ),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: const [
                                  Skeleton(width: 48, height: 48, cornerRadius: 12),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Skeleton(height: 14, width: double.infinity),
                                        SizedBox(height: 6),
                                        Skeleton(height: 11, width: 100),
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 10),
                                  Skeleton(height: 36, width: 60, cornerRadius: 8),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Divider(height: 1, color: AppColors.lightGrey2),
                              const SizedBox(height: 10),
                              const Skeleton(height: 11, width: double.infinity),
                            ],
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
      ),
    );
  }
}
