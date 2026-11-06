import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_sale_model.dart';
import 'package:solvexo_pos/app/modules/pos_returns/controllers/pos_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_returns/views/pos_return_complete_view.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Return items: pick the lines and quantities, say whether they go back on the shelf, whether the customer has the original receipt,
/// see what it credits and how it is paid back, then confirm. Refund method = the sale's own tenders (no store credit).
class PosReturnView extends StatelessWidget {
  PosReturnView({super.key, PosReturnController? controller}) : c = controller ?? Get.put(PosReturnController());
  final PosReturnController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Return items'), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Obx(() {
              if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('returnLoading')));
              final s = c.sale.value;
              if (s == null) return Center(child: Text(c.error.value ?? 'Not found', key: const Key('returnError')));
              if (!s.canRefund) return Center(child: Padding(padding: const EdgeInsets.all(Space.s5), child: Text('This sale cannot be returned (${s.status}).', key: const Key('returnNotAllowed'), textAlign: TextAlign.center, style: t.body.copyWith(color: p.textSecondary))));
              final est = c.estimateMinor;
              final plan = c.plan();
              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s4),
                      children: [
                        Text('${s.invoice?.number ?? s.saleNumber}  ·  ${Money.format(s.total, currency: s.currency, exponent: s.currencyExponent)}', key: const Key('returnHeader'), style: t.subtitle.copyWith(color: p.textSecondary)),
                        const SizedBox(height: Space.s3),
                        for (final i in s.items) _Line(c: c, item: i),
                        const SizedBox(height: Space.s2),
                        AppCard(
                          radius: Radii.rMd,
                          child: Row(
                            children: [
                              Expanded(child: Text('The customer has the original receipt', style: t.body.copyWith(color: p.textPrimary))),
                              Switch(key: const Key('receiptSwitch'), value: c.receiptPresented.value, onChanged: (v) => c.receiptPresented.value = v),
                            ],
                          ),
                        ),
                        if (!c.receiptPresented.value) Padding(padding: const EdgeInsets.only(top: Space.s1), child: Text('Without the receipt a manager must approve the return.', key: const Key('noReceiptNote'), style: t.caption.copyWith(color: p.warningFg))),
                        const SizedBox(height: Space.s3),
                        if (est != null)
                          AppCard(
                            key: const Key('returnSummary'),
                            radius: Radii.rMd,
                            color: p.fill,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [Expanded(child: Text('Credit', style: t.subtitle.copyWith(color: p.textPrimary))), AmountText(c.money(est), key: const Key('returnEstimate'), style: t.amountLg)]),
                                const SizedBox(height: Space.s2),
                                Text('Paid back to', style: t.caption.copyWith(color: p.textMuted)),
                                for (final line in plan) Text(line, key: const Key('returnPlanLine'), style: t.body.copyWith(color: p.textSecondary)),
                              ],
                            ),
                          ),
                        if (c.error.value != null) Padding(padding: const EdgeInsets.only(top: Space.s3), child: Text(c.error.value!, key: const Key('returnProblem'), style: t.body.copyWith(color: p.danger))),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s4),
                    child: Row(
                      children: [
                        Expanded(child: AppButton(key: const Key('returnAll'), label: 'Return everything', variant: AppButtonVariant.secondary, onPressed: c.processing.value ? null : () => _go(context, all: true))),
                        const SizedBox(width: Space.s3),
                        Expanded(flex: 2, child: AppButton(key: const Key('returnSelected'), label: 'Return selected', icon: Icons.assignment_return_outlined, loading: c.processing.value, onPressed: (!c.hasSelection || c.processing.value) ? null : () => _go(context))),
                      ],
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Future<void> _go(BuildContext context, {bool all = false}) async {
    if (await c.confirm(all: all)) Get.off<void>(() => PosReturnCompleteView(c: c));
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.c, required this.item});
  final PosReturnController c;
  final PosSaleItemModel item;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final id = item.saleItemId ?? '';
    final left = item.refundableQty;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('returnLine_$id'),
        radius: Radii.rMd,
        child: Obx(() {
          final q = c.qty[id] ?? 0;
          final restock = c.restocks(id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: t.subtitle.copyWith(color: left == 0 ? p.textMuted : p.textPrimary)),
                      Text('Sold ${item.qty}${item.refundedQty > 0 ? ' · returned ${item.refundedQty}' : ''}${item.isCustom ? ' · custom item' : ''}', style: t.caption.copyWith(color: p.textMuted)),
                    ]),
                  ),
                  if (left == 0) const StatusBadge('Returned', tone: StatusTone.neutral) else QuantityStepper(key: Key('returnStepper_$id'), value: q, min: 0, compact: true, onChanged: (v) => c.setQty(id, v)),
                ],
              ),
              if (q > 0 && !item.isCustom) ...[
                const SizedBox(height: Space.s2),
                Row(
                  children: [
                    Expanded(child: Text(restock ? 'Back on the shelf' : 'Not going back on the shelf', style: t.caption.copyWith(color: restock ? p.textSecondary : p.warningFg))),
                    Switch(key: Key('restock_$id'), value: restock, onChanged: (v) => c.setRestock(id, v)),
                  ],
                ),
                if (!restock) AppTextField(key: Key('restockReason_$id'), label: 'Why? (damaged, opened…)', onChanged: (v) => c.restockReason[id] = v),
              ],
            ],
          );
        }),
      ),
    );
  }
}
