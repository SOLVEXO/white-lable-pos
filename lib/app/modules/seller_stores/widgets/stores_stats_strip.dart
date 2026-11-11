import 'package:solvexo_pos/app/modules/seller_stores/controllers/seller_stores_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:get/get.dart';

class StoresStatsStrip extends StatelessWidget {
  final SellerStoresController controller;

  const StoresStatsStrip({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final fg = context.palette.onAccentFill;
    return Obx(
      () => Container(
        padding: const EdgeInsets.symmetric(vertical: Space.s3 + 2),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.12),
          borderRadius: Radii.rLg,
          border: Border.all(color: fg.withValues(alpha: 0.2)),
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
                value: '${Money.symbol()}${_fmtRevenue(controller.totalRevenue)}', // the store's currency symbol
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
    final fg = context.palette.onAccentFill;
    final t = context.type;
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: t.amountMd.copyWith(color: fg)),
          const SizedBox(height: 2),
          Text(
            label,
            style: t.caption.copyWith(color: fg.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

class _VertLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      color: context.palette.onAccentFill.withValues(alpha: 0.25),
    );
  }
}
