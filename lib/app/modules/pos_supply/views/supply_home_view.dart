import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos/views/pos_hub_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Supply home for managers / owners: suppliers, purchase orders, receiving without a purchase order, payables. (A cashier is sent straight
/// to the receivable orders; the server decides what each screen will let them do.)
class SupplyHomeView extends StatelessWidget {
  const SupplyHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Suppliers & orders',
      body: ListView(
        key: const Key('supplyHome'),
        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: HubRow(icon: Icons.local_shipping_outlined, title: 'Purchase orders', subtitle: 'Create, approve, send and receive orders', onTap: () => Get.toNamed(Routes.posSupplyOrders)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: HubRow(icon: Icons.move_to_inbox_outlined, title: 'Receive stock', subtitle: 'Receive goods without a purchase order', onTap: () => Get.toNamed(Routes.posSupplyReceive)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: HubRow(icon: Icons.storefront_outlined, title: 'Suppliers', subtitle: 'Contacts, tax details and balances', onTap: () => Get.toNamed(Routes.posSupplySuppliers)),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: HubRow(icon: Icons.payments_outlined, title: 'Payables', subtitle: 'What you owe, by supplier and age', onTap: () => Get.toNamed(Routes.posSupplyPayables)),
          ),
        ],
      ),
    );
  }
}
