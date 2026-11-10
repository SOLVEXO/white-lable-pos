import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/report_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/charts/charts.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/report_export.dart';

double? changePercent(int now, int? before) => before == null || before == 0 ? null : ((now - before) / before.abs() * 1000).roundToDouble() / 10;

/// "Nothing sold in this period" — one wording for every report.
class ReportEmpty extends StatelessWidget {
  const ReportEmpty({super.key, this.message = 'Nothing was sold in this period. Pick another period above.'});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.s6),
    child: EmptyState(key: const Key('reportEmpty'), icon: Icons.insights_outlined, title: 'Nothing to show', message: message),
  );
}

/// The body of a report, by kind.
class ReportBody extends StatelessWidget {
  const ReportBody({super.key, required this.c, required this.r});
  final ReportController c;
  final BizReport r;
  @override
  Widget build(BuildContext context) => switch (r) {
    SalesReport s => _Sales(c: c, r: s),
    ProfitReport p => _Profit(c: c, r: p),
    ProductsReport p => _Products(c: c, r: p),
    CategoriesReport x => _Categories(r: x),
    TaxReport x => _Tax(r: x),
    PaymentsReport x => _Payments(r: x),
    CashiersReport x => _Cashiers(c: c, r: x),
    HourlyReport x => _Hourly(r: x),
  };
}

/// Two columns when the screen is wide (chart beside the figures), one on a phone.
class _TwoUp extends StatelessWidget {
  const _TwoUp({required this.left, required this.right});
  final Widget left, right;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, c) => c.maxWidth >= 760
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: Space.s4),
              Expanded(child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              left,
              const SizedBox(height: Space.s3),
              right,
            ],
          ),
  );
}

// ── sales ─────────────────────────────────────────────────────────────────────
class _Sales extends StatelessWidget {
  const _Sales({required this.c, required this.r});
  final ReportController c;
  final SalesReport r;
  @override
  Widget build(BuildContext context) {
    final t = r.totals;
    final prev = r.previous;
    final exp = r.head.cur?.exponent ?? 2;
    if (t.transactions == 0 && t.returns == 0 && prev == null) return const ReportEmpty();
    final stats = ReportStatGrid(
      children: [
        ReportStat(
          label: 'Net sales (ex tax, after returns)',
          value: r.head.money(t.netSalesMinor),
          change: prev == null ? null : changePercent(t.netSalesMinor, prev.netSalesMinor),
          valueKey: const Key('salesNet'),
        ),
        ReportStat(label: 'Transactions', value: '${t.transactions}', change: prev == null ? null : changePercent(t.transactions, prev.transactions)),
        ReportStat(label: 'Average basket', value: r.head.money(t.averageBasketMinor), change: prev == null ? null : changePercent(t.averageBasketMinor, prev.averageBasketMinor)),
        ReportStat(label: 'Gross sales (incl. tax)', value: r.head.money(t.grossSalesMinor)),
        ReportStat(label: 'Tax', value: r.head.money(t.taxMinor)),
        ReportStat(label: 'Discounts', value: r.head.money(t.discountMinor)),
        ReportStat(label: 'Returns', value: '${t.returns} · ${r.head.money(t.returnsMinor)}', change: prev == null ? null : changePercent(t.returnsMinor, prev.returnsMinor), goodWhenUp: false),
      ],
    );
    final chart = r.byDay.length < 2
        ? const SizedBox.shrink()
        : Obx(() {
            final prevDays = c.previousByDay.toList();
            return AppCard(
              radius: Radii.rMd,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const InvSectionTitle('Sales by day'),
                  LineChart(
                    key: const Key('salesByDay'),
                    current: [for (final d in r.byDay) d.totalMinor.toDouble()],
                    previous: prev == null || prevDays.isEmpty ? null : [for (final d in prevDays) d.totalMinor.toDouble()],
                    labels: [for (final d in r.byDay) storeDayLabel(d.day, weekday: false)],
                    axisLabel: (v) => compactMajor(v, exp),
                    semanticsLabel:
                        'Sales by day, ${periodText(r.head)}: ${[for (final d in r.byDay) '${storeDayLabel(d.day)} ${r.head.money(d.totalMinor)}'].join(', ')}${prev == null ? '' : '. Previous period total ${r.head.money(prev.grossSalesMinor)}'}',
                  ),
                ],
              ),
            );
          });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prev != null) ReportInfo('Compared with ${storeDayLabel(r.previousFrom ?? '')} - ${storeDayLabel(r.previousTo ?? '')}. The arrows show the change.', icon: Icons.compare_arrows_rounded),
        _TwoUp(left: stats, right: chart),
        if (r.byDay.isNotEmpty) ...[
          const InvSectionTitle('By day'),
          for (final d in r.byDay)
            ReportRow(
              key: Key('salesDay_${d.day}'),
              title: storeDayLabel(d.day),
              subtitle: '${d.transactions} sale${d.transactions == 1 ? '' : 's'}',
              value: r.head.money(d.totalMinor),
              // a day with sales opens the list of that STORE day's sales
              onTap: d.transactions == 0 ? null : () => Get.toNamed(Routes.posDayOrders, arguments: {'date': d.day}),
            ),
        ],
      ],
    );
  }
}

