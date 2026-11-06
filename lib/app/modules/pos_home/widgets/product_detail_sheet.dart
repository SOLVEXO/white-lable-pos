import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Long-press a product: its name, SKU, price and stock, and every variant with its own stock — tap a variant (or "Add to sale") to add it.
class ProductDetailSheet extends StatelessWidget {
  const ProductDetailSheet({super.key, required this.c, required this.product});
  final PosHomeController c;
  final PosProductModel product;

  static Future<void> open(PosHomeController c, PosProductModel p) => AppBottomSheet.showGet<void>(ProductDetailSheet(c: c, product: p), title: p.name);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('SKU ${product.sku.isEmpty ? '—' : product.sku}', key: const Key('detailSku'), style: t.caption.copyWith(color: p.textMuted))),
            if (product.hasUnlimitedStock)
              const StatusBadge('Unlimited stock', tone: StatusTone.neutral)
            else
              StatusBadge(product.isOutOfStock ? 'Sold out' : '${product.totalStock} in stock', key: const Key('detailStock'), tone: product.isOutOfStock ? StatusTone.danger : (product.isLowStock ? StatusTone.warning : StatusTone.success)),
          ],
        ),
        const SizedBox(height: Space.s2),
        if (!product.hasMultipleVariants) AmountText(Money.format(product.price), key: const Key('detailPrice'), style: t.amountLg),
        if (product.hasMultipleVariants) ...[
          Text('Variants', style: t.title.copyWith(color: p.textPrimary)),
          const SizedBox(height: Space.s2),
          for (final v in product.variants)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('detailVariant_${v.variantId}'),
                radius: Radii.rMd,
                child: InkWell(
                  onTap: v.isAvailable
                      ? () {
                          c.addToCart(product, v);
                          Get.back();
                        }
                      : null,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.label, style: t.subtitle.copyWith(color: v.isAvailable ? p.textPrimary : p.textMuted)),
                            Text(v.unlimitedStock ? 'Unlimited stock' : (v.isAvailable ? '${v.stock} in stock' : 'Sold out'), style: t.caption.copyWith(color: p.textMuted)),
                          ],
                        ),
                      ),
                      Text(Money.format(v.price), style: t.amountMd.copyWith(color: p.accentFg, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: Space.s3),
        if (!product.hasMultipleVariants)
          AppButton(
            key: const Key('detailAdd'),
            label: product.inStock ? 'Add to sale' : 'Sold out',
            icon: Icons.add_rounded,
            onPressed: product.inStock
                ? () {
                    c.addToCart(product);
                    Get.back();
                  }
                : null,
          ),
      ],
    );
  }
}
