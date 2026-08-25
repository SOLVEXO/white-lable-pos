import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosSettingsShimmer extends StatelessWidget {
  const PosSettingsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppDimen.allPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _profileShimmer(),
            const SizedBox(height: 24),
            _sectionShimmer(tileCount: 4), // REGISTER
            const SizedBox(height: 24),
            _sectionShimmer(tileCount: 3), // SHIFT
            const SizedBox(height: 24),
            _sectionShimmer(tileCount: 3), // PREFERENCES
            const SizedBox(height: 32),
            _closeButtonShimmer(),
          ],
        ),
      ),
    );
  }

  Widget _profileShimmer() {
    return Container(
      margin: const EdgeInsets.all(AppDimen.allPadding),
      padding: const EdgeInsets.all(AppDimen.allPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
      ),
      child: Row(
        children: [
          const Skeleton(width: 60, height: 60, cornerRadius: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Skeleton(height: 15, width: 110),
                SizedBox(height: 7),
                Skeleton(height: 12, width: 150),
                SizedBox(height: 8),
                Skeleton(height: 12, width: 160),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionShimmer({required int tileCount}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimen.allPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Skeleton(height: 11, width: 80),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: tileCount,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                indent: 54,
                color: AppColors.lightGrey2,
              ),
              itemBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimen.allPadding,
                  vertical: 14,
                ),
                child: Row(
                  children: const [
                    Skeleton(width: 36, height: 36, cornerRadius: 8),
                    SizedBox(width: 14),
                    Expanded(
                      child: Skeleton(height: 13, width: double.infinity),
                    ),
                    SizedBox(width: 40),
                    Skeleton(height: 13, width: 40),
                    SizedBox(width: 6),
                    Skeleton(height: 13, width: 13, cornerRadius: 4),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _closeButtonShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppDimen.allPadding),
      child: Skeleton(
        height: 52,
        width: double.infinity,
        cornerRadius: AppDimen.serviceCountTileRadius,
      ),
    );
  }
}