// ── profit ────────────────────────────────────────────────────────────────────
class _Profit extends StatelessWidget {
  const _Profit({required this.c, required this.r});
  final ReportController c;
  final ProfitReport r;
  @override
  Widget build(BuildContext context) {
    final t = r.totals;
    final prev = r.previous;
    final m = r.head.money;
    final pal = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (t.netSalesMinor == 0 && t.expensesMinor == 0) const ReportEmpty(message: 'No sales and no expenses in this period. Pick another period above.'),
        ReportStatGrid(
          children: [
            ReportStat(label: 'Net sales (ex tax)', value: m(t.netSalesMinor), change: prev == null ? null : changePercent(t.netSalesMinor, prev.netSalesMinor)),
            ReportStat(label: 'Cost of goods sold', value: m(t.costOfGoodsSoldMinor)),
            ReportStat(
              label: 'Gross margin',
              value: m(t.grossMarginMinor),
              valueKey: const Key('profitGross'),
              note: t.marginPercent == null ? null : '${t.marginPercent!.toStringAsFixed(1)} % of sales with a cost',
              change: prev == null ? null : changePercent(t.grossMarginMinor, prev.grossMarginMinor),
            ),
            ReportStat(label: 'Expenses', value: m(t.expensesMinor), change: prev == null ? null : changePercent(t.expensesMinor, prev.expensesMinor), goodWhenUp: false),
            ReportStat(
              label: 'After expenses',
              value: m(t.afterExpensesMinor),
              valueKey: const Key('profitAfter'),
              change: prev == null ? null : changePercent(t.afterExpensesMinor, prev.afterExpensesMinor),
            ),
            ReportStat(label: 'Cost coverage', value: t.costCoveragePercent == null ? '—' : '${t.costCoveragePercent!.toStringAsFixed(1)} %', valueKey: const Key('profitCoverage')),
          ],
        ),
        const SizedBox(height: Space.s3),
        Text('What the figures mean', style: context.type.subtitle.copyWith(color: pal.textPrimary)),
        const SizedBox(height: Space.s1),
        Text(
          r.grossMarginLabel ?? 'Gross margin: net sales − cost of goods sold',
          key: const Key('profitGrossLabel'),
          style: context.type.bodySmall.copyWith(color: pal.textSecondary),
        ),
        Text(
          r.afterExpensesLabel ?? 'After expenses: gross margin − recorded expenses',
          key: const Key('profitAfterLabel'),
          style: context.type.bodySmall.copyWith(color: pal.textSecondary),
        ),
        const SizedBox(height: Space.s3),
        if (t.partialCoverage)
          ReportInfo(
            key: const Key('profitCoverageNote'),
            'Only ${t.costCoveragePercent!.toStringAsFixed(1)} % of net sales have a known cost. ${m(t.costUnknownNetMinor)} of sales come from items with no cost price, so they are left out of the margin (never guessed). Add cost prices to those products to complete it.',
            icon: Icons.warning_amber_rounded,
            warn: true,
          ),
        if (t.supplierPaymentsNote != null) ReportInfo(key: const Key('profitSupplierNote'), '${t.supplierPaymentsNote!} Supplier payments in this period: ${m(t.supplierPaymentsMinor)}.'),
        if (t.expensesByCategoryMinor.isNotEmpty) ...[
          const InvSectionTitle('Expenses by category'),
          for (final e in t.expensesByCategoryMinor.entries) ReportRow(title: '${e.key[0].toUpperCase()}${e.key.substring(1).replaceAll('_', ' ')}', value: m(e.value)),
        ],
      ],
    );
  }
}

