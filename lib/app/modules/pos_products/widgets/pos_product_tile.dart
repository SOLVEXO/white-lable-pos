import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_products/widgets/pos_stock_badge.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

class PosProductTile extends StatelessWidget {
  final PosProductModel product;
  /// unused by the tile (prices are formatted with the store's currency); kept so existing callers still compile
  final String? currencySymbol;

  const PosProductTile({super.key, required this.product, this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AppCard(
      radius: Radii.rMd,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: Radii.rMd,
            child: SizedBox(
              width: 52,
              height: 52,
              child: AppNetworkImage(url: product.displayImage, fallbackIcon: Icons.inventory_2_outlined),
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: t.subtitle.copyWith(color: p.textPrimary),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  product.hasMultipleVariants ? '${product.sku} · ${product.variants.length} variants' : product.sku,
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: Space.s1),
                AmountText(Money.format(product.price), style: t.amountMd, color: p.accentFg, animate: false),
              ],
            ),
          ),
          const SizedBox(width: Space.s3),
          PosStockBadge(stockCount: product.totalStock, unlimited: product.hasUnlimitedStock),
        ],
      ),
    );
  }
}
