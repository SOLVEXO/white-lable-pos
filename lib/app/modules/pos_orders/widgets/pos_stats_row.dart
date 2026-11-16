import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosStatsRow extends StatelessWidget {
  final PosOrdersController controller;
  const PosStatsRow({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    return Obx(() {
      final sales = _StatCard(
        label: 'Sales (loaded)',
        value: Money.format(controller.totalSales),
        subtitle: '${controller.txnCount} txns',
      );
      final avg = _StatCard(
        label: 'Avg (loaded)',
        value: Money.format(controller.avgTransaction),
      );
      final cash = _StatCard(
        label: 'Cash (loaded)',
        value: Money.format(controller.cashTotal),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
        child: stack
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  sales,
                  const SizedBox(height: Space.s2),
                  avg,
                  const SizedBox(height: Space.s2),
                  cash,
                ],
              )
            : IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: sales),
                    const SizedBox(width: Space.s3),
                    Expanded(child: avg),
                    const SizedBox(width: Space.s3),
                    Expanded(child: cash),
                  ],
                ),
              ),
      );
    });
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;

  const _StatCard({required this.label, required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
          const SizedBox(height: Space.s1),
          AmountText(value, style: context.type.amountMd, color: p.textPrimary, animate: false),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: context.type.caption.copyWith(color: p.textMuted)),
          ],
        ],
      ),
    );
  }
}
