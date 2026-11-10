import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// What each report answers (the hub's cards).
const reportBlurbs = <ReportKind, (IconData, String)>{
  ReportKind.sales: (Icons.show_chart_rounded, 'Totals, returns and sales by day'),
  ReportKind.profit: (Icons.savings_outlined, 'Gross margin and what is left after expenses'),
  ReportKind.products: (Icons.inventory_2_outlined, 'Best sellers by sales, quantity or margin'),
  ReportKind.categories: (Icons.category_outlined, 'Sales and margin per category'),
  ReportKind.tax: (Icons.receipt_long_outlined, 'Tax by category and HS code, invoices vs credit notes'),
  ReportKind.payments: (Icons.donut_large_rounded, 'Cash, card and other tenders'),
  ReportKind.cashiers: (Icons.badge_outlined, 'Sales, voids, returns and hours per person'),
  ReportKind.hourly: (Icons.schedule_rounded, 'Busiest hours and days'),
};

/// The reports hub (managers / owner): the business pulse, the eight reports and the store's time zone. Two columns on a tablet.
class ReportsHubView extends StatelessWidget {
  const ReportsHubView({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget card(Key key, IconData icon, String title, String subtitle, VoidCallback onTap) => AppCard(
      key: key,
      radius: Radii.rMd,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: p.accentSoft, borderRadius: Radii.rSm),
            child: Icon(icon, color: p.accentFg, size: 22),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.subtitle.copyWith(color: p.textPrimary)),
                Text(subtitle, style: t.caption.copyWith(color: p.textSecondary)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
    final cards = [
      card(const Key('hub_pulse'), Icons.monitor_heart_outlined, 'Business pulse', 'Today so far vs the same day last week', () => Get.toNamed(Routes.posPulse)),
      for (final k in ReportKind.values) card(Key('hub_${k.path}'), reportBlurbs[k]!.$1, k.label, reportBlurbs[k]!.$2, () => Get.toNamed(Routes.posReport, arguments: {'kind': k.path})),
      card(const Key('hub_timeZone'), Icons.public_rounded, 'Store time zone', 'Where the store\'s day starts and ends', () => Get.toNamed(Routes.posStoreTimeZone)),
    ];
    return InvScaffold(
      title: 'Reports',
      maxWidth: 1100,
      body: LayoutBuilder(
        builder: (_, c) {
          final cols = c.maxWidth >= 700 ? 2 : 1;
          final w = (c.maxWidth - Space.s4 * 2 - Space.s3 * (cols - 1)) / cols;
          return ListView(
            key: const Key('reportsHub'),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              Text('Live from the till\'s records, in the store\'s time zone.', style: t.bodySmall.copyWith(color: p.textSecondary)),
              const SizedBox(height: Space.s3),
              Wrap(
                spacing: Space.s3,
                runSpacing: Space.s3,
                children: [for (final x in cards) SizedBox(width: w, child: x)],
              ),
            ],
          );
        },
      ),
    );
  }
}
