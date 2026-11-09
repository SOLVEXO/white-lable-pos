import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_detail_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_adjust_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One item: stock, committed / damaged, locations, lots with expiry badges, recent movements (managers) and Adjust.
class InvDetailView extends StatelessWidget {
  InvDetailView({super.key, required String variantId, String? role, InvDetailController? controller, DateTime? now})
    : c =
          controller ??
          Get.put(
            InvDetailController(variantId: variantId, role: role),
            tag: variantId,
          ),
      _now = now;
  final InvDetailController c;
  final DateTime? _now;

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Item',
      maxWidth: 760,
      body: Obx(() {
        final d = c.detail.value;
        if (c.loading.value && d == null) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
        if (d == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, d));
      }),
    );
  }

  Future<void> _adjust(InvDetail d) async {
    final ok = await AppBottomSheet.showGet<bool>(
      InvAdjustSheet(variantId: d.row.variantId, currentStock: d.row.stock, productName: d.row.productName),
      title: 'Adjust stock',
    );
    if (ok == true) await c.load();
  }

  Widget _content(BuildContext context, InvDetail d) {
    final p = context.palette;
    final t = context.type;
    final r = d.row;
    final now = _now ?? DateTime.now();
    final showMoves = c.canManage;
    return ListView(
      key: const Key('invDetailList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Text(r.productName, style: t.headline.copyWith(color: p.textPrimary)),
        const SizedBox(height: Space.s1),
        Text(
          [if (r.optionsLabel.isNotEmpty) r.optionsLabel, if (r.sku.isNotEmpty) 'SKU ${r.sku}', if ((r.barcode ?? '').isNotEmpty) r.barcode!].join(' · '),
          style: t.bodySmall.copyWith(color: p.textMuted),
        ),
        const SizedBox(height: Space.s4),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      r.unlimited ? 'Unlimited stock' : '${r.stock} on hand',
                      key: const Key('invDetailStock'),
                      style: t.display.copyWith(color: p.textPrimary),
                    ),
                  ),
                  InvStockBadge(r),
                ],
              ),
              const SizedBox(height: Space.s3),
              _kv(context, 'Committed (held for orders)', '${r.committed}', key: const Key('invDetailCommitted')),
              _kv(context, 'Damaged', '${r.damaged}', key: const Key('invDetailDamaged')),
              if (r.reorderPoint != null) _kv(context, 'Reorder point', '${r.reorderPoint}'),
              if (r.trackLots) _kv(context, 'Expired units', '${r.expiredUnits}', key: const Key('invDetailExpired')),
              if (r.trackLots && r.nextExpiryAt != null) _kv(context, 'Next expiry', invDate(r.nextExpiryAt), key: const Key('invDetailNextExpiry')),
              if (r.costMinor != null && d.cur != null) _kv(context, 'Cost (average)', invMoney(r.costMinor!, d.cur!), key: const Key('invDetailCost')),
              if (r.valueMinor != null && d.cur != null) _kv(context, 'Stock value', invMoney(r.valueMinor!, d.cur!), key: const Key('invDetailValue')),
              const SizedBox(height: Space.s3),
              if (r.unlimited)
                Text('This item has unlimited stock, so there is nothing to adjust.', style: t.bodySmall.copyWith(color: p.textSecondary))
              else
                AppButton(key: const Key('invAdjustButton'), label: 'Adjust stock', icon: Icons.tune_rounded, onPressed: () => _adjust(d)),
            ],
          ),
        ),
        if (d.locations.isNotEmpty) ...[
          const InvSectionTitle('Locations'),
          for (final l in d.locations)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('invLoc_${l.locationId}'),
                radius: Radii.rMd,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(l.name, style: t.body.copyWith(color: p.textPrimary)),
                    ),
                    Text('${l.stock}', style: t.amountMd.copyWith(color: p.textPrimary)),
                  ],
                ),
              ),
            ),
        ],
        if (d.lots.isNotEmpty) ...[const InvSectionTitle('Lots and expiry'), for (final l in d.lots) _LotTile(lot: l, now: now, cur: d.cur)],
        if (showMoves) ...[
          const InvSectionTitle('Recent movements'),
          if (d.recentMovements.isEmpty && d.ledgerStartsAt == null)
            Text(
              'No movements recorded yet',
              key: const Key('invNoMovements'),
              style: t.body.copyWith(color: p.textSecondary),
            ),
          for (final m in d.recentMovements) InvMovementTile(m, cur: d.cur, showProduct: false),
          if (d.ledgerStartsAt != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.s1),
              child: Text(
                'History starts ${invDate(d.ledgerStartsAt)}',
                key: const Key('invLedgerNote'),
                style: t.caption.copyWith(color: p.textMuted),
              ),
            ),
          if (d.recentMovements.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: Space.s2),
              child: AppButton(
                key: const Key('invAllHistory'),
                label: 'All history for this item',
                variant: AppButtonVariant.secondary,
                onPressed: () => Get.toNamed(Routes.posStockMovements, arguments: {'variantId': r.variantId}),
              ),
            ),
        ],
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v, {Key? key}) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: t.body.copyWith(color: p.textSecondary)),
          ),
          Text(v, style: t.subtitle.copyWith(color: p.textPrimary)),
        ],
      ),
    );
  }
}

class _LotTile extends StatelessWidget {
  const _LotTile({required this.lot, required this.now, required this.cur});
  final InvLot lot;
  final DateTime now;
  final InvCur? cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final days = lot.daysLeft(now);
    final badge = days == null
        ? null
        : days < 0
        ? const StatusBadge('Expired', tone: StatusTone.danger)
        : days <= 7
        ? StatusBadge(days == 0 ? 'Expires today' : 'Expires in $days d', tone: StatusTone.warning)
        : days <= 30
        ? StatusBadge('Expires in $days d', tone: StatusTone.info)
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('invLot_${lot.lotId}'),
        radius: Radii.rMd,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Lot ${lot.lotNumber}', style: t.subtitle.copyWith(color: p.textPrimary)),
                  Text(
                    [if (lot.expiryDate != null) 'Expires ${invDate(lot.expiryDate)}' else 'No expiry date', if (lot.costMinor != null && cur != null) 'Cost ${invMoney(lot.costMinor!, cur!)}'].join(' · '),
                    style: t.caption.copyWith(color: p.textMuted),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: badge,
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            Text('${lot.remaining}', style: t.amountMd.copyWith(color: p.textPrimary)),
          ],
        ),
      ),
    );
  }
}
