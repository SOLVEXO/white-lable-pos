import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos/widgets/pos_app_bar.dart';
import 'package:solvexo_pos/app/modules/pos_products/controllers/pos_products_controller.dart';
import 'package:solvexo_pos/app/modules/pos_products/widgets/pos_product_tile.dart';
import 'package:solvexo_pos/app/modules/pos_products/widgets/pos_products_empty.dart';
import 'package:solvexo_pos/app/modules/pos_products/widgets/pos_products_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';

class PosProductsView extends StatelessWidget {
  PosProductsView({super.key});

  final PosProductsController controller = Get.put(PosProductsController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: Center(
        // tablet: a centred column, not a stretched phone (G6.3)
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: Column(
        children: [
          const PosAppBar(title: 'Products'),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
            child: AppSearchBar(
              controller: controller.searchController,
              onChanged: controller.onSearchChanged,
              hint: 'Search products or SKU...',
            ),
          ),
          Expanded(
            child: Obx(() {
              if (controller.isLoading.value) {
                return const PosProductsShimmer();
              }
              final products = controller.filteredProducts;
              if (products.isEmpty) return const PosProductsEmpty();
              return RefreshIndicator(
                color: p.accentFg,
                backgroundColor: p.surface,
                onRefresh: controller.refreshData,
                child: ListView.separated(
                  controller: controller.scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  itemCount: products.length + (controller.isLoadingMore.value ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: Space.s3),
                  itemBuilder: (_, i) {
                    if (i >= products.length) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: Space.s3),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: p.accentFg),
                          ),
                        ),
                      );
                    }
                    return PosProductTile(
                      product: products[i],
                      currencySymbol: controller.currencySymbol.value,
                    );
                  },
                ),
              );
            }),
          ),
        ],
      )),
      ),
    );
  }
}
