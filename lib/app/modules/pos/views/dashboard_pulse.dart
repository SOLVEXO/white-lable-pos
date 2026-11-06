import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_dashboard_model.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// The Home business pulse from the server's dashboard: sales, orders, average sale, refunds, top products, payment mix, low stock,
/// what needs attention and the open shift(s). A cashier gets only their own shift (the server decides); the manager-only parts are simply
/// absent from their answer.
class DashboardPulse extends StatelessWidget {
  const DashboardPulse({super.key, required this.d, this.onAttention});
  final PosDashboard d;
  final VoidCallback? onAttention;

  String _m(num v) => Money.format(v, currency: d.currency, exponent: d.exponent);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final maxMix = d.paymentMix.fold<double>(0, (a, b) => b.total > a ? b.total : a);
    return Column(
      key: const Key('dashboardPulse'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(d.isShiftScope ? 'Your shift so far' : 'Today'),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Sales', value: _m(d.netRevenue), keyName: 'pulseSales')),
            const SizedBox(width: Space.s2),
            Expanded(child: _Stat(label: 'Orders', value: '${d.orders}', keyName: 'pulseOrders')),
          ],
        ),
        const SizedBox(height: Space.s2),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Average sale', value: _m(d.average), keyName: 'pulseAverage')),
            const SizedBox(width: Space.s2),
            Expanded(child: _Stat(label: 'Refunds', value: _m(d.refunds), keyName: 'pulseRefunds', tone: d.refunds > 0 ? p.dangerFg : null)),
          ],
        ),
        if (d.showsAttention && d.attentionTotal > 0) ...[
          const SizedBox(height: Space.s2),
          AppCard(
            key: const Key('pulseAttention'),
            radius: Radii.rMd,
            color: p.warningSoft,
            child: InkWell(
              onTap: onAttention,
              child: Row(
                children: [
                  Icon(Icons.priority_high_rounded, color: p.warningFg),
                  const SizedBox(width: Space.s2),
                  Expanded(child: Text('${d.attentionTotal} ${d.attentionTotal == 1 ? 'item needs' : 'items need'} attention', style: t.subtitle.copyWith(color: p.warningFg))),
                  Icon(Icons.chevron_right_rounded, color: p.warningFg),
                ],
              ),
            ),
          ),
        ],
        if (d.topProducts.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          const SectionHeader('Top products'),
          AppCard(
            key: const Key('pulseTop'),
            radius: Radii.rMd,
            child: Column(
              children: [
                for (final tp in d.topProducts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s1),
                    child: Row(children: [Expanded(child: Text(tp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(color: p.textPrimary))), Text('×${tp.qty}', style: t.caption.copyWith(color: p.textMuted)), const SizedBox(width: Space.s3), Text(_m(tp.revenue), style: t.amountMd.copyWith(color: p.textPrimary))]),
                  ),
              ],
            ),
          ),
        ],
        if (d.paymentMix.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          const SectionHeader('Payment mix'),
          AppCard(
            key: const Key('pulseMix'),
            radius: Radii.rMd,
            child: Column(
              children: [
                for (final pm in d.paymentMix)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Space.s1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Expanded(child: Text(_label(pm.method), style: t.body.copyWith(color: p.textPrimary))), Text('${pm.count}', style: t.caption.copyWith(color: p.textMuted)), const SizedBox(width: Space.s3), Text(_m(pm.total), style: t.amountMd.copyWith(color: p.textPrimary))]),
                        const SizedBox(height: 4),
                        ClipRRect(borderRadius: Radii.rFull, child: LinearProgressIndicator(value: maxMix <= 0 ? 0 : (pm.total / maxMix).clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: p.fill, color: p.accent)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (d.lowStock.isNotEmpty) ...[
          const SizedBox(height: Space.s4),
          SectionHeader('Low stock (${d.lowStockCount})'),
          AppCard(
            key: const Key('pulseLowStock'),
            radius: Radii.rMd,
            child: Column(
              children: [
                for (final ls in d.lowStock.take(5))
                  Padding(padding: const EdgeInsets.symmetric(vertical: Space.s1), child: Row(children: [Expanded(child: Text(ls.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(color: p.textPrimary))), StatusBadge('${ls.stock} left', tone: ls.stock <= 3 ? StatusTone.danger : StatusTone.warning)])),
              ],
            ),
          ),
        ],
        const SizedBox(height: Space.s4),
        SectionHeader(d.shifts.length > 1 ? 'Open shifts' : 'Shift'),
        if (d.shifts.isEmpty)
          AppCard(key: const Key('pulseNoShift'), radius: Radii.rMd, child: Text('No shift is open.', style: t.body.copyWith(color: p.textSecondary)))
        else
          for (final s in d.shifts)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: const Key('pulseShift'),
                radius: Radii.rMd,
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: p.textSecondary),
                    const SizedBox(width: Space.s3),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(s.employeeName ?? 'Till', style: t.subtitle.copyWith(color: p.textPrimary)), Text(s.openedAt == null ? 'Open' : 'Open since ${DateFormat('HH:mm').format(s.openedAt!.toLocal())} · ${s.transactions} sales', style: t.caption.copyWith(color: p.textMuted))])),
                    Text(_m(s.totalSales), style: t.amountMd.copyWith(color: p.textPrimary)),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  static String _label(String m) => switch (m) { 'cash' => 'Cash', 'card' => 'Card', 'raast_qr' => 'Raast', _ => 'Other' };
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.keyName, this.tone});
  final String label;
  final String value;
  final String keyName;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      radius: Radii.rMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.type.caption.copyWith(color: p.textMuted)),
          const SizedBox(height: Space.s1),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, key: Key(keyName), style: context.type.amountLg.copyWith(color: tone ?? p.textPrimary))),
        ],
      ),
    );
  }
}