// ── products ──────────────────────────────────────────────────────────────────
class _Products extends StatelessWidget {
  const _Products({required this.c, required this.r});
  final ReportController c;
  final ProductsReport r;
  @override
  Widget build(BuildContext context) {
    final m = r.head.money;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => Wrap(
            spacing: Space.s2,
            children: [
              for (final s in const [('net', 'Net sales'), ('qty', 'Quantity'), ('margin', 'Margin')])
                ChoiceChip(key: Key('sort_${s.$1}'), label: Text('By ${s.$2.toLowerCase()}'), selected: c.sort.value == s.$1, onSelected: (_) => c.setSort(s.$1)),
            ],
          ),
        ),
        const SizedBox(height: Space.s2),
        if (r.products.isEmpty)
          const ReportEmpty()
        else ...[
          if (r.count > r.products.length) Text('Top ${r.products.length} of ${r.count}', style: context.type.caption.copyWith(color: context.palette.textMuted)),
          for (final x in r.products)
            ReportRow(
              key: Key('product_${x.variantId ?? 'custom'}'),
              title: x.name,
              subtitle: [if (x.sku != null) x.sku!, '${_q(x.qtySold)} sold', if (x.qtyReturned != 0) '${_q(x.qtyReturned)} returned'].join(' · '),
              value: m(x.netSalesMinor),
              detail: x.marginPercent == null ? 'Margin unknown (no cost)' : 'Margin ${m(x.grossMarginMinor)} · ${x.marginPercent!.toStringAsFixed(1)} %',
              onTap: x.variantId == null ? null : () => Get.toNamed(Routes.posStockDetail, arguments: {'variantId': x.variantId, 'role': c.canManage.value ? 'manager' : null}),
            ),
        ],
      ],
    );
  }
}

String _q(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ── categories ────────────────────────────────────────────────────────────────
class _Categories extends StatelessWidget {
  const _Categories({required this.r});
  final CategoriesReport r;
  @override
  Widget build(BuildContext context) {
    if (r.categories.isEmpty) return const ReportEmpty();
    final m = r.head.money;
    final exp = r.head.cur?.exponent ?? 2;
    final top = r.categories.take(12).toList();
    return _TwoUp(
      left: AppCard(
        radius: Radii.rMd,
        child: BarChart(
          key: const Key('categoryBars'),
          bars: [for (final x in top) ChartBar(label: x.name.length > 8 ? '${x.name.substring(0, 7)}…' : x.name, value: x.netSalesMinor.toDouble(), valueText: m(x.netSalesMinor))],
          axisLabel: (v) => compactMajor(v, exp),
          semanticsLabel: 'Net sales by category: ${[for (final x in r.categories) '${x.name} ${m(x.netSalesMinor)}'].join(', ')}',
        ),
      ),
      right: Column(
        children: [
          for (final x in r.categories)
            ReportRow(title: x.name, subtitle: '${_q(x.qty)} sold', value: m(x.netSalesMinor), detail: x.marginPercent == null ? 'Margin unknown' : 'Margin ${x.marginPercent!.toStringAsFixed(1)} %'),
        ],
      ),
    );
  }
}

// ── tax ───────────────────────────────────────────────────────────────────────
class _Tax extends StatelessWidget {
  const _Tax({required this.r});
  final TaxReport r;
  @override
  Widget build(BuildContext context) {
    final m = r.head.money;
    final tt = r.totals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReportStatGrid(
          children: [
            ReportStat(label: 'Net tax', value: m(tt.netTaxMinor), valueKey: const Key('taxNet')),
            ReportStat(label: 'Invoices', value: '${tt.invoices}', note: 'Tax ${m(tt.invoiceTaxMinor)}'),
            ReportStat(label: 'Credit notes', value: '${tt.creditNotes}', note: 'Tax ${m(tt.creditNoteTaxMinor)}'),
          ],
        ),
        const SizedBox(height: Space.s2),
        Text('Net tax = tax on invoices − tax on credit notes.', style: context.type.caption.copyWith(color: context.palette.textMuted)),
        const InvSectionTitle('By tax category and HS code'),
        if (r.rows.isEmpty)
          const ReportEmpty()
        else
          for (final x in r.rows)
            ReportRow(
              key: Key('tax_${x.taxCategory}_${x.hsCode ?? ''}'),
              title: taxCategoryLabel(x.taxCategory),
              subtitle: '${x.hsCode == null ? 'No HS code' : 'HS ${x.hsCode}'} · net ${m(x.netMinor)}',
              value: m(x.taxMinor),
              detail: 'Sales ${m(x.salesTaxMinor)} · returns ${m(x.returnsTaxMinor)}',
            ),
      ],
    );
  }
}

