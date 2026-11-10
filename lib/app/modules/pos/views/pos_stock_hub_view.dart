import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos/utils/pos_access.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// The Stock tab (was "Products"): the two existing stock screens plus stock activity, grouped. Counts, transfers and
/// batches need endpoints the POS token cannot call yet — they appear as "Soon" rows for managers / owners only.
class PosStockHubView extends StatelessWidget {
  const PosStockHubView({super.key, this.access});

  /// Test seam; the app resolves it from the signed-in employee.
  final PosAccess? access;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PosAccess>(
      future: access != null ? Future.value(access) : PosAccess.current(),
      builder: (context, snap) {
        final a = snap.data ?? PosAccess.cashier;
        return HubScaffold(
          title: 'Stock',
          listKey: const Key('stockHub'),
          children: [
            HubSection('Catalogue', [
              HubRow(icon: Icons.inventory_2_outlined, title: 'Products', subtitle: 'Search the catalogue and see prices', onTap: () => Get.toNamed(Routes.posProducts)),
            ]),
            HubSection('Stock', [
              HubRow(icon: Icons.fact_check_outlined, title: 'Stock on hand', subtitle: a.canManage ? 'Levels, low stock and adjustments' : 'Levels and low stock', onTap: () => Get.toNamed(Routes.posInventory)),
              // G3.4: a cashier receives stock against approved purchase orders (no costs); managers get the whole supply area
              HubRow(
                icon: Icons.move_to_inbox_outlined,
                title: a.canManage ? 'Suppliers & receiving' : 'Receive stock',
                subtitle: a.canManage ? 'Purchase orders, receiving and payables' : 'Receive goods against an approved purchase order',
                onTap: () => Get.toNamed(a.canManage ? Routes.posSupply : Routes.posSupplyOrders),
              ),
              if (a.canManage) HubRow(icon: Icons.history_rounded, title: 'Stock activity', subtitle: 'Every change to stock, with who and why', onTap: () => Get.toNamed(Routes.posStockActivity), locked: true),
            ]),
            if (a.canManage)
              const HubSection('Coming soon', [
                HubRow(icon: Icons.checklist_rounded, title: 'Stock count', subtitle: 'Count by scan and review variances', soon: true),
                HubRow(icon: Icons.swap_horiz_rounded, title: 'Transfers', subtitle: 'Move stock between locations', soon: true),
                HubRow(icon: Icons.event_busy_outlined, title: 'Batches & expiry', subtitle: 'Track lots and expiry dates', soon: true),
              ]),
          ],
        );
      },
    );
  }
}
