import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class PosSaleDetailShimmer extends StatelessWidget {
  const PosSaleDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Skeleton(height: 14, width: 100),
                Skeleton(height: 20, width: 70, cornerRadius: 8),
              ]),
              SizedBox(height: 10),
              Skeleton(height: 11, width: 130),
              SizedBox(height: 12),
              Row(children: [
                Skeleton(height: 20, width: 60, cornerRadius: 20),
                SizedBox(width: 8),
                Skeleton(height: 12, width: 80),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Skeleton(height: 13, width: 50),
              const SizedBox(height: 14),
              for (int i = 0; i < 3; i++) ...[
                Row(children: const [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Skeleton(height: 12, width: 140),
                      SizedBox(height: 6),
                      Skeleton(height: 10, width: 90),
                    ]),
                  ),
                  Skeleton(height: 12, width: 45),
                ]),
                if (i != 2) const SizedBox(height: 14),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          _card(
            child: Column(children: [
              for (int i = 0; i < 3; i++) ...[
                Row(children: const [
                  Skeleton(height: 12, width: 70),
                  Spacer(),
                  Skeleton(height: 12, width: 55),
                ]),
                if (i != 2) const SizedBox(height: 10),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }
}
