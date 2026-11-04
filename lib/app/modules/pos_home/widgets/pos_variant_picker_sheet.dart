import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Pick one variant of a multi-variant product. (Moved out of `pos_home_controller.dart`; the behaviour is unchanged:
/// an available variant is added with `controller.addToCart(product, variant)` and the sheet closes with `Get.back()`;
/// an unavailable one does nothing.) Presented with `Get.bottomSheet`, whose route background is transparent, so this
/// widget draws its own surface via [AppSheetSurface].
class PosVariantPickerSheet extends StatelessWidget {
  final PosProductModel product;
  final PosHomeController controller;

  const PosVariantPickerSheet({super.key, required this.product, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppSheetSurface(
      title: 'Select variant · ${product.name}',
      child: Column(
        children: [
          for (final v in product.variants)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                color: p.fill,
                radius: Radii.rMd,
                semanticLabel: '${v.label}, ${v.unlimitedStock ? 'unlimited stock' : (v.stock > 0 ? '${v.stock} in stock' : 'out of stock')}, ${Money.format(v.price)}',
                onTap: v.isAvailable
                    ? () {
                        controller.addToCart(product, v);
                        Get.back();
                      }
                    : null,
                child: Opacity(
                  opacity: v.isAvailable ? 1 : 0.55,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(v.label, style: context.type.subtitle.copyWith(color: p.textPrimary)),
                            Text(
                              v.unlimitedStock ? 'Unlimited stock' : (v.stock > 0 ? '${v.stock} in stock' : 'Out of stock'),
                              style: context.type.caption.copyWith(color: v.isAvailable ? p.textMuted : p.dangerFg),
                            ),
                          ],
                        ),
                      ),
                      Text(Money.format(v.price), style: context.type.amountMd.copyWith(color: p.accentFg, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
