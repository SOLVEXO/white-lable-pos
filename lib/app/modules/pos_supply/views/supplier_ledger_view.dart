import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_ledger_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/pay_supplier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.cur});
  final LedgerEntry entry;
  final InvCur? cur;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final amount = supplyMoney(entry.amountMinor.abs(), cur);
    final balance = supplyMoney(entry.balanceAfterMinor, cur);
    final owedUp = entry.amountMinor > 0;
    final detail = [
      invDateTime(entry.createdAt),
      if (entry.refNumber != null) entry.refNumber!,
      if (entry.method != null) supplyMethodLabel(entry.method),
      if (entry.reference != null) entry.reference!,
    ].where((e) => e.isNotEmpty).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('ledger_${entry.id}'),
        radius: Radii.rMd,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.typeLabel, style: t.subtitle.copyWith(color: p.textPrimary)),
                  Text(detail, style: t.caption.copyWith(color: p.textMuted)),
                  if (entry.note != null) Text(entry.note!, style: t.bodySmall.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (amount != null) Text('${owedUp ? '+' : '−'}$amount', style: t.amountMd.copyWith(color: owedUp ? p.warningFg : p.successFg)),
                if (balance != null)
                  Text(
                    'Balance $balance',
                    key: Key('ledgerBalance_${entry.id}'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One supplier's ledger with the running balance, and the Pay action (managers / owners). Online only.
class SupplierLedgerView extends StatelessWidget {
  SupplierLedgerView({super.key, required String supplierId, SupplierLedgerController? controller}) : c = controller ?? Get.put(SupplierLedgerController(supplierId: supplierId), tag: supplierId);
  final SupplierLedgerController c;

  Future<void> _pay(SupplierLedger l) async {
    final cur = l.cur;
    if (cur == null) return;
    final ok = await PaySupplierSheet.open(supplierId: l.supplier.id, exponent: cur.exponent, currencyCode: cur.code, balanceMinor: l.aging.balanceMinor);
    if (ok == true) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Supplier ledger',
      body: Obx(() {
        if (!supplyOnlineRx().value && c.ledger.value == null) return const SupplyNeedsInternet(subject: 'The ledger');
        final l = c.ledger.value;
        if (c.loading.value && l == null) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (l == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        final t = context.type;
        final owed = supplyMoney(l.aging.balanceMinor, l.cur);
        return RefreshIndicator(
          onRefresh: c.load,
          child: ListView(
            key: const Key('ledgerList'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
            children: [
              Text(l.supplier.name, style: t.title.copyWith(color: context.palette.textPrimary)),
              const SizedBox(height: Space.s2),
              AppCard(
                radius: Radii.rMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You owe', style: t.caption.copyWith(color: context.palette.textSecondary)),
                    if (owed != null) AmountText(owed, key: const Key('ledgerOwed'), style: t.amountLg, animate: false),
                    const SizedBox(height: Space.s3),
                    AgingBuckets(aging: l.aging, cur: l.cur),
                  ],
                ),
              ),
              const SizedBox(height: Space.s3),
              AppButton(key: const Key('ledgerPay'), label: 'Pay supplier', onPressed: l.cur == null ? null : () => _pay(l)),
              const InvSectionTitle('History'),
              if (l.entries.isEmpty)
                const EmptyState(icon: Icons.receipt_long_outlined, title: 'No entries yet', message: 'Goods received, payments and returns will appear here.')
              else
                for (final e in l.entries) _LedgerTile(entry: e, cur: l.cur),
            ],
          ),
        );
      }),
    );
  }
}
