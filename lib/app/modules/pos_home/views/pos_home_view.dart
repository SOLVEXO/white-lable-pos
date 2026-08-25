import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_cart_bar.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_category_row.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_product_card.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_search_bar.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosHomeView extends StatelessWidget {
  final c = Get.put(PosHomeController());

  PosHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        Column(children: [
          const PosAppBar(),
          PosSearchBar(c: c),
          const Divider(height: 1, color: AppColors.lightGrey2),
          PosCategoryRow(c: c),
          const Divider(height: 1, color: AppColors.lightGrey2),
          Expanded(child: _ProductGrid(c: c)),
        ]),

        Obx(() => AnimatedPositioned(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          bottom: c.hasItems ? (bottomPad + 12) : -(100 + bottomPad),
          left: 16,
          right: 16,
          child: PosCartBar(c: c),
        )),
      ]),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  final PosHomeController c;
  const _ProductGrid({required this.c});

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Obx(() {
      // Show shimmer while initial load is in progress
      if (c.isLoadingProducts.value) {
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.72,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: 9,
          itemBuilder: (_, __) => _ProductShimmer(),
        );
      }

      final products = c.filteredProducts;
      if (products.isEmpty) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off_rounded,
                size: 52, color: AppColors.lightGrey2),
            const SizedBox(height: 12),
            const CustomText(
              text: 'No products found',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.w500,
              color: AppColors.iosGrey,
            ),
            const SizedBox(height: 4),
            const CustomText(
              text: 'Try a different search or category',
              fontSize: AppFontSize.tiny,
              color: AppColors.lightGrey,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: c.retryLoadProducts,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CustomText(
                  text: 'Retry',
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ]),
        );
      }
      return GridView.builder(
        padding: EdgeInsets.fromLTRB(
            12, 12, 12, c.hasItems ? (bottomPad + 88) : 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 0.72,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) => PosProductCard(c: c, product: products[i]),
      );
    });
  }
}

class _ProductShimmer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Expanded(
          flex: 11,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.lightGrey2.withOpacity(0.5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
          ),
        ),
        Expanded(
          flex: 9,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey2.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(4),
                    )),
                const SizedBox(height: 6),
                Container(
                    height: 8,
                    width: 50,
                    decoration: BoxDecoration(
                      color: AppColors.lightGrey2.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    )),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
