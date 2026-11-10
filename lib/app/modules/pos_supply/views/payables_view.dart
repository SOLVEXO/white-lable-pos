import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/payables_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _PayableTile extends StatelessWidget {
  const _PayableTile({required this.row, required this.cur});
  final PayableRow row;
  final InvCur? cur;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final owed = supplyMoney(row.aging.balanceMinor, cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('payable_${row.supplierId}'),
        radius: Radii.rMd,
        onTap: () => Get.toNamed(Routes.posSupplyLedger, arguments: {'supplierId': row.supplierId}),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                ),
                if (owed != null) AmountText(owed, style: t.amountMd, animate: false),
                Icon(Icons.chevron_right_rounded, color: p.textMuted),
              ],
            ),
            const SizedBox(height: Space.s2),
            AgingBuckets(aging: row.aging, cur: cur),
          ],
        ),
      ),
    );
  }
}

/// What the store owes its suppliers: the total with its aging, then each supplier's balance (managers / owners). Online only.
class PayablesView extends StatelessWidget {
  PayablesView({super.key, PayablesController? controller}) : c = controller ?? Get.put(PayablesController());
  final PayablesController c;

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Payables',
      body: Obx(() {
        if (!supplyOnlineRx().value && c.payables.value == null) return const SupplyNeedsInternet(subject: 'Payables');
        final data = c.payables.value;
        if (c.loading.value && data == null) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (data == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        final total = supplyMoney(data.totals.balanceMinor, data.cur);
        final t = context.type;
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            key: const Key('payablesList'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              AppCard(
                key: const Key('payablesTotals'),
                radius: Radii.rMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total owed', style: t.caption.copyWith(color: context.palette.textSecondary)),
                    if (total != null) AmountText(total, key: const Key('payablesTotal'), style: t.amountLg, animate: false),
                    const SizedBox(height: Space.s3),
                    AgingBuckets(aging: data.totals, cur: data.cur),
                  ],
                ),
              ),
              const InvSectionTitle('By supplier'),
              if (data.suppliers.isEmpty)
                const EmptyState(icon: Icons.verified_outlined, title: 'Nothing owed', message: 'You do not owe any supplier right now.')
              else
                for (final r in data.suppliers) _PayableTile(row: r, cur: data.cur),
            ],
          ),
        );
      }),
    );
  }
}
