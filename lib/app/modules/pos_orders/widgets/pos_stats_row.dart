import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_orders/controllers/pos_orders_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosStatsRow extends StatelessWidget {
  final PosOrdersController controller;
  const PosStatsRow({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppDimen.allPadding, 12, AppDimen.allPadding, 12,
      ),
      child: Row(children: [
        Expanded(
          flex: 2,
          child: _StatCard(
            label: 'Sales (loaded)',
            value: '${controller.currencySymbol.value}${controller.totalSales.toStringAsFixed(2)}',
            subtitle: '${controller.txnCount} txns',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Avg (loaded)',
            value: '${controller.currencySymbol.value}${controller.avgTransaction.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            label: 'Cash (loaded)',
            value: '${controller.currencySymbol.value}${controller.cashTotal.toStringAsFixed(0)}',
          ),
        ),
      ]),
    ));
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;

  const _StatCard({required this.label, required this.value, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius:
            BorderRadius.circular(AppDimen.serviceCountTileRadius),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CustomText(text: label, fontSize: AppFontSize.tiny, color: AppColors.grey),
        const SizedBox(height: 4),
        CustomText(
          text: value,
          fontSize: AppFontSize.small,
          fontWeight: FontWeight.bold,
          color: AppColors.black,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          CustomText(
            text: subtitle!,
            fontSize: AppFontSize.tiny,
            color: AppColors.lightGrey5,
          ),
        ],
      ]),
    );
  }
}
