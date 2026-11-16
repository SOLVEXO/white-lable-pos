import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_daily_report/controllers/pos_daily_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_daily_report/widgets/pos_daily_report_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosDailyReportView extends StatelessWidget {
  PosDailyReportView({super.key});

  final PosDailyReportController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Daily Report',
      actions: [
        Obx(
          () => IconButton(
            tooltip: 'Export CSV',
            onPressed: c.isExporting.value ? null : c.exportCsv,
            icon: c.isExporting.value
                ? SizedBox(
                    width: IconSizes.sm,
                    height: IconSizes.sm,
                    child: CircularProgressIndicator(strokeWidth: 2, color: context.palette.accentFg),
                  )
                : Icon(Icons.ios_share_rounded, color: context.palette.accentFg),
          ),
        ),
        IconButton(
          tooltip: 'Refresh',
          onPressed: c.onRefresh,
          icon: Icon(Icons.refresh_rounded, color: context.palette.accentFg),
        ),
      ],
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosDailyReportShimmer();
        }
        final report = c.report.value;
        if (report == null) {
          return EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No Report Data',
            message: 'No sales recorded for today.',
            actionLabel: 'Retry',
            onAction: c.onRefresh,
          );
        }
        return RefreshIndicator(
          onRefresh: c.onRefresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              _SummaryGrid(report: report),
              const SizedBox(height: Space.s5),
              _PaymentBreakdown(report: report),
              if (report.topProducts.isNotEmpty) ...[
                const SizedBox(height: Space.s5),
                _TopProducts(products: report.topProducts),
              ],
            ],
          ),
        );
      }),
    );
  }
}

// ── Summary grid ─────────────────────────────────────────────────────────────
class _SummaryGrid extends StatelessWidget {
  final PosDailyReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Summary'),
        _Pair(
          left: _MetricCard(
            label: 'Total Revenue',
            value: Money.format(report.totalRevenue),
            icon: Icons.attach_money_rounded,
            tint: p.accentSoft,
            tone: p.accentFg,
          ),
          right: _MetricCard(
            label: 'Net Revenue',
            value: Money.format(report.netRevenue),
            icon: Icons.trending_up_rounded,
            tint: p.successSoft,
            tone: p.successFg,
          ),
        ),
        const SizedBox(height: Space.s2),
        _Pair(
          left: _MetricCard(
            label: 'Transactions',
            value: '${report.totalTransactions}',
            icon: Icons.receipt_long_rounded,
            tint: p.warningSoft,
            tone: p.warningFg,
          ),
          right: _MetricCard(
            label: 'Refunds',
            value: Money.format(report.refundsTotal),
            icon: Icons.undo_rounded,
            tint: p.dangerSoft,
            tone: p.dangerFg,
          ),
        ),
        const SizedBox(height: Space.s2),
        _Pair(
          left: _MetricCard(
            label: 'Avg. Sale',
            value: Money.format(report.avgTransactionValue),
            icon: Icons.calculate_outlined,
            tint: p.accentSoft,
            tone: p.accentFg,
          ),
          right: _MetricCard(
            label: 'Discount + Tax',
            value: '-${Money.format(report.totalDiscount)} / +${Money.format(report.totalTax)}',
            icon: Icons.local_offer_outlined,
            tint: p.warningSoft,
            tone: p.warningFg,
          ),
        ),
      ],
    );
  }
}

/// Two figures side by side; stacked when the text is large so no number is squeezed.
class _Pair extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _Pair({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.textScalerOf(context).scale(16) > 19) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: Space.s2), right],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: Space.s2),
          Expanded(child: right),
        ],
      ),
    );
  }
}

// ── Payment breakdown ─────────────────────────────────────────────────────────
class _PaymentBreakdown extends StatelessWidget {
  final PosDailyReportModel report;
  const _PaymentBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final byMethod = report.byPaymentMethod;
    final total = byMethod.total;
    return _SectionCard(
      title: 'Payment Methods',
      child: Column(
        children: [
          _PayRow(label: 'Cash', amount: byMethod.cash.total, total: total, color: p.success),
          const SizedBox(height: Space.s3),
          _PayRow(label: 'Card', amount: byMethod.card.total, total: total, color: p.accent),
          const SizedBox(height: Space.s3),
          _PayRow(label: 'Other', amount: byMethod.other.total, total: total, color: p.warning),
        ],
      ),
    );
  }
}

// ── Top products ───────────────────────────────────────────────────────────────
class _TopProducts extends StatelessWidget {
  final List<PosTopProduct> products;
  const _TopProducts({required this.products});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return _SectionCard(
      title: 'Top Products',
      child: Column(
        children: [
          for (var i = 0; i < products.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == products.length - 1 ? 0 : Space.s3),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(Space.s2),
                    decoration: BoxDecoration(color: p.accentSoft, borderRadius: Radii.rSm),
                    child: Icon(Icons.inventory_2_outlined, size: IconSizes.sm, color: p.accentFg),
                  ),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          products[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.subtitle.copyWith(color: p.textPrimary),
                        ),
                        Text('${products[i].qty} sold', style: t.caption.copyWith(color: p.textSecondary)),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s2),
                  Flexible(
                    child: AmountText(
                      Money.format(products[i].revenue),
                      style: t.amountSm,
                      color: p.textPrimary,
                      animate: false,
                      alignment: MainAxisAlignment.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared components ─────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final Color tone;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      padding: const EdgeInsets.all(Space.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(Space.s2),
            decoration: BoxDecoration(color: tint, borderRadius: Radii.rSm),
            child: Icon(icon, size: IconSizes.sm, color: tone),
          ),
          const SizedBox(height: Space.s3),
          AmountText(value, style: context.type.amountMd, color: p.textPrimary, animate: false),
          const SizedBox(height: Space.s1),
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title),
        AppCard(
          radius: Radii.rMd,
          padding: const EdgeInsets.all(Space.s4),
          child: child,
        ),
      ],
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
    final p = context.palette;
    final t = context.type;
    final pct = total > 0 ? amount / total : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: t.body.copyWith(color: p.textPrimary))),
            const SizedBox(width: Space.s2),
            Flexible(
              child: AmountText(
                Money.format(amount),
                style: t.amountSm,
                color: p.textPrimary,
                animate: false,
                alignment: MainAxisAlignment.end,
              ),
            ),
            const SizedBox(width: Space.s2),
            Text('(${(pct * 100).toStringAsFixed(0)}%)', style: t.caption.copyWith(color: p.textMuted)),
          ],
        ),
        const SizedBox(height: Space.s1),
        ClipRRect(
          borderRadius: Radii.rFull,
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: p.fill,
            color: color,
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
