import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Money text for [minor] in the response's own currency, or null when the server did not state the amount or the currency (nothing is rendered then).
String? supplyMoney(int? minor, InvCur? cur) => (minor == null || cur == null) ? null : invMoney(minor, cur);

/// "Needs internet": supply works online only (the last-synced order list is the one read-only exception).
class SupplyNeedsInternet extends StatelessWidget {
  const SupplyNeedsInternet({super.key, this.subject = 'This screen'});
  final String subject;
  @override
  Widget build(BuildContext context) => EmptyState(
    key: const Key('supplyNeedsInternet'),
    icon: Icons.wifi_off_rounded,
    title: 'Needs internet',
    message: '$subject needs an internet connection. Connect the till and it will load by itself.',
    tone: context.palette.warningFg,
  );
}

/// "Last synced 9 Nov, 14:32 — read only" above the remembered order list.
class SupplyLastSyncedBanner extends StatelessWidget {
  const SupplyLastSyncedBanner({super.key, required this.asOf});
  final DateTime asOf;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('supplyLastSynced'),
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s2),
      decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rMd),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: p.warningFg),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text('Last synced ${invDateTime(asOf)} — read only', style: context.type.caption.copyWith(color: p.warningFg)),
          ),
        ],
      ),
    );
  }
}

StatusTone poStatusTone(String s) => switch (s) {
  PoStatus.draft => StatusTone.neutral,
  PoStatus.approved => StatusTone.accent,
  PoStatus.sent => StatusTone.info,
  PoStatus.partiallyReceived => StatusTone.warning,
  PoStatus.received => StatusTone.success,
  PoStatus.cancelled => StatusTone.danger,
  _ => StatusTone.neutral,
};

class PoStatusBadge extends StatelessWidget {
  const PoStatusBadge(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => StatusBadge(PoStatus.label(status), tone: poStatusTone(status));
}

/// One purchase order row. Money only when the server stated it (a cashier's orders carry none).
class PoTile extends StatelessWidget {
  const PoTile({super.key, required this.order, required this.cur, required this.onTap});
  final PurchaseOrder order;
  final InvCur? cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final money = supplyMoney(order.totalMinor, order.cur ?? cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('po_${order.id}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: Space.s2,
                    runSpacing: Space.s1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        order.poNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.subtitle.copyWith(color: p.textPrimary),
                      ),
                      PoStatusBadge(order.status),
                    ],
                  ),
                  Text(
                    order.supplierName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(color: p.textSecondary),
                  ),
                  if (money != null)
                    Text(
                      money,
                      key: Key('poTotal_${order.id}'),
                      style: t.amountMd.copyWith(color: p.textPrimary),
                    ),
                  Text(
                    [
                      if (order.expectedAt != null) 'Expected ${invDate(order.expectedAt)}',
                      '${order.items.length} line${order.items.length == 1 ? '' : 's'}',
                      if (order.receivable) '${order.remainingUnits} to receive',
                    ].join(' · '),
                    style: t.caption.copyWith(color: p.textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Current / 30 / 60 / 90+ buckets of what is owed.
class AgingBuckets extends StatelessWidget {
  const AgingBuckets({super.key, required this.aging, required this.cur});
  final Aging aging;
  final InvCur? cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget cell(Key k, String label, int minor) {
      final money = supplyMoney(minor, cur);
      return Expanded(
        child: Column(
          key: k,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.caption.copyWith(color: p.textSecondary)),
            if (money != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(money, style: t.amountMd.copyWith(color: minor > 0 && label != 'Current' ? p.warningFg : p.textPrimary)),
              ),
          ],
        ),
      );
    }

    return Row(
      children: [
        cell(const Key('agingCurrent'), 'Current', aging.currentMinor),
        cell(const Key('aging30'), '30 days', aging.d30Minor),
        cell(const Key('aging60'), '60 days', aging.d60Minor),
        cell(const Key('aging90'), '90+ days', aging.d90Minor),
      ],
    );
  }
}

/// The error line under a sheet or form.
class SupplyErrorText extends StatelessWidget {
  const SupplyErrorText(this.message, {super.key, this.errorKey});
  final String? message;
  final Key? errorKey;
  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: Space.s3),
          child: Text(
            message!,
            key: errorKey,
            style: context.type.body.copyWith(color: context.palette.dangerFg),
          ),
        );
}

Future<DateTime?> pickSupplyDate(BuildContext context, {DateTime? initial, DateTime? first, DateTime? last}) {
  final now = DateTime.now();
  return showDatePicker(context: context, initialDate: initial ?? now, firstDate: first ?? DateTime(now.year - 2), lastDate: last ?? DateTime(now.year + 10));
}

/// A tappable field showing a date ("Pick a date" when none) with a clear button.
class SupplyDateField extends StatelessWidget {
  const SupplyDateField({super.key, required this.label, required this.value, required this.onPick, this.onClear});
  final String label;
  final DateTime? value;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return AppCard(
      radius: Radii.rMd,
      onTap: onPick,
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: Space.s3),
      child: Row(
        children: [
          Icon(Icons.event_rounded, size: 20, color: p.textMuted),
          const SizedBox(width: Space.s2),
          Expanded(
            child: Text(value == null ? label : '$label: ${invDate(value)}', style: t.body.copyWith(color: value == null ? p.textMuted : p.textPrimary)),
          ),
          if (value != null && onClear != null) IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_rounded, size: 18), onPressed: onClear),
        ],
      ),
    );
  }
}
