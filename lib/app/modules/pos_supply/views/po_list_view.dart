import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Purchase orders. A manager sees every order with its total and filters by status; a cashier sees only the orders that can be received, with
/// no money at all (the server sends none). Offline the last remembered list is shown READ ONLY with "Last synced <time>"; with nothing
/// remembered it says "Needs internet".
class PoListView extends StatelessWidget {
  PoListView({super.key, PoListController? controller}) : c = controller ?? Get.put(PoListController());
  final PoListController c;

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Purchase orders',
      actions: [
        Obx(
          () => c.canManage && !c.readOnly
              ? IconButton(
                  key: const Key('poNew'),
                  tooltip: 'New purchase order',
                  icon: const Icon(Icons.add_rounded),
                  onPressed: supplyOnlineRx().value ? () => Get.toNamed(Routes.posSupplyOrderForm)?.then((_) => c.load()) : null,
                )
              : const SizedBox.shrink(),
        ),
      ],
      body: Obx(() {
        if (c.loading.value && c.orders.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (c.needsInternet.value) return const SupplyNeedsInternet(subject: 'Purchase orders');
        if (c.error.value != null && c.orders.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        final list = c.visible;
        return Column(
          children: [
            if (c.readOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
                child: SupplyLastSyncedBanner(asOf: c.asOf.value!),
              ),
            if (c.canManage)
              SizedBox(
                height: 48,
                child: SingleChildScrollView(
                  key: const Key('poFilters'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s1),
                  child: Row(
                    children: [
                      for (final (id, label) in PoStatus.filters)
                        Padding(
                          padding: const EdgeInsets.only(right: Space.s2),
                          child: ChoiceChip(key: Key('poFilter_$id'), label: Text(label), selected: c.status.value == id, onSelected: (_) => c.setStatus(id)),
                        ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(
                      icon: Icons.local_shipping_outlined,
                      title: c.canManage ? 'No purchase orders' : 'Nothing to receive',
                      message: c.canManage ? 'Orders in this status will show here.' : 'Approved purchase orders waiting for stock will show here.',
                    )
                  : RefreshIndicator(
                      onRefresh: c.load,
                      child: ListView.builder(
                        key: const Key('poList'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                        itemCount: list.length,
                        itemBuilder: (_, i) => PoTile(
                          order: list[i],
                          cur: c.cur.value,
                          onTap: c.readOnly ? () => CustomSnack.readOnly() : () => Get.toNamed(Routes.posSupplyOrder, arguments: {'orderId': list[i].id})?.then((_) => c.load()),
                        ),
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

/// Offline rows are not opened (detail needs the server).
abstract final class CustomSnack {
  static void readOnly() => Get.snackbar('Needs internet', 'Connect to open this purchase order.', snackPosition: SnackPosition.BOTTOM);
}
