import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StoresStatsStrip extends StatelessWidget {
  final SellerStoresController controller;

  const StoresStatsStrip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
          border: Border.all(color: AppColors.white.withOpacity(0.2)),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _StatCell(value: '${controller.storeCount}', label: 'Stores'),
              _VertLine(),
              _StatCell(
                value: '${controller.totalProducts}',
                label: 'Products',
              ),
              _VertLine(),
              _StatCell(
                value: '\$${_fmtRevenue(controller.totalRevenue)}',
                label: 'Revenue',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact money label: 999.5 → "999.50", 12,340 → "12.3k".
String _fmtRevenue(double n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;

  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            text: value,
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.white,
          ),
          const SizedBox(height: 2),
          CustomText(
            text: label,
            fontSize: AppFontSize.tiny,
            color: AppColors.white.withOpacity(0.75),
          ),
        ],
      ),
    );
  }
}

class _VertLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: AppColors.white.withOpacity(0.25));
  }
}
