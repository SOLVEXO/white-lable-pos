import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/money.dart';

/// Stock list (and, with [lowOnly], the Low stock screen): debounced search, All / Low / Out chips, infinite scroll.
class InvStockListView extends StatelessWidget {
  InvStockListView({super.key, InvStockListController? controller, bool lowOnly = false, this.role})
    : c = controller ?? Get.put(InvStockListController(lowOnly: lowOnly), tag: lowOnly ? 'low' : 'all');
  final InvStockListController c;
  final String? role;

  static const filters = <(String, String)>[('all', 'All'), ('low', 'Low'), ('out', 'Out')];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InvScaffold(
      title: c.lowOnly ? 'Low stock' : 'Stock',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
            child: AppSearchBar(hint: 'Search name, SKU or barcode', onChanged: c.onQueryChanged),
          ),
          if (!c.lowOnly)
            SizedBox(
              height: 44,
              child: Obx(
                () => ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                  children: [
                    for (final (id, label) in filters)
                      Padding(
                        padding: const EdgeInsets.only(right: Space.s2),
                        child: ChoiceChip(key: Key('invFilter_$id'), label: Text(label), selected: c.filter.value == id, onSelected: (_) => c.setFilter(id)),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Obx(() {
              if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
              if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.reload);
              if (c.items.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: c.lowOnly ? 'Nothing is low' : 'No items found',
                  message: c.lowOnly ? 'Every item is above its reorder point.' : 'Try another name, SKU or filter.',
                );
              }
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 400) c.loadMore();
                  return false;
                },
                child: ListView.builder(
                  key: const Key('invStockList'),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  itemCount: c.items.length + (c.hasMore.value ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= c.items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(Space.s4),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(key: const Key('invLoadingMore'), strokeWidth: 2, color: p.accentFg),
                          ),
                        ),
                      );
                    }
                    return InvStockRowTile(row: c.items[i], role: role);
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class InvStockRowTile extends StatelessWidget {
  const InvStockRowTile({super.key, required this.row, this.role, this.exponent});
  final InvRow row;
  final String? role;
  final int? exponent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final exp = exponent ?? Money.exponent;
    final sub = [if (row.optionsLabel.isNotEmpty) row.optionsLabel, if (row.sku.isNotEmpty) row.sku].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('invRow_${row.variantId}'),
        radius: Radii.rMd,
        onTap: () => Get.toNamed(Routes.posStockDetail, arguments: {'variantId': row.variantId, if (role != null) 'role': role}),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textMuted),
                    ),
                  if (row.costMinor != null || row.valueMinor != null)
                    Text(
                      [if (row.costMinor != null) 'Cost ${invMoney(row.costMinor!, exp)}', if (row.valueMinor != null) 'Value ${invMoney(row.valueMinor!, exp)}'].join(' · '),
                      key: Key('invRowCost_${row.variantId}'),
                      style: t.caption.copyWith(color: p.textSecondary),
                    ),
                ],
              ),
            ),
            const SizedBox(width: Space.s3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(row.unlimited ? '∞' : '${row.stock}', style: t.amountMd.copyWith(color: p.textPrimary)),
                InvStockBadge(row),
              ],
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
