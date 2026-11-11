import 'package:flutter/material.dart';
import 'package:solvexo_pos/app/components/costs_hidden_note.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/views/draft_po_sheet.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_stock_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Stock list (and, with [lowOnly], the Low stock screen): debounced search, All / Low / Out chips, infinite scroll.
class InvStockListView extends StatelessWidget {
  InvStockListView({super.key, InvStockListController? controller, bool lowOnly = false, String initialFilter = 'all', this.role})
    : c = controller ?? Get.put(InvStockListController(lowOnly: lowOnly, initialFilter: initialFilter), tag: lowOnly ? 'low' : initialFilter);
  final InvStockListController c;
  final String? role;

  static const filters = <(String, String)>[('all', 'All'), ('low', 'Low'), ('out', 'Out'), ('expiring', 'Expiring')];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InvScaffold(
      title: c.lowOnly ? 'Low stock' : 'Stock',
      // G4.6: the low items of one supplier → a draft purchase order (managers; the server decides)
      actions: c.lowOnly ? [TextButton.icon(key: const Key('draftPoButton'), onPressed: () => DraftPoSheet.open(), icon: const Icon(Icons.post_add_rounded), label: const Text('Draft PO'))] : null,
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
          // G5.1: one location at a time (only when the store has locations)
          if (!c.lowOnly)
            Obx(
              () => c.locations.isEmpty
                  ? const SizedBox.shrink()
                  : SizedBox(
                      height: 44,
                      child: ListView(
                        key: const Key('invLocations'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
                        children: [
                          Padding(padding: const EdgeInsets.only(right: Space.s2), child: ChoiceChip(key: const Key('invLoc_all'), avatar: const Icon(Icons.store_mall_directory_outlined, size: 16), label: const Text('All locations'), selected: c.locationId.value == null, onSelected: (_) => c.setLocation(null))),
                          for (final l in c.locations)
                            Padding(padding: const EdgeInsets.only(right: Space.s2), child: ChoiceChip(key: Key('invLoc_${l.id}'), label: Text(l.name), selected: c.locationId.value == l.id, onSelected: (_) => c.setLocation(l.id))),
                        ],
                      ),
                    ),
            ),
          // G4.8: the owner hides costs from managers — say so above the list (the rows simply carry no cost)
          Obx(() => c.costsHidden.value ? const Padding(padding: EdgeInsets.symmetric(horizontal: Space.s4), child: CostsHiddenNote(what: 'Costs and stock value')) : const SizedBox.shrink()),
          Expanded(
            child: Obx(() {
              if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
              if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.reload);
              if (c.items.isEmpty) {
                return EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: c.lowOnly ? 'Nothing is low' : (c.filter.value == 'expiring' ? 'Nothing is expiring' : 'No items found'),
                  message: c.lowOnly
                      ? 'Every item is above its reorder point.'
                      : (c.filter.value == 'expiring' ? 'No lot has expired or expires in the next 30 days.' : 'Try another name, SKU or filter.'),
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
                    return InvStockRowTile(row: c.items[i], role: role, cur: c.cur.value);
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
  const InvStockRowTile({super.key, required this.row, this.role, this.cur});
  final InvRow row;
  final String? role;
  /// the page's currency (a row may state its own, e.g. the barcode lookup); null = not stated → no money is shown
  final InvCur? cur;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final money = row.cur ?? cur;
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
                  if (row.trackLots && (row.expiredUnits > 0 || row.nextExpiryAt != null))
                    Text(
                      [if (row.expiredUnits > 0) '${row.expiredUnits} expired', if (row.nextExpiryAt != null) 'next expiry ${invDate(row.nextExpiryAt)}'].join(' · '),
                      key: Key('invRowExpiry_${row.variantId}'),
                      style: t.caption.copyWith(color: row.expiredUnits > 0 ? p.dangerFg : p.warningFg),
                    ),
                  if (money != null && (row.costMinor != null || row.valueMinor != null))
                    Text(
                      [if (row.costMinor != null) 'Cost ${invMoney(row.costMinor!, money)}', if (row.valueMinor != null) 'Value ${invMoney(row.valueMinor!, money)}'].join(' · '),
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
                Text(row.unlimited ? '∞' : '${row.locationStock ?? row.stock}', key: Key('invRowQty_${row.variantId}'), style: t.amountMd.copyWith(color: p.textPrimary)),
                if (row.locationStock != null && !row.unlimited) Text('of ${row.stock} in store', style: t.caption.copyWith(color: p.textMuted)) else InvStockBadge(row),
              ],
            ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
