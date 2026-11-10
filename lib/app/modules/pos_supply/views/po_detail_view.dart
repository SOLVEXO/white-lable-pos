import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

class _PoLineRow extends StatelessWidget {
  const _PoLineRow({required this.line, required this.cur});
  final PoLine line;
  final InvCur? cur;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final unit = supplyMoney(line.unitCostMinor, cur);
    final total = supplyMoney(line.lineTotalMinor, cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('poLine_${line.id}'),
        radius: Radii.rMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  if (line.optionsLabel.isNotEmpty || line.sku != null)
                    Text([if (line.sku != null) line.sku!, if (line.optionsLabel.isNotEmpty) line.optionsLabel].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
                  const SizedBox(height: Space.s1),
                  Wrap(
                    key: Key('poLineQty_${line.id}'),
                    spacing: Space.s3,
                    children: [
                      for (final q in ['Ordered ${line.ordered}', 'Received ${line.received}', 'Damaged ${line.damaged}', 'Remaining ${line.remaining}'])
                        Text(q, style: t.bodySmall.copyWith(color: p.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            if (total != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(total, style: t.amountMd.copyWith(color: p.textPrimary)),
                  if (unit != null) Text('$unit each', style: t.caption.copyWith(color: p.textMuted)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// One purchase order with its lines and the actions of its status. A cashier sees the lines (no money) and Receive; managers also approve,
/// send, edit, cancel and close short. The server decides who may; its answer is shown in plain words.
class PoDetailView extends StatelessWidget {
  PoDetailView({super.key, required String orderId, PoDetailController? controller}) : c = controller ?? Get.put(PoDetailController(orderId: orderId), tag: orderId);
  final PoDetailController c;

  Future<void> _confirm(BuildContext context, String title, String body, String action, String yes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          TextButton(key: const Key('poConfirmYes'), onPressed: () => Navigator.of(ctx).pop(true), child: Text(yes)),
        ],
      ),
    );
    if (ok == true) await c.run(action);
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Purchase order',
      maxWidth: 760,
      body: Obx(() {
        if (!supplyOnlineRx().value && c.detail.value == null) return const SupplyNeedsInternet(subject: 'Purchase orders');
        final d = c.detail.value;
        if (c.loading.value && d == null) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (d == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, d));
      }),
    );
  }

  Widget _content(BuildContext context, PoDetail d) {
    final p = context.palette;
    final t = context.type;
    final o = d.order;
    final cur = o.cur ?? d.cur;
    String? m(int? v) => supplyMoney(v, cur);
    Widget total(String label, int? v, {bool big = false}) => m(v) == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: Space.s1),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: t.body.copyWith(color: p.textSecondary)),
                ),
                Text(m(v)!, style: (big ? t.amountLg : t.amountMd).copyWith(color: p.textPrimary)),
              ],
            ),
          );
    return ListView(
      key: const Key('poDetailList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(o.poNumber, style: t.title.copyWith(color: p.textPrimary)),
            ),
            PoStatusBadge(o.status),
          ],
        ),
        Text(o.supplierName, style: t.body.copyWith(color: p.textSecondary)),
        Text([if (o.expectedAt != null) 'Expected ${invDate(o.expectedAt)}', if (o.createdAt != null) 'Created ${invDate(o.createdAt)}'].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
        if (o.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Text(o.notes, style: t.body.copyWith(color: p.textSecondary)),
          ),
        Obx(
          () => c.notice.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    c.notice.value!,
                    key: const Key('poNotice'),
                    style: t.body.copyWith(color: p.successFg),
                  ),
                ),
        ),
        Obx(() => SupplyErrorText(c.actionError.value, errorKey: const Key('poActionError'))),
        const InvSectionTitle('Lines'),
        for (final l in o.items) _PoLineRow(line: l, cur: cur),
        if (o.hasCosts)
          AppCard(
            key: const Key('poTotals'),
            radius: Radii.rMd,
            child: Column(children: [total('Subtotal', o.subtotalMinor), total('Shipping', o.shippingMinor), total('Tax', o.taxMinor), total('Total', o.totalMinor, big: true)]),
          ),
        const SizedBox(height: Space.s4),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            runSpacing: Space.s2,
            children: [
              if (c.canReceive)
                AppButton(
                  key: const Key('poReceive'),
                  label: 'Receive',
                  expand: false,
                  icon: Icons.move_to_inbox_outlined,
                  onPressed: () => Get.toNamed(Routes.posSupplyReceive, arguments: {'orderId': o.id})?.then((_) => c.load(silent: true)),
                ),
              if (c.canApprove) AppButton(key: const Key('poApprove'), label: 'Approve', expand: false, loading: c.busy.value, onPressed: () => c.run('approve')),
              if (c.canSend) AppButton(key: const Key('poSend'), label: 'Send', expand: false, variant: AppButtonVariant.secondary, loading: c.busy.value, onPressed: () => c.run('send')),
              if (c.canEdit)
                AppButton(
                  key: const Key('poEdit'),
                  label: 'Edit',
                  expand: false,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => Get.toNamed(Routes.posSupplyOrderForm, arguments: {'orderId': o.id})?.then((_) => c.load(silent: true)),
                ),
              if (c.canCloseShort)
                AppButton(
                  key: const Key('poCloseShort'),
                  label: 'Close short',
                  expand: false,
                  variant: AppButtonVariant.secondary,
                  onPressed: () => _confirm(context, 'Close short?', 'The remaining units will not be received on this order.', 'close-short', 'Close short'),
                ),
              if (c.canCancel)
                AppButton(
                  key: const Key('poCancel'),
                  label: 'Cancel order',
                  expand: false,
                  variant: AppButtonVariant.danger,
                  onPressed: () => _confirm(context, 'Cancel this order?', 'A cancelled order cannot be received.', 'cancel', 'Cancel order'),
                ),
            ],
          ),
        ),
        if (d.receipts.isNotEmpty) ...[
          const InvSectionTitle('Receipts'),
          for (final r in d.receipts)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('receipt_${r.id}'),
                radius: Radii.rMd,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.receiptNumber, style: t.subtitle.copyWith(color: p.textPrimary)),
                          Text(
                            [
                              invDate(r.createdAt),
                              '${r.lines.fold<int>(0, (s, l) => s + l.qtyGood)} good',
                              '${r.lines.fold<int>(0, (s, l) => s + l.qtyDamaged)} damaged',
                            ].where((e) => e.isNotEmpty).join(' · '),
                            style: t.caption.copyWith(color: p.textMuted),
                          ),
                        ],
                      ),
                    ),
                    if (supplyMoney(r.totalMinor, r.cur ?? cur) != null) Text(supplyMoney(r.totalMinor, r.cur ?? cur)!, style: t.amountMd.copyWith(color: p.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}
