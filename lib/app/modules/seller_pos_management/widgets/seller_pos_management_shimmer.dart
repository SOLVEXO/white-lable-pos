import 'package:solvexo_pos/app/components/skeleton.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class SellerPosManagementShimmer extends StatelessWidget {
  const SellerPosManagementShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,
      highlightColor: AppColors.shimmerHighlight,
      child: ListView(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const Skeleton(height: 56, width: double.infinity, cornerRadius: 14),
          const SizedBox(height: 16),
          Row(children: const [
            Expanded(child: Skeleton(height: 78, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 78, width: double.infinity, cornerRadius: 12)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 78, width: double.infinity, cornerRadius: 12)),
          ]),
          const SizedBox(height: 12),
          Row(children: const [
            Expanded(child: Skeleton(height: 38, width: double.infinity, cornerRadius: 10)),
            SizedBox(width: 10),
            Expanded(child: Skeleton(height: 38, width: double.infinity, cornerRadius: 10)),
          ]),
          const SizedBox(height: 20),
          _section(header: 'Employees', rowCount: 3),
          const SizedBox(height: 20),
          _section(header: 'Registers', rowCount: 2),
          const SizedBox(height: 20),
          _section(header: 'Shifts', rowCount: 2),
        ],
      ),
    );
  }

  Widget _section({required String header, required int rowCount}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Skeleton(height: 12, width: 90),
      const SizedBox(height: 10),
      Container(
        decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(
          children: List.generate(rowCount, (i) {
            return Column(children: [
              if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.lightGrey2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: const [
                  Skeleton(width: 42, height: 42, cornerRadius: 21),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Skeleton(height: 13, width: 120),
                      SizedBox(height: 6),
                      Skeleton(height: 11, width: 90),
                    ]),
                  ),
                ]),
              ),
            ]);
          }),
        ),
      ),
    ]);
  }
}
