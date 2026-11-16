import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_range_report/controllers/pos_range_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_range_report/widgets/pos_range_report_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

bool _largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(16) > 19;

class PosRangeReportView extends StatelessWidget {
  PosRangeReportView({super.key});

  final PosRangeReportController c = Get.put(PosRangeReportController());

  @override
  Widget build(BuildContext context) {
    // CSV export lives on Daily Report — the backend only supports
    // exporting a single date, so there's no honest "export this range"
    // action to offer here.
    return AppPage(
      title: 'Reports',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateRangeBar(c: c),
          Expanded(
            child: Obx(() {
              if (c.isLoading.value) {
                return const PosRangeReportShimmer();
              }
              final report = c.report.value;
              if (report == null) {
                return const EmptyState(icon: Icons.bar_chart_rounded, title: 'No data for this range.');
              }
              return RefreshIndicator(
                onRefresh: c.loadReport,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
                  children: [
                    _SummaryGrid(report: report),
                    const SizedBox(height: Space.s5),
                    _DailyBreakdown(report: report),
                    if (report.topProducts.isNotEmpty) ...[
                      const SizedBox(height: Space.s5),
                      _TopProducts(report: report),
                    ],
                  ],
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _DateRangeBar extends StatelessWidget {
  final PosRangeReportController c;
  const _DateRangeBar({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s1, Space.s4, Space.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Obx(
          () => AppPill(
            label: '${DateFormat('MMM d').format(c.from.value)} — ${DateFormat('MMM d, y').format(c.to.value)}',
            icon: Icons.calendar_today_outlined,
            trailingIcon: Icons.keyboard_arrow_down_rounded,
            selected: true,
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now(),
                initialDateRange: DateTimeRange(start: c.from.value, end: c.to.value),
              );
              if (picked != null) c.setRange(picked.start, picked.end);
            },
          ),
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final PosRangeReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = [
      _Metric(label: 'Revenue', value: Money.format(report.totalRevenue), color: p.accentFg),
      _Metric(label: 'Net', value: Money.format(report.netRevenue), color: p.successFg),
      _Metric(label: 'Transactions', value: '${report.totalTransactions}', color: p.textPrimary),
    ];
    if (_largeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(height: Space.s2), tiles[i]],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: Space.s2), Expanded(child: tiles[i])],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      padding: const EdgeInsets.symmetric(vertical: Space.s3, horizontal: Space.s3),
      child: Column(
        children: [
          AmountText(value, style: context.type.amountMd, color: color, animate: false, alignment: MainAxisAlignment.center),
          const SizedBox(height: Space.s1),
          Text(label, textAlign: TextAlign.center, style: context.type.caption.copyWith(color: p.textSecondary)),
        ],
      ),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  final PosRangeReportModel report;
  const _DailyBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final large = _largeText(context);
    final maxTotal = report.dailyBreakdown.fold(0.0, (m, d) => d.total > m ? d.total : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Daily Revenue'),
        AppCard(
          radius: Radii.rMd,
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            children: [
              for (final d in report.dailyBreakdown) ...[
                Builder(
                  builder: (context) {
                    final date = Text(DateFormat('MMM d').format(DateTime.parse(d.date)), maxLines: 1, style: t.caption.copyWith(color: p.textSecondary));
                    final amount = AmountText(Money.format(d.total), style: t.amountSm, color: p.textPrimary, animate: false, alignment: MainAxisAlignment.end);
                    final bar = ClipRRect(
                      borderRadius: Radii.rFull,
                      child: LinearProgressIndicator(
                        value: maxTotal > 0 ? d.total / maxTotal : 0,
                        backgroundColor: p.fill,
                        color: p.accent,
                        minHeight: 8,
                      ),
                    );
                    if (large) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: Space.s3),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                date,
                                const SizedBox(width: Space.s2),
                                Expanded(child: amount),
                              ],
                            ),
                            const SizedBox(height: Space.s1),
                            bar,
                          ],
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: Space.s2),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 56,
                            child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: date),
                          ),
                          Expanded(child: bar),
                          const SizedBox(width: Space.s2),
                          SizedBox(width: 88, child: amount),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TopProducts extends StatelessWidget {
  final PosRangeReportModel report;
  const _TopProducts({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Top Products'),
        AppCard(
          radius: Radii.rMd,
          padding: const EdgeInsets.all(Space.s4),
          child: Column(
            children: [
              for (var i = 0; i < report.topProducts.length; i++)
                Padding(
                  padding: EdgeInsets.only(bottom: i == report.topProducts.length - 1 ? 0 : Space.s3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.topProducts[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.subtitle.copyWith(color: p.textPrimary),
                            ),
                            Text('${report.topProducts[i].qty} sold', style: t.caption.copyWith(color: p.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: Space.s2),
                      Flexible(
                        child: AmountText(
                          Money.format(report.topProducts[i].revenue),
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
        ),
      ],
    );
  }
}
