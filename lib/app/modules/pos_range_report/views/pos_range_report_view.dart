import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_range_report/controllers/pos_range_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_range_report/widgets/pos_range_report_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosRangeReportView extends StatelessWidget {
  PosRangeReportView({super.key});

  final PosRangeReportController c = Get.put(PosRangeReportController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // CSV export lives on Daily Report — the backend only supports
      // exporting a single date, so there's no honest "export this range"
      // action to offer here.
      appBar: CustomAppBarTwo(
        title: 'Reports',
        color: AppColors.black2,
      ),
      body: Column(children: [
        _DateRangeBar(c: c),
        Expanded(
          child: Obx(() {
            if (c.isLoading.value) {
              return const PosRangeReportShimmer();
            }
            final report = c.report.value;
            if (report == null) {
              return const Center(child: CustomText(text: 'No data for this range.', fontSize: AppFontSize.small2, color: AppColors.iosGrey));
            }
            return RefreshIndicator(
              onRefresh: c.loadReport,
              color: AppColors.primaryColor,
              child: ListView(
                padding: const EdgeInsets.all(AppDimen.allPadding),
                children: [
                  _SummaryGrid(report: report),
                  const SizedBox(height: 16),
                  _DailyBreakdown(report: report),
                  if (report.topProducts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _TopProducts(report: report),
                  ],
                ],
              ),
            );
          }),
        ),
      ]),
    );
  }
}

class _DateRangeBar extends StatelessWidget {
  final PosRangeReportController c;
  const _DateRangeBar({required this.c});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Obx(() => GestureDetector(
        onTap: () async {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime.now().subtract(const Duration(days: 365)),
            lastDate: DateTime.now(),
            initialDateRange: DateTimeRange(start: c.from.value, end: c.to.value),
          );
          if (picked != null) c.setRange(picked.start, picked.end);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.lightGrey2),
          ),
          child: Row(children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.primaryColor),
            const SizedBox(width: 8),
            CustomText(
              text: '${DateFormat('MMM d').format(c.from.value)} — ${DateFormat('MMM d, y').format(c.to.value)}',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.black2,
            ),
            const Spacer(),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.iosGrey),
          ]),
        ),
      )),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final PosRangeReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _Metric(label: 'Revenue', value: '\$${report.totalRevenue.toStringAsFixed(2)}', color: AppColors.primaryColor)),
      const SizedBox(width: 10),
      Expanded(child: _Metric(label: 'Net', value: '\$${report.netRevenue.toStringAsFixed(2)}', color: AppColors.green2)),
      const SizedBox(width: 10),
      Expanded(child: _Metric(label: 'Transactions', value: '${report.totalTransactions}', color: AppColors.orange)),
    ]);
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Metric({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        CustomText(text: value, fontSize: AppFontSize.small, fontWeight: FontWeight.bold, color: color),
        const SizedBox(height: 4),
        CustomText(text: label, fontSize: AppFontSize.tiny, color: AppColors.iosGrey, textAlign: TextAlign.center),
      ]),
    );
  }
}

class _DailyBreakdown extends StatelessWidget {
  final PosRangeReportModel report;
  const _DailyBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final maxTotal = report.dailyBreakdown.fold(0.0, (m, d) => d.total > m ? d.total : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CustomText(text: 'Daily Revenue', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
        const SizedBox(height: 12),
        ...report.dailyBreakdown.map((d) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            SizedBox(width: 60, child: CustomText(text: DateFormat('MMM d').format(DateTime.parse(d.date)), fontSize: AppFontSize.tiny, color: AppColors.iosGrey)),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: maxTotal > 0 ? d.total / maxTotal : 0,
                  backgroundColor: AppColors.background,
                  color: AppColors.primaryColor,
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: CustomText(text: '\$${d.total.toStringAsFixed(0)}', fontSize: AppFontSize.tiny, textAlign: TextAlign.right, color: AppColors.black2),
            ),
          ]),
        )),
      ]),
    );
  }
}

class _TopProducts extends StatelessWidget {
  final PosRangeReportModel report;
  const _TopProducts({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CustomText(text: 'Top Products', fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
        const SizedBox(height: 10),
        ...report.topProducts.map((p) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(child: CustomText(text: p.name, fontSize: AppFontSize.verySmall, color: AppColors.black2, maxLines: 1, overflow: TextOverflow.ellipsis)),
            CustomText(text: '${p.qty} sold', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
            const SizedBox(width: 8),
            CustomText(text: '\$${p.revenue.toStringAsFixed(2)}', fontSize: AppFontSize.verySmall, fontWeight: FontWeight.bold, color: AppColors.primaryColor),
          ]),
        )),
      ]),
    );
  }
}
