import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/pos_inventory_controller.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosInventoryView extends StatelessWidget {
  PosInventoryView({super.key});

  final PosInventoryController c = Get.put(PosInventoryController());

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Inventory',
      actions: [
        IconButton(
          tooltip: 'Stock activity',
          onPressed: () => Get.toNamed(Routes.posStockActivity),
          icon: const Icon(Icons.history_rounded),
        ),
      ],
      body: Column(children: [
        Obx(() => _StatsHeader(stats: c.stats.value)),
        _LowStockToggle(c: c),
        Expanded(
          child: Obx(() {
            if (c.isLoading.value) {
              return const SkeletonList(padding: EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6));
            }
            if (c.showLowStockOnly.value) {
              return _LowStockList(c: c);
            }
            return _InventoryList(c: c);
          }),
        ),
      ]),
    );
  }
}

class _StatsHeader extends StatelessWidget {
  final InventoryStats? stats;
  const _StatsHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats == null) return const SizedBox.shrink();
    final p = context.palette;
    final chips = [
      _StatChip(label: 'Products', value: '${stats!.totalProducts}', color: p.textPrimary),
      _StatChip(label: 'In Stock', value: '${stats!.inStock}', color: p.successFg),
      _StatChip(label: 'Low Stock', value: '${stats!.lowStock}', color: p.warningFg),
      _StatChip(label: 'Out', value: '${stats!.outOfStock}', color: p.dangerFg),
    ];
    // Large text: two rows of two instead of four side by side.
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: Space.s3),
        child: stack
            ? Column(children: [
                Row(children: [Expanded(child: chips[0]), Expanded(child: chips[1])]),
                const SizedBox(height: Space.s3),
                Row(children: [Expanded(child: chips[2]), Expanded(child: chips[3])]),
              ])
            : Row(children: [for (final chip in chips) Expanded(child: chip)]),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(value, maxLines: 1, style: t.amountMd.copyWith(color: color)),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: t.caption.copyWith(color: context.palette.textMuted),
        ),
      ]),
    );
  }
}

class _LowStockToggle extends StatelessWidget {
  final PosInventoryController c;
  const _LowStockToggle({required this.c});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Obx(() => AppPill(
              label: 'Low Stock Only',
              icon: Icons.warning_amber_rounded,
              selected: c.showLowStockOnly.value,
              onTap: c.toggleLowStockOnly,
            )),
      ),
    );
  }
}

class _InventoryList extends StatelessWidget {
  final PosInventoryController c;
  const _InventoryList({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (c.products.isEmpty) {
        return const EmptyState(icon: Icons.inventory_2_outlined, title: 'No products found.');
      }
      return RefreshIndicator(
        onRefresh: c.refreshData,
        color: p.accentFg,
        child: ListView.builder(
          controller: c.scrollController,
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
          itemCount: c.products.length + (c.isLoadingMore.value ? 1 : 0),
          itemBuilder: (_, i) {
            if (i >= c.products.length) {
              return Padding(
                padding: const EdgeInsets.all(Space.s4),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: p.accentFg),
                  ),
                ),
              );
            }
            return _InventoryTile(product: c.products[i], c: c);
          },
        ),
      );
    });
  }
}

class _InventoryTile extends StatelessWidget {
  final InventoryProductSummary product;
  final PosInventoryController c;
  const _InventoryTile({required this.product, required this.c});

  StatusTone get _statusTone {
    switch (product.stockStatus) {
      case 'out_of_stock':
        return StatusTone.danger;
      case 'low_stock':
        return StatusTone.warning;
      default:
        return StatusTone.success;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // an offline oversell can leave stock at or below zero — that is simply out of stock
    final out = !product.isUnlimited && (product.stock <= 0 || product.stockStatus == 'out_of_stock');
    return _StockRow(
      onTap: () => c.openAdjustStock(product.productId, product.name),
      title: product.name,
      subtitle: product.hasSingleVariant ? product.sku : '${product.sku} · ${product.variantCount} variants',
      badge: StatusBadge(
        product.isUnlimited ? 'Unlimited' : (out ? 'Out of stock' : '${product.stock} in stock'),
        tone: product.isUnlimited ? StatusTone.info : (out ? StatusTone.danger : _statusTone),
      ),
      trailing: Icon(Icons.chevron_right_rounded, color: p.textMuted),
    );
  }
}

/// One product line of this screen: name (and SKU), a stock pill, and a tap that opens the stock adjustment.
class _StockRow extends StatelessWidget {
  const _StockRow({required this.onTap, required this.title, required this.badge, this.subtitle, this.trailing});
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final Widget badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final stack = MediaQuery.textScalerOf(context).scale(16) > 19;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.subtitle.copyWith(color: p.textPrimary)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption.copyWith(color: p.textMuted)),
              if (stack) Padding(padding: const EdgeInsets.only(top: Space.s1), child: badge),
            ]),
          ),
          if (!stack) ...[const SizedBox(width: Space.s3), badge],
          if (trailing != null) ...[const SizedBox(width: Space.s1), trailing!],
        ]),
      ),
    );
  }
}

class _LowStockList extends StatelessWidget {
  final PosInventoryController c;
  const _LowStockList({required this.c});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Obx(() {
      if (c.lowStockItems.isEmpty) {
        return const EmptyState(icon: Icons.check_circle_outline_rounded, title: 'Nothing is low on stock.');
      }
      return RefreshIndicator(
        onRefresh: c.refreshData,
        color: p.accentFg,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
          itemCount: c.lowStockItems.length,
          itemBuilder: (_, i) {
            final item = c.lowStockItems[i];
            return _StockRow(
              onTap: () => c.openAdjustStock(item.productId, item.name),
              title: item.name,
              badge: StatusBadge('${item.stock} left', tone: StatusTone.warning),
                    );
          },
        ),
      );
    });
  }
}
