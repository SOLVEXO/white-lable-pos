import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_session_report/controllers/pos_session_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_session_report/widgets/pos_session_report_shimmer.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSessionReportView extends StatelessWidget {
  PosSessionReportView({super.key});

  final PosSessionReportController c = Get.put(PosSessionReportController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Session Report',
        color: AppColors.black2,
        actions: [
          GestureDetector(
            onTap: c.refreshData,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.refresh_rounded, color: AppColors.primaryColor, size: 22),
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSessionReportShimmer();
        }
        final report = c.report.value;
        if (report == null) {
          return const Center(child: CustomText(text: 'Report not found.', fontSize: AppFontSize.small2, color: AppColors.iosGrey));
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: AppColors.primaryColor,
          child: ListView(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            children: [
              _SessionHeader(report: report),
              const SizedBox(height: 16),
              _SummaryGrid(report: report),
              const SizedBox(height: 16),
              _PaymentBreakdown(report: report),
              const SizedBox(height: 16),
              _CashFlowCard(report: report),
            ],
          ),
        );
      }),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  final PosSessionReportModel report;
  const _SessionHeader({required this.report});

  @override
  Widget build(BuildContext context) {
    final session = report.session;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (session.isOpen ? AppColors.green2 : AppColors.iosGrey).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: CustomText(
              text: session.isOpen ? 'Open' : (session.isForceClosed ? 'Force Closed' : 'Closed'),
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: session.isOpen ? AppColors.green2 : AppColors.iosGrey,
            ),
          ),
        ]),
        const SizedBox(height: 8),
        CustomText(
          text: 'Opened ${DateFormat('MMM d, h:mm a').format(session.openedAt.toLocal())}',
          fontSize: AppFontSize.tiny,
          color: AppColors.iosGrey,
        ),
        if (session.closedAt != null)
          CustomText(
            text: 'Closed ${DateFormat('MMM d, h:mm a').format(session.closedAt!.toLocal())}',
            fontSize: AppFontSize.tiny,
            color: AppColors.iosGrey,
          ),
        if (session.isForceClosed && session.forceCloseReason != null) ...[
          const SizedBox(height: 6),
          CustomText(text: 'Reason: ${session.forceCloseReason}', fontSize: AppFontSize.tiny, color: AppColors.orange),
        ],
      ]),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final PosSessionReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _Metric(label: 'Total Sales', value: '\$${report.totalSales.toStringAsFixed(2)}', color: AppColors.primaryColor)),
      const SizedBox(width: 10),
      Expanded(child: _Metric(label: 'Transactions', value: '${report.totalTransactions}', color: AppColors.orange)),
      const SizedBox(width: 10),
      Expanded(child: _Metric(label: 'Refunds', value: '\$${report.refundsTotal.toStringAsFixed(2)}', color: AppColors.red)),
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

class _PaymentBreakdown extends StatelessWidget {
  final PosSessionReportModel report;
  const _PaymentBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final b = report.byPaymentMethod;
    return _SectionCard(
      title: 'Payment Methods',
      child: Column(children: [
        _PayRow(label: 'Cash', count: b.cash.count, amount: b.cash.total),
        const SizedBox(height: 8),
        _PayRow(label: 'Card', count: b.card.count, amount: b.card.total),
        const SizedBox(height: 8),
        _PayRow(label: 'Other', count: b.other.count, amount: b.other.total),
      ]),
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label;
  final int count;
  final double amount;
  const _PayRow({required this.label, required this.count, required this.amount});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CustomText(text: label, fontSize: AppFontSize.verySmall, color: AppColors.black2),
      const SizedBox(width: 6),
      CustomText(text: '($count)', fontSize: AppFontSize.tiny, color: AppColors.iosGrey),
      const Spacer(),
      CustomText(text: '\$${amount.toStringAsFixed(2)}', fontSize: AppFontSize.verySmall, fontWeight: FontWeight.w600, color: AppColors.black2),
    ]);
  }
}

class _CashFlowCard extends StatelessWidget {
  final PosSessionReportModel report;
  const _CashFlowCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final cf = report.cashFlow;
    return _SectionCard(
      title: 'Cash Drawer',
      child: Column(children: [
        _row('Opening Cash', cf.openingCash),
        _row('Cash Sales', cf.cashSales),
        _row('Cash In', cf.cashIn),
        _row('Cash Out', -cf.cashOut),
        _row('Expected Cash', cf.expectedCash, bold: true),
        if (cf.closingCash != null) _row('Closing Cash (counted)', cf.closingCash!),
        if (cf.cashDifference != null)
          _row('Difference', cf.cashDifference!, color: cf.isShortfall ? AppColors.red : AppColors.green2, bold: true),
      ]),
    );
  }

  Widget _row(String label, double amount, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        CustomText(text: label, fontSize: AppFontSize.verySmall, fontWeight: bold ? FontWeight.bold : FontWeight.w400, color: AppColors.black2),
        const Spacer(),
        CustomText(
          text: '${amount < 0 ? '-' : ''}\$${amount.abs().toStringAsFixed(2)}',
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: color ?? AppColors.black2,
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
        boxShadow: [BoxShadow(color: AppColors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CustomText(text: title, fontSize: AppFontSize.small2, fontWeight: FontWeight.bold, color: AppColors.black2),
        const SizedBox(height: 12),
        const Divider(height: 1, color: AppColors.lightGrey2),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }
}