// ── payment mix ───────────────────────────────────────────────────────────────
class _Payments extends StatelessWidget {
  const _Payments({required this.r});
  final PaymentsReport r;
  @override
  Widget build(BuildContext context) {
    if (r.methods.isEmpty) return const ReportEmpty();
    final m = r.head.money;
    return _TwoUp(
      left: AppCard(
        radius: Radii.rMd,
        child: DonutChart(
          key: const Key('paymentDonut'),
          slices: [for (final x in r.methods) DonutSlice(label: paymentMethodLabel(x.method), value: x.netMinor.toDouble())],
          centerText: m(r.netMinor),
          semanticsLabel:
              'Payment mix, net ${m(r.netMinor)}: ${[for (final x in r.methods) '${paymentMethodLabel(x.method)} ${x.sharePercent.toStringAsFixed(1)} percent, ${m(x.netMinor)}'].join(', ')}',
        ),
      ),
      right: Column(
        children: [
          for (final x in r.methods)
            ReportRow(
              key: Key('pay_${x.method}'),
              title: paymentMethodLabel(x.method),
              subtitle: '${x.payments} payment${x.payments == 1 ? '' : 's'} · ${x.sharePercent.toStringAsFixed(1)} %',
              value: m(x.netMinor),
              detail: 'Paid ${m(x.paidMinor)} · refunded ${m(x.refundedMinor)}',
            ),
        ],
      ),
    );
  }
}

// ── cashiers ──────────────────────────────────────────────────────────────────
class _Cashiers extends StatelessWidget {
  const _Cashiers({required this.c, required this.r});
  final ReportController c;
  final CashiersReport r;
  @override
  Widget build(BuildContext context) {
    final m = r.head.money;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.ownOnly) const ReportInfo(key: Key('cashiersOwnOnly'), 'Only your own sales are shown.', icon: Icons.person_outline_rounded),
        if (c.employeeId.value != null && !r.ownOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: InputChip(key: const Key('cashierFilterChip'), label: Text(r.cashiers.firstOrNull?.name ?? 'One cashier'), onDeleted: () => c.setEmployee(null)),
          ),
        if (r.cashiers.isEmpty)
          const ReportEmpty(message: 'No sales or shifts in this period. Pick another period above.')
        else
          for (final x in r.cashiers)
            ReportRow(
              key: Key('cashier_${x.employeeId}'),
              title: x.name,
              subtitle: '${x.transactions} sale${x.transactions == 1 ? '' : 's'} · avg ${m(x.averageBasketMinor)} · worked ${hoursMinutes(x.workedMinutes)}',
              value: m(x.netSalesMinor),
              detail: 'Discounts ${m(x.discountsMinor)} · returns ${x.returnsProcessed} · voids ${x.voids}',
              onTap: r.ownOnly || c.employeeId.value != null || r.cashiers.length < 2 ? null : () => c.setEmployee(x.employeeId),
            ),
      ],
    );
  }
}

// ── hourly ────────────────────────────────────────────────────────────────────
class _Hourly extends StatelessWidget {
  const _Hourly({required this.r});
  final HourlyReport r;
  @override
  Widget build(BuildContext context) {
    if (r.isEmpty) return const ReportEmpty();
    final m = r.head.money;
    final exp = r.head.cur?.exponent ?? 2;
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    var bestDay = -1, bestHour = -1, best = 0;
    for (var d = 0; d < r.heat.length; d++) {
      for (var h = 0; h < r.heat[d].length; h++) {
        if (r.heat[d][h] > best) (bestDay, bestHour, best) = (d, h, r.heat[d][h]);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.busiestHour != null)
          ReportInfo(
            key: const Key('busiestHour'),
            'Busiest hour: ${hourLabel(r.busiestHour!)} - ${hourLabel((r.busiestHour! + 1) % 24)} (${m(r.byHour[r.busiestHour!].totalMinor)}, ${r.byHour[r.busiestHour!].transactions} sales)',
            icon: Icons.local_fire_department_outlined,
          ),
        _TwoUp(
          left: AppCard(
            radius: Radii.rMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InvSectionTitle('Sales by hour'),
                BarChart(
                  key: const Key('hourBars'),
                  bars: [for (final h in r.byHour) ChartBar(label: h.hour.toString().padLeft(2, '0'), value: h.totalMinor.toDouble(), valueText: '${m(h.totalMinor)} · ${h.transactions} sales')],
                  highlight: r.busiestHour,
                  axisLabel: (v) => compactMajor(v, exp),
                  semanticsLabel:
                      'Sales by hour. ${r.busiestHour == null ? '' : 'Busiest ${hourLabel(r.busiestHour!)}. '}${[for (final h in r.byHour.where((h) => h.transactions > 0)) '${hourLabel(h.hour)} ${m(h.totalMinor)}'].join(', ')}',
                ),
              ],
            ),
          ),
          right: AppCard(
            radius: Radii.rMd,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InvSectionTitle('Weekday × hour'),
                HeatmapChart(
                  key: const Key('hourHeatmap'),
                  values: r.heat,
                  semanticsLabel: bestDay < 0 ? 'Weekday by hour: no sales' : 'Weekday by hour heatmap. Busiest: ${days[bestDay]} ${hourLabel(bestHour)}, ${m(best)}.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
