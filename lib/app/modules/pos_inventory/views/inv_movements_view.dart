import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_movements_controller.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Movement history (managers / owners): type chips and an infinite list. A cashier is told the history is for managers.
class InvMovementsView extends StatelessWidget {
  InvMovementsView({super.key, InvMovementsController? controller})
    : c =
          controller ??
          (Get.isRegistered<InvMovementsController>()
              ? Get.find<InvMovementsController>()
              : Get.put(InvMovementsController(variantId: Get.arguments is Map ? Get.arguments['variantId'] as String? : null)));
  final InvMovementsController c;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InvScaffold(
      title: 'Movement history',
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: Obx(
              () => ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s2),
                children: [
                  for (final (id, label) in InvMovementsController.types)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s2),
                      child: ChoiceChip(key: Key('invType_${id ?? 'all'}'), label: Text(label), selected: c.type.value == id, onSelected: (_) => c.setType(id)),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Obx(() {
              if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('invLoading')));
              if (c.forbidden.value) return const EmptyState(icon: Icons.lock_outline_rounded, title: 'Managers only', message: 'The movement history is only available to managers and owners.');
              if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.reload);
              if (c.items.isEmpty) return const EmptyState(icon: Icons.swap_vert_rounded, title: 'No movements', message: 'Nothing has moved for this filter yet.');
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 400) c.loadMore();
                  return false;
                },
                child: ListView.builder(
                  key: const Key('invMovementList'),
                  padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                  itemCount: c.items.length + (c.hasMore.value ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= c.items.length) {
                      return Padding(
                        padding: const EdgeInsets.all(Space.s4),
                        child: Center(
                          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: p.accentFg)),
                        ),
                      );
                    }
                    return InvMovementTile(c.items[i]);
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
