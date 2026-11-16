import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:solvexo_pos/app/modules/pos_session_report/controllers/pos_session_report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_session_report/widgets/pos_session_report_shimmer.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class PosSessionReportView extends StatelessWidget {
  PosSessionReportView({super.key});

  final PosSessionReportController c = Get.put(PosSessionReportController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'Session Report',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: c.refreshData,
          icon: Icon(Icons.refresh_rounded, color: p.accentFg, size: IconSizes.md),
        ),
      ],
      body: Obx(() {
        if (c.isLoading.value) {
          return const PosSessionReportShimmer();
        }
        final report = c.report.value;
        if (report == null) {
          return const EmptyState(icon: Icons.receipt_long_outlined, title: 'Report not found.');
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              _SessionHeader(report: report),
              const SizedBox(height: Space.s4),
              _SummaryGrid(report: report),
              const SizedBox(height: Space.s4),
              _PaymentBreakdown(report: report),
              const SizedBox(height: Space.s4),
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
    final p = context.palette;
    final t = context.type;
    final session = report.session;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusBadge(
            session.isOpen ? 'Open' : (session.isForceClosed ? 'Force Closed' : 'Closed'),
            tone: session.isOpen ? StatusTone.success : StatusTone.neutral,
            dot: true,
          ),
          const SizedBox(height: Space.s2),
          Text('Opened ${DateFormat('MMM d, h:mm a').format(session.openedAt.toLocal())}', style: t.bodySmall.copyWith(color: p.textSecondary)),
          if (session.closedAt != null)
            Text('Closed ${DateFormat('MMM d, h:mm a').format(session.closedAt!.toLocal())}', style: t.bodySmall.copyWith(color: p.textSecondary)),
          if (session.isForceClosed && session.forceCloseReason != null) ...[
            const SizedBox(height: Space.s2),
            Text('Reason: ${session.forceCloseReason}', style: t.bodySmall.copyWith(color: p.warningFg)),
          ],
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final PosSessionReportModel report;
  const _SummaryGrid({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tiles = [
      _Metric(label: 'Total Sales', value: Money.format(report.totalSales), color: p.accentFg),
      _Metric(label: 'Transactions', value: '${report.totalTransactions}', color: p.textPrimary),
      _Metric(label: 'Refunds', value: Money.format(report.refundsTotal), color: p.dangerFg),
    ];
    if (MediaQuery.textScalerOf(context).scale(16) > 19) {
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
      padding: const EdgeInsets.symmetric(vertical: Space.s3, horizontal: Space.s3),
      child: Column(
        children: [
          AmountText(value, style: context.type.amountMd, color: color, animate: false, alignment: MainAxisAlignment.center),
          const SizedBox(height: Space.s1),
          Text(label, style: context.type.caption.copyWith(color: p.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _PaymentBreakdown extends StatelessWidget {
  final PosSessionReportModel report;
  const _PaymentBreakdown({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final b = report.byPaymentMethod;
    return _SectionCard(
      title: 'Payment Methods',
      child: Column(
        children: [
          _PayRow(label: 'Cash', count: b.cash.count, amount: b.cash.total),
          const SizedBox(height: Space.s2),
          _PayRow(label: 'Card', count: b.card.count, amount: b.card.total),
          // G5.4: the part of the card total taken on a separate bank terminal — to match against the terminal's own settlement slip
          if (report.cardTerminalCount > 0) ...[
            const SizedBox(height: Space.s2),
            _PayRow(key: const Key('cardTerminalRow'), label: '  on bank terminal', count: report.cardTerminalCount, amount: report.cardTerminalTotal),
            if (report.cardTerminalApprovalCodes.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('  Approval codes: ${report.cardTerminalApprovalCodes.join(', ')}', style: context.type.bodySmall.copyWith(color: p.textSecondary)),
              ),
          ],
          const SizedBox(height: Space.s2),
          _PayRow(label: 'Other', count: b.other.count, amount: b.other.total),
        ],
      ),
    );
  }
}

class _PayRow extends StatelessWidget {
  final String label;
  final int count;
  final double amount;
  const _PayRow({super.key, required this.label, required this.count, required this.amount});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Row(
      children: [
        Flexible(child: Text(label, style: t.body.copyWith(color: p.textPrimary))),
        const SizedBox(width: Space.s1),
        Text('($count)', style: t.caption.copyWith(color: p.textMuted)),
        const SizedBox(width: Space.s3),
        const Spacer(),
        Flexible(
          flex: 2,
          child: AmountText(Money.format(amount), style: t.amountMd, color: p.textPrimary, animate: false, alignment: MainAxisAlignment.end),
        ),
      ],
    );
  }
}

class _CashFlowCard extends StatelessWidget {
  final PosSessionReportModel report;
  const _CashFlowCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final cf = report.cashFlow;
    return _SectionCard(
      title: 'Cash Drawer',
      child: Column(
        children: [
          _row(context, 'Opening Cash', cf.openingCash),
          _row(context, 'Cash Sales', cf.cashSales),
          _row(context, 'Cash In', cf.cashIn),
          _row(context, 'Cash Out', -cf.cashOut),
          _row(context, 'Expected Cash', cf.expectedCash, bold: true),
          if (cf.closingCash != null) _row(context, 'Closing Cash (counted)', cf.closingCash!),
          if (cf.cashDifference != null) _row(context, 'Difference', cf.cashDifference!, color: cf.isShortfall ? p.dangerFg : p.successFg, bold: true),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, double amount, {Color? color, bool bold = false}) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.s1),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label, style: t.body.copyWith(color: p.textPrimary, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            flex: 2,
            child: AmountText(Money.format(amount), style: t.amountMd, color: color ?? p.textPrimary, animate: false, alignment: MainAxisAlignment.end),
          ),
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
    final p = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: context.type.title.copyWith(color: p.textPrimary))),
          const SizedBox(height: Space.s3),
          Divider(height: 1, color: p.border),
          const SizedBox(height: Space.s3),
          child,
        ],
      ),
    );
  }
}
