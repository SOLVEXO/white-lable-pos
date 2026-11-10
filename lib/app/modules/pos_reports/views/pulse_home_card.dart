import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/pulse_controller.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The compact business pulse on a manager's Home: today's net sales against the same weekday last week, transactions and the average basket.
/// Drawn only after the server answered 200 (the role / plan matrix decides); nothing at all for a cashier, who never asks.
class PulseHomeCard extends StatefulWidget {
  const PulseHomeCard({super.key, this.controller});
  final BusinessPulseController? controller;
  @override
  State<PulseHomeCard> createState() => _PulseHomeCardState();
}

class _PulseHomeCardState extends State<PulseHomeCard> {
  late final BusinessPulseController? c = widget.controller ?? (Get.isRegistered<BusinessPulseController>() ? Get.find<BusinessPulseController>() : null);

  @override
  void initState() {
    super.initState();
    c?.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = this.c;
    if (c == null) return const SizedBox.shrink();
    return Obx(() {
      final p = c.pulse.value;
      if (!c.allowed.value || p == null) return const SizedBox.shrink();
      final pal = context.palette;
      final t = context.type;
      return Padding(
        padding: const EdgeInsets.only(top: Space.s3),
        child: AppCard(
          key: const Key('pulseHomeCard'),
          radius: Radii.rMd,
          onTap: () => Get.toNamed(Routes.posPulse),
          semanticLabel: 'Business pulse: net sales today ${p.head.money(p.today.netSalesMinor)}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.monitor_heart_outlined, size: 18, color: pal.accentFg),
                  const SizedBox(width: Space.s2),
                  Expanded(
                    child: Text('Today so far vs last ${p.comparedDay == null ? 'week' : storeDayLabel(p.comparedDay!).split(' ').first}', style: t.caption.copyWith(color: pal.textSecondary)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: pal.textMuted),
                ],
              ),
              const SizedBox(height: Space.s1),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Space.s2,
                runSpacing: Space.s1,
                children: [
                  Text(
                    p.head.money(p.today.netSalesMinor),
                    key: const Key('pulseHomeNet'),
                    style: t.amountMd.copyWith(color: pal.textPrimary),
                  ),
                  ChangeChip(p.change['netSalesMinor']),
                ],
              ),
              Text(
                '${p.today.transactions} sale${p.today.transactions == 1 ? '' : 's'} · avg ${p.head.money(p.today.averageBasketMinor)} · ${p.lowStockCount} low on stock · ${p.clockedInNow} clocked in',
                style: t.caption.copyWith(color: pal.textMuted),
              ),
            ],
          ),
        ),
      );
    });
  }
}
