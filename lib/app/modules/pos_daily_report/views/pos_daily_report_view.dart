import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_daily_report/controllers/pos_daily_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_daily_report/widgets/pos_daily_report_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosDailyReportView extends StatelessWidget {
  PosDailyReportView({super.key});

  final PosDailyReportController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Daily Report',
        color: AppColors.black2,
        actions: [
          GestureDetector(
            onTap: c.onRefresh,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.refresh_rounded,
                  color: AppColors.primaryColor, size: 22),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosDailyReportShimmer();
        }
        final report = c.report.value;
        if (report == null) {
          return _EmptyState(onRetry: c.onRefresh);
        }
        return RefreshIndicator(
          onRefresh: c.onRefresh,
          color: AppColors.primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            children: [
              _SummaryGrid(report: report),
              const SizedBox(height: 16),
              _PaymentBreakdown(report: report),
              if (report.topProducts.isNotEmpty) ...[
                const SizedBox(height: 16),
                _TopProducts(products: report.topProducts),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// ── Empty / error state ──────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _EmptyState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Icon(Icons.bar_chart_rounded,
              size: 40, color: AppColors.primaryColor),
        ),
        const SizedBox(height: 18),
        const CustomText(
          text: 'No Report Data',
          fontSize: AppFontSize.medium,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const SizedBox(height: 8),
        const CustomText(
          text: 'No sales recorded for today.',
          fontSize: AppFontSize.verySmall,
          color: AppColors.iosGrey,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: CustomText(
              text: 'Retry',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryColor,
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Summary grid ─────────────────────────────────────────────────────────────
class _SummaryGrid extends StatelessWidget {
  final PosDailyReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const CustomText(
        text: 'Summary',
        fontSize: AppFontSize.small2,
        fontWeight: FontWeight.bold,
        color: AppColors.black2,
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _MetricCard(
            label: 'Total Revenue',
            value: '\$${report.totalRevenue.toStringAsFixed(2)}',
            icon: Icons.attach_money_rounded,
            iconColor: AppColors.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: 'Net Revenue',
            value: '\$${report.netRevenue.toStringAsFixed(2)}',
            icon: Icons.trending_up_rounded,
            iconColor: AppColors.green2,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _MetricCard(
            label: 'Transactions',
            value: '${report.totalTransactions}',
            icon: Icons.receipt_long_rounded,
            iconColor: AppColors.orange,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: 'Refunds',
            value: '\$${report.refundsTotal.toStringAsFixed(2)}',
            icon: Icons.undo_rounded,
            iconColor: AppColors.red,
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: _MetricCard(
            label: 'Avg. Sale',
            value: '\$${report.avgTransactionValue.toStringAsFixed(2)}',
            icon: Icons.calculate_outlined,
            iconColor: AppColors.primaryColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            label: 'Discount + Tax',
            value: '-\$${report.totalDiscount.toStringAsFixed(2)} / +\$${report.totalTax.toStringAsFixed(2)}',
            icon: Icons.local_offer_outlined,
            iconColor: AppColors.orange,
          ),
        ),
      ]),
    ]);
  }
}

// ── Payment breakdown ─────────────────────────────────────────────────────────
class _PaymentBreakdown extends StatelessWidget {
  final PosDailyReportModel report;
  const _PaymentBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final byMethod = report.byPaymentMethod;
    final total = byMethod.total;
    return _SectionCard(
      title: 'Payment Methods',
      child: Column(children: [
        _PayRow(
          label: 'Cash',
          amount: byMethod.cash.total,
          total: total,
          color: AppColors.green2,
        ),
        const SizedBox(height: 8),
        _PayRow(
          label: 'Card',
          amount: byMethod.card.total,
          total: total,
          color: AppColors.primaryColor,
        ),
        const SizedBox(height: 8),
        _PayRow(
          label: 'Other',
          amount: byMethod.other.total,
          total: total,
          color: AppColors.orange,
        ),
      ]),
    );
  }
}

// ── Top products ───────────────────────────────────────────────────────────────
class _TopProducts extends StatelessWidget {
  final List<PosTopProduct> products;
  const _TopProducts({required this.products});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top Products',
      child: Column(
        children: products.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.inventory_2_outlined, size: 18, color: AppColors.primaryColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CustomText(
                  text: p.name,
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                CustomText(
                  text: '${p.qty} sold',
                  fontSize: AppFontSize.tiny,
                  color: AppColors.iosGrey,
                ),
              ]),
            ),
            CustomText(
              text: '\$${p.revenue.toStringAsFixed(2)}',
              fontSize: AppFontSize.small2,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ]),
        )).toList(),
      ),
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(height: 10),
        CustomText(
          text: value,
          fontSize: AppFontSize.medium,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const SizedBox(height: 2),
        CustomText(
          text: label,
          fontSize: AppFontSize.tiny,
          color: AppColors.iosGrey,
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CustomText(
          text: title,
          fontSize: AppFontSize.small2,
          fontWeight: FontWeight.bold,
          color: AppColors.black2,
        ),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.lightGrey2),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final Color color;

  const _PayRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? amount / total : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CustomText(
          text: label,
          fontSize: AppFontSize.verySmall,
          color: AppColors.black2,
        ),
        const Spacer(),
        CustomText(
          text: '\$${amount.toStringAsFixed(2)}',
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.black2,
        ),
        const SizedBox(width: 6),
        CustomText(
          text: '(${(pct * 100).toStringAsFixed(0)}%)',
          fontSize: AppFontSize.tiny,
          color: AppColors.iosGrey,
        ),
      ]),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct,
          backgroundColor: AppColors.background,
          color: color,
          minHeight: 6,
        ),
      ),
    ]);
  }
}
