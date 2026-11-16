import 'package:solvexo_pos/app/data/models/inventory/inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_stock_activity/controllers/pos_stock_activity_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// Store-wide feed of stock adjustments (newest first). Not filterable to a
/// single product — the seller-facing activity-log route has no
/// targetId/targetType filter (only the admin route does), so this is a
/// store-wide history, not a per-product ledger; see
/// InventoryRepository.getStockActivity's doc comment.
class PosStockActivityView extends StatelessWidget {
  PosStockActivityView({super.key});

  final PosStockActivityController c = Get.put(PosStockActivityController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppPage(
      title: 'Stock Activity',
      body: Obx(() {
        if (c.isLoading.value) {
          return const SkeletonList(padding: EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6));
        }
        if (c.entries.isEmpty) {
          return const EmptyState(icon: Icons.history_rounded, title: 'No stock adjustments yet.');
        }
        return RefreshIndicator(
          onRefresh: c.refreshData,
          color: p.accentFg,
          child: ListView.builder(
            controller: c.scrollController,
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
            itemCount: c.entries.length + (c.isLoadingMore.value ? 1 : 0),
            itemBuilder: (_, i) {
              if (i >= c.entries.length) {
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
              return _ActivityTile(entry: c.entries[i]);
            },
          ),
        );
      }),
    );
  }
}

/// One stock change: what happened, then who and when (same card as the inventory movement line).
class _ActivityTile extends StatelessWidget {
  final ActivityLogEntry entry;
  const _ActivityTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(Space.s2),
              decoration: BoxDecoration(color: p.warningSoft, borderRadius: Radii.rSm),
              child: Icon(Icons.inventory_2_outlined, color: p.warningFg, size: IconSizes.sm),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  entry.description.isNotEmpty ? entry.description : entry.action,
                  style: t.subtitle.copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: Space.s1),
                Text(
                  '${entry.actorName.isNotEmpty ? '${entry.actorName} · ' : ''}${DateFormat('MMM d, h:mm a').format(entry.createdAt.toLocal())}',
                  style: t.caption.copyWith(color: p.textMuted),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
