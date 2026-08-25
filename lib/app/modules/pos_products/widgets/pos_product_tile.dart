import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/modules/pos_products/widgets/pos_stock_badge.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class PosProductTile extends StatelessWidget {
  final PosProductModel product;

  const PosProductTile({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _thumbnail(),
          const SizedBox(width: 12),
          Expanded(child: _productInfo()),
          const SizedBox(width: 12),
          PosStockBadge(stockCount: product.totalStock),
        ],
      ),
    );
  }

  Widget _thumbnail() {
    final image = product.displayImage;
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: image != null
          ? Image.network(
              image,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.inventory_2_outlined, size: 24, color: AppColors.grey),
            )
          : const Icon(Icons.inventory_2_outlined, size: 24, color: AppColors.grey),
    );
  }

  Widget _productInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomText(
          text: product.name,
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        const SizedBox(height: 3),
        CustomText(
          text: product.hasMultipleVariants ? '${product.sku} · ${product.variants.length} variants' : product.sku,
          fontSize: AppFontSize.tiny,
          color: AppColors.grey,
        ),
        const SizedBox(height: 5),
        CustomText(
          text: '\$${product.price.toStringAsFixed(2)}',
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.w600,
          color: AppColors.primaryColor,
          fontFamily: AppTextStyles.monoFontFamily,
        ),
      ],
    );
  }
}
