import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_overview_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Inventory home: the numbers that matter, the open count and the ways into the stock list, history, counts and limits.
/// A cashier sees quantities only (no value, no history, no limits); the server leaves those out of the answer anyway.
class InvOverviewView extends StatelessWidget {
  InvOverviewView({super.key, InvOverviewController? controller}) : c = controller ?? Get.put(InvOverviewController());
  final InvOverviewController c;

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Inventory',
      body: Obx(() {
        final o = c.overview.value;
        if (c.loading.value && o == null) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
        if (o == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, o));
      }),
    );
  }

  Widget _content(BuildContext context, InvOverview o) {
    final p = context.palette;
    final t = context.type;
    return ListView(
      key: const Key('invOverviewList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        if (o.hasOpenCount)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s3),
            child: AppCard(
              key: const Key('invOpenCountBanner'),
              color: p.accentSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.fact_check_outlined, color: p.accentFg),
                      const SizedBox(width: Space.s2),
                      Expanded(
                        child: Text('A stock count is open', style: t.subtitle.copyWith(color: p.textPrimary)),
                      ),
                    ],
                  ),
                  if (o.openCountStartedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: Text('Started ${invDateTime(o.openCountStartedAt)}', style: t.bodySmall.copyWith(color: p.textSecondary)),
                    ),
                  const SizedBox(height: Space.s3),
                  AppButton(key: const Key('invContinueCount'), label: 'Continue count', icon: Icons.play_arrow_rounded, onPressed: () => Get.toNamed(Routes.posStockCount)),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, box) {
            const gap = Space.s3;
            final cols = box.maxWidth >= 560 ? 3 : 2;
            final w = (box.maxWidth - gap * (cols - 1)) / cols;
            Widget tile(Key k, String label, String value, {StatusTone? tone, IconData? icon}) => SizedBox(
              width: w,
              child: _Tile(key: k, label: label, value: value, tone: tone, icon: icon),
            );
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                tile(const Key('invTileSkus'), 'Items (SKUs)', '${o.skuCount}', icon: Icons.inventory_2_outlined),
                tile(const Key('invTileLow'), 'Low stock', '${o.lowStockCount}', tone: o.lowStockCount > 0 ? StatusTone.warning : null, icon: Icons.trending_down_rounded),
                tile(const Key('invTileOut'), 'Out of stock', '${o.outOfStockCount}', tone: o.outOfStockCount > 0 ? StatusTone.danger : null, icon: Icons.remove_shopping_cart_outlined),
                tile(const Key('invTileExpired'), 'Expired lots', '${o.expiredLots}', tone: o.expiredLots > 0 ? StatusTone.danger : null, icon: Icons.event_busy_outlined),
                tile(const Key('invTileExp7'), 'Expiring in 7 days', '${o.expiringIn7Days}', tone: o.expiringIn7Days > 0 ? StatusTone.warning : null, icon: Icons.hourglass_bottom_rounded),
                tile(const Key('invTileExp30'), 'Expiring in 30 days', '${o.expiringIn30Days}', icon: Icons.event_outlined),
                if (o.stockValueMinor != null && o.cur != null) tile(const Key('invTileValue'), 'Stock value', invMoney(o.stockValueMinor!, o.cur!), icon: Icons.account_balance_wallet_outlined),
              ],
            );
          },
        ),
        if (o.canManage && (o.variantsWithoutCost ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Text(
              '${o.variantsWithoutCost} item${o.variantsWithoutCost == 1 ? ' has' : 's have'} no cost recorded, so the value is understated.',
              key: const Key('invNoCostNote'),
              style: t.caption.copyWith(color: p.textMuted),
            ),
          ),
        const SizedBox(height: Space.s5),
        HubRow(key: const Key('invRowStock'), icon: Icons.list_alt_rounded, title: 'Stock list', subtitle: 'Search every item and open its detail', onTap: () => Get.toNamed(Routes.posStockList)),
        const SizedBox(height: Space.s2),
        HubRow(
          key: const Key('invRowLow'),
          icon: Icons.trending_down_rounded,
          title: 'Low stock',
          subtitle: 'Items at or below their reorder point',
          badge: o.lowStockCount,
          onTap: () => Get.toNamed(Routes.posStockList, arguments: const {'lowOnly': true}),
        ),
        if (o.canManage) ...[
          const SizedBox(height: Space.s2),
          HubRow(
            key: const Key('invRowMovements'),
            icon: Icons.swap_vert_rounded,
            title: 'Movement history',
            subtitle: 'Sales, returns, adjustments and counts',
            onTap: () => Get.toNamed(Routes.posStockMovements),
          ),
        ],
        if (o.canManage || o.hasOpenCount) ...[
          const SizedBox(height: Space.s2),
          HubRow(
            key: const Key('invRowCount'),
            icon: Icons.fact_check_outlined,
            title: o.canManage ? 'Stock count' : 'Continue stock count',
            subtitle: o.hasOpenCount ? 'A count is open: scan and count items' : 'Start a count by scanning',
            onTap: () => Get.toNamed(Routes.posStockCount),
          ),
        ],
        if (o.canManage) ...[
          const SizedBox(height: Space.s2),
          HubRow(
            key: const Key('invRowLimits'),
            icon: Icons.rule_rounded,
            title: 'Approval limits',
            subtitle: 'What a cashier may change without a manager',
            onTap: () => Get.toNamed(Routes.posStockLimits),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({super.key, required this.label, required this.value, this.tone, this.icon});
  final String label, value;
  final StatusTone? tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final color = switch (tone) {
      StatusTone.danger => p.dangerFg,
      StatusTone.warning => p.warningFg,
      _ => p.textPrimary,
    };
    return AppCard(
      semanticLabel: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: p.textMuted), const SizedBox(width: Space.s1)],
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.amountLg.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
