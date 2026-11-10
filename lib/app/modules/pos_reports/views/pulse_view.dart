import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

String _clock(DateTime? d) => d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// G4.0 business pulse (managers / owner): today so far against the same weekday last week up to the same time, with up / down chips; the top five
/// products; how many items are low on stock (opens the low-stock list) and who is clocked in now (opens attendance). Online only.
class PulseView extends StatefulWidget {
  const PulseView({super.key, this.controller});
  final BusinessPulseController? controller;
  @override
  State<PulseView> createState() => _PulseViewState();
}

class _PulseViewState extends State<PulseView> {
  late final BusinessPulseController c = widget.controller ?? (Get.isRegistered<BusinessPulseController>() ? Get.find<BusinessPulseController>() : Get.put(BusinessPulseController(), permanent: true));
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    c.load().whenComplete(() {
      if (mounted) setState(() => _asked = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Business pulse',
      maxWidth: 1100,
      actions: [IconButton(key: const Key('pulseRefresh'), tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded), onPressed: c.load)],
      body: Obx(() {
        final p = c.pulse.value;
        if (!reportsOnlineRx().value && p == null) return const ReportsNeedsInternet(subject: 'The business pulse');
        if (p == null && (c.loading.value || !_asked)) return const Center(child: CircularProgressIndicator(key: Key('pulseLoading')));
        if (p == null && c.error.value != null) return InvErrorState(message: c.error.value!, onRetry: c.load);
        if (p == null) {
          return const EmptyState(key: Key('pulseManagersOnly'), icon: Icons.lock_outline_rounded, title: 'Managers only', message: 'Only managers and the owner see the business pulse.');
        }
        return RefreshIndicator(
          onRefresh: c.load,
          child: _PulseBody(p: p),
        );
      }),
    );
  }
}

class _PulseBody extends StatelessWidget {
  const _PulseBody({required this.p});
  final BusinessPulse p;
  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = context.type;
    final m = p.head.money;
    final a = p.today, b = p.lastWeek;
    ReportStat stat(String label, String key, String now, String then, {bool goodWhenUp = true}) =>
        ReportStat(label: label, value: now, change: p.change[key], compared: true, goodWhenUp: goodWhenUp, note: 'Last week $then', valueKey: Key('pulse_$key'));
    return ListView(
      key: const Key('pulseBody'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Text(
          'Today so far${p.asOf == null ? '' : ' · as of ${_clock(p.asOf)}'}${p.comparedDay == null ? '' : ' · compared with ${storeDayLabel(p.comparedDay!)} up to the same time'}${p.head.timeZone == null ? '' : ' · ${p.head.timeZone}'}',
          key: const Key('pulseCaption'),
          style: t.bodySmall.copyWith(color: pal.textSecondary),
        ),
        const SizedBox(height: Space.s3),
        ReportStatGrid(
          children: [
            stat('Net sales', 'netSalesMinor', m(a.netSalesMinor), m(b.netSalesMinor)),
            stat('Transactions', 'transactions', '${a.transactions}', '${b.transactions}'),
            stat('Average basket', 'averageBasketMinor', m(a.averageBasketMinor), m(b.averageBasketMinor)),
            stat('Gross margin', 'grossMarginMinor', m(a.grossMarginMinor), m(b.grossMarginMinor)),
            stat('Cash', 'cashMinor', m(a.cashMinor), m(b.cashMinor)),
            stat('Card', 'cardMinor', m(a.cardMinor), m(b.cardMinor)),
            stat('Returns', 'returnsMinor', m(a.returnsMinor), m(b.returnsMinor), goodWhenUp: false),
            stat('Expenses', 'expensesMinor', m(a.expensesMinor), m(b.expensesMinor), goodWhenUp: false),
          ],
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Expanded(
              child: AppCard(
                key: const Key('pulseLowStock'),
                radius: Radii.rMd,
                onTap: () => Get.toNamed(Routes.posStockList, arguments: {'lowOnly': true}),
                child: _Count(icon: Icons.inventory_2_outlined, count: p.lowStockCount, label: p.lowStockCount == 1 ? 'item low on stock' : 'items low on stock', warn: p.lowStockCount > 0),
              ),
            ),
            const SizedBox(width: Space.s2),
            Expanded(
              child: AppCard(
                key: const Key('pulseClockedIn'),
                radius: Radii.rMd,
                onTap: () => Get.toNamed(Routes.posTeamAttendance),
                child: _Count(icon: Icons.badge_outlined, count: p.clockedInNow, label: 'clocked in now'),
              ),
            ),
          ],
        ),
        const InvSectionTitle('Top products today'),
        if (p.topProducts.isEmpty)
          Text(
            'Nothing sold yet today.',
            key: const Key('pulseNoTop'),
            style: t.body.copyWith(color: pal.textMuted),
          )
        else
          for (var i = 0; i < p.topProducts.length; i++)
            ReportRow(
              key: Key('pulseTop_$i'),
              title: '${i + 1}. ${p.topProducts[i].name}',
              subtitle: '${_n(p.topProducts[i].qty)} sold',
              value: m(p.topProducts[i].netSalesMinor),
              onTap: p.topProducts[i].variantId == null ? null : () => Get.toNamed(Routes.posStockDetail, arguments: {'variantId': p.topProducts[i].variantId, 'role': 'manager'}),
            ),
        const SizedBox(height: Space.s4),
        AppButton(key: const Key('pulseAllReports'), label: 'All reports', icon: Icons.insights_outlined, variant: AppButtonVariant.secondary, onPressed: () => Get.toNamed(Routes.posReports)),
      ],
    );
  }
}

String _n(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.count, required this.label, this.warn = false});
  final IconData icon;
  final int count;
  final String label;
  final bool warn;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      children: [
        Icon(icon, color: warn ? p.warningFg : p.textSecondary),
        const SizedBox(width: Space.s2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: context.type.amountMd.copyWith(color: warn ? p.warningFg : p.textPrimary)),
              Text(label, style: context.type.caption.copyWith(color: p.textSecondary)),
            ],
          ),
        ),
        Icon(Icons.chevron_right_rounded, color: p.textMuted),
      ],
    );
  }
}
