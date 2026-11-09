import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Customers: search by name, phone or e-mail (debounced), balances and points on every row, add a customer. Opens a profile on tap.
/// Offline it shows the remembered customers ("as of …") and adding one says it needs internet.
class CustomerListView extends StatelessWidget {
  CustomerListView({super.key, CustomerListController? controller}) : c = controller ?? Get.put(CustomerListController());
  final CustomerListController c;

  Future<void> _add() async {
    final saved = await CustomerFormSheet.open();
    if (saved == null) return;
    c.upsert(saved);
    if (saved.existing) {
      CustomAppSnackbar.warning('${saved.name} already has that phone number, so that customer is shown.');
    } else {
      CustomAppSnackbar.success('${saved.name} added.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Customers',
      actions: [
        Obx(
          () => IconButton(
            key: const Key('customersAdd'),
            tooltip: customersOnlineRx().value ? 'Add customer' : 'Add customer (needs internet)',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: customersOnlineRx().value ? _add : null,
          ),
        ),
      ],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
            child: AppSearchBar(hint: 'Search name, phone or e-mail', onChanged: c.onQueryChanged),
          ),
          Obx(() => c.asOf.value == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s2), child: CustomerAsOfBanner(asOf: c.asOf.value!))),
          Expanded(
            child: Obx(() {
              if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('customersLoading')));
              if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.reload);
              if (c.items.isEmpty) {
                return EmptyState(
                  icon: Icons.groups_2_outlined,
                  title: c.query.isEmpty ? 'No customers yet' : 'No customers found',
                  message: c.query.isEmpty ? 'Add a customer to track their credit and points.' : 'Try another name, phone number or e-mail.',
                  actionLabel: customersOnlineRx().value ? 'Add customer' : null,
                  onAction: customersOnlineRx().value ? _add : null,
                );
              }
              final cur = c.cur.value;
              return ListView.builder(
                key: const Key('customerList'),
                padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                itemCount: c.items.length,
                itemBuilder: (_, i) {
                  final PosCustomer customer = c.items[i];
                  return CustomerTile(customer: customer, cur: cur, onTap: () => Get.toNamed(Routes.posCustomerProfile, arguments: {'customerId': customer.id}));
                },
              );
            }),
          ),
        ],
      ),
    );
  }
}
