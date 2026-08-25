import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosCartItemTile extends StatelessWidget {
  final PosHomeController c;
  final CartItem item;
  const PosCartItemTile({super.key, required this.c, required this.item});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // ── Thumbnail tile ────────────────────────────────────────
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: item.product.displayImage != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    item.product.displayImage!,
                    width: 46,
                    height: 46,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.inventory_2_outlined, size: 22, color: AppColors.primaryColor),
                  ),
                )
              : Icon(Icons.inventory_2_outlined, size: 22, color: AppColors.primaryColor),
        ),
        const SizedBox(width: 12),

        // ── Name + qty controls ───────────────────────────────────
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CustomText(
              text: item.product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.black2,
            ),
            const SizedBox(height: 2),
            CustomText(
              text: item.variant?.label ?? item.product.sku,
              fontSize: AppFontSize.tiny,
              color: AppColors.iosGrey,
            ),
            const SizedBox(height: 8),
            Row(children: [
              _QtyBtn(icon: Icons.remove_rounded, onTap: () => c.decrement(item)),
              Container(
                width: 34,
                alignment: Alignment.center,
                child: CustomText(
                  text: '${item.quantity.value}',
                  fontSize: AppFontSize.extraSmall,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black2,
                ),
              ),
              _QtyBtn(icon: Icons.add_rounded, onTap: () => c.increment(item)),
              const SizedBox(width: 8),
              CustomText(
                text: '× \$${item.unitPrice.toStringAsFixed(2)}',
                fontSize: AppFontSize.tiny,
                color: AppColors.iosGrey,
                fontFamily: AppTextStyles.monoFontFamily,
              ),
            ]),
          ]),
        ),
        const SizedBox(width: 10),

        // ── Line total + remove ───────────────────────────────────
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          GestureDetector(
            onTap: () => c.removeFromCart(item),
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.09),
                borderRadius: BorderRadius.circular(7),
              ),
              child: const Icon(Icons.close_rounded, size: 14, color: AppColors.red),
            ),
          ),
          const SizedBox(height: 8),
          CustomText(
            text: '\$${item.lineTotal.toStringAsFixed(2)}',
            fontSize: AppFontSize.small2,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
            fontFamily: AppTextStyles.monoFontFamily,
          ),
        ]),
      ]),
    ));
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: AppColors.lightGrey2),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 15, color: AppColors.black2),
      ),
    );
  }
}
