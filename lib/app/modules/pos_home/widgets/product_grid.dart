import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/product_detail_sheet.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The product catalogue as a sliver grid. Uses the controller's own `productScrollController` (its listener loads the
/// next page near the bottom), shows a skeleton while loading, an empty state with Retry, and one scoped `Obx` per tile
/// so adding to the cart rebuilds only the tiles' badge, never the whole grid.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.c, required this.cartKey, this.bottomInset = Space.s4});
  final PosHomeController c;

  /// The cart icon the fly-to-cart dot flies to.
  final GlobalKey cartKey;

  /// Extra room at the bottom (the phone's total pill floats over the grid).
  final double bottomInset;

  static int columnsFor(double width) {
    if (width < 420) return 2;
    if (width < 620) return 3;
    return (width / 168).floor().clamp(3, 6);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final cols = columnsFor(box.maxWidth);
        final delegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          childAspectRatio: 0.74,
          crossAxisSpacing: Space.s3,
          mainAxisSpacing: Space.s3,
        );
        return Obx(() {
          if (c.isLoadingProducts.value) return _GridSkeleton(delegate: delegate, bottomInset: bottomInset);
          final products = c.filteredProducts;
          if (products.isEmpty) {
            return EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No products found',
              message: 'Try a different search or category',
              actionLabel: 'Retry',
              onAction: c.retryLoadProducts,
            );
          }
          return CustomScrollView(
            controller: c.productScrollController,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, 0),
                sliver: SliverGrid(
                  gridDelegate: delegate,
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => RepaintBoundary(child: ProductTileObx(c: c, product: products[i], cartKey: cartKey)),
                    childCount: products.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: bottomInset + 28,
                  child: Obx(
                    () => c.isLoadingMoreProducts.value
                        ? Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: context.palette.accent)))
                        : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );
        });
      },
    );
  }
}

/// One grid tile. Its own `Obx` reads only this product's quantity in the cart.
class ProductTileObx extends StatelessWidget {
  const ProductTileObx({super.key, required this.c, required this.product, required this.cartKey});
  final PosHomeController c;
  final PosProductModel product;
  final GlobalKey cartKey;

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => ProductTile(
        name: product.name,
        priceText: Money.format(product.price),
        imageUrl: product.displayImage,
        stock: product.hasUnlimitedStock ? null : product.totalStock,
        unlimited: product.hasUnlimitedStock,
        inCartQty: c.cartQtyFor(product),
        // a multi-variant product opens the variant picker instead of adding straight away: no fly-to-cart then
        cartKey: product.hasMultipleVariants ? null : cartKey,
        onAdd: () => c.addToCart(product),
        onLongPress: () => ProductDetailSheet.open(c, product),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton({required this.delegate, required this.bottomInset});
  final SliverGridDelegate delegate;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s4, bottomInset),
        gridDelegate: delegate,
        itemCount: 12,
        itemBuilder: (_, __) => const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: SkeletonBox(height: double.infinity, radius: Radii.lg)),
            SizedBox(height: Space.s2),
            SkeletonBox(height: 12),
            SizedBox(height: Space.s1),
            SkeletonBox(width: 56, height: 12),
          ],
        ),
      ),
    );
  }
}
