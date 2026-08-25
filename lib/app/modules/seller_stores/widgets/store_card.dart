import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_status_style.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

class StoreCard extends StatelessWidget {
  final SellerStore store;
  final VoidCallback onOpen;

  const StoreCard({super.key, required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _StoreAvatar(
                  store: store,
                  isActive: store.isActive,
                  isprofile: store.logo.isNotEmpty,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomText(
                        text: store.name,
                        fontFamily: AppTextStyles.headingFontFamily,
                        fontSize: AppFontSize.small2,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 3),
                      CustomText(
                        text: store.category,
                        fontSize: AppFontSize.tiny,
                        color: AppColors.grey,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _OpenButton(onTap: onOpen),
              ],
            ),
          ),
          Container(
            height: 1,
            color: AppColors.lightGrey2,
            margin: const EdgeInsets.symmetric(horizontal: 14),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                _StatItem(
                  icon: Icons.inventory_2_outlined,
                  value: '${store.productCount}',
                  label: 'Products',
                ),
                const SizedBox(width: 20),
                _StatItem(
                  icon: Icons.trending_up_rounded,
                  value: '\$${store.totalSales.toStringAsFixed(0)}',
                  label: 'Sales',
                ),
                const Spacer(),
                _StatusBadge(status: store.status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

class _StoreAvatar extends StatelessWidget {
  final SellerStore store;
  final bool isActive;
  final bool isprofile;

  const _StoreAvatar({
    required this.isActive,
    required this.isprofile,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    return isprofile
        ? CommonImageView(
            url: store.logo,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            radius: BorderRadius.circular(12),
          )
        : Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              gradient: isActive
                  ? AppColors.appbarGradient
                  : const LinearGradient(
                      colors: [AppColors.lightGrey2, AppColors.lightGrey4],
                    ),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: CustomText(
              text: store.name[0],
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.white,
            ),
          );
  }
}

// ── Open button ───────────────────────────────────────────────────────────────

class _OpenButton extends StatelessWidget {
  final VoidCallback onTap;
  const _OpenButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.primaryColor,
          borderRadius: BorderRadius.circular(AppDimen.borderRadius),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryColor.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const CustomText(
          text: 'Open',
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.white,
        ),
      ),
    );
  }
}

// ── Stat item ─────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.lightGrey5),
        const SizedBox(width: 4),
        CustomText(
          text: value,
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.black2,
        ),
        const SizedBox(width: 3),
        CustomText(
          text: label,
          fontSize: AppFontSize.tiny,
          color: AppColors.grey,
        ),
      ],
    );
  }
}

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = storeStatusStyle(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: style.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        CustomText(
          text: style.shortLabel,
          fontSize: AppFontSize.tiny,
          fontWeight: FontWeight.w600,
          color: style.color,
        ),
      ],
    );
  }
}
