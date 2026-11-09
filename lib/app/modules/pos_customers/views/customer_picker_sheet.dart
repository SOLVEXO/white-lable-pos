import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The customer chosen for a sale, with the currency their balances are stated in.
class CustomerPick {
  const CustomerPick(this.customer, this.cur);
  final PosCustomer customer;
  final InvCur? cur;
}

/// Attach a customer to the sale: debounced search by name, phone or e-mail, credit and points on every row, "Add customer" without
/// leaving the sale (the new one is chosen at once), and Walk-in. Offline it lists what the till remembers and adding says "Needs internet".
class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key, this.controller});

  /// Tests pass their own (already initialised) controller; the sheet otherwise owns a fresh one for as long as it is open.
  final CustomerListController? controller;

  /// `null` = Walk-in / closed without choosing.
  static Future<CustomerPick?> open() => Get.bottomSheet<CustomerPick>(const CustomerPickerSheet(), isScrollControlled: true, backgroundColor: Colors.transparent);

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  late final CustomerListController c = widget.controller ?? (CustomerListController()..onInit());

  @override
  void dispose() {
    if (widget.controller == null) c.onClose();
    super.dispose();
  }

  Future<void> _add() async {
    final saved = await CustomerFormSheet.open();
    if (saved != null) Get.back<CustomerPick>(result: CustomerPick(saved, c.cur.value));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Opened with Get.bottomSheet (transparent route background), so the sheet draws its own surface.
    return AppSheetSurface(
      scrollable: false,
      padding: const EdgeInsets.fromLTRB(Space.s5, 0, Space.s5, Space.s4),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Select customer', style: context.type.title.copyWith(color: p.textPrimary)),
                  ),
                ),
                TextButton(
                  key: const Key('walkInButton'),
                  onPressed: () => Get.back(),
                  style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: p.accentFg),
                  child: Text('Walk-in', style: context.type.label.copyWith(color: p.accentFg)),
                ),
              ],
            ),
            const SizedBox(height: Space.s2),
            AppSearchBar(hint: 'Search name, phone or e-mail', onChanged: c.onQueryChanged),
            const SizedBox(height: Space.s2),
            Obx(
              () => c.asOf.value == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: Space.s2),
                      child: CustomerAsOfBanner(asOf: c.asOf.value!),
                    ),
            ),
            Obx(
              () => AppButton(
                key: const Key('pickerAdd'),
                label: 'Add customer',
                icon: Icons.person_add_alt_1_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: customersOnlineRx().value ? _add : null,
              ),
            ),
            Obx(
              () => customersOnlineRx().value
                  ? const SizedBox.shrink()
                  : const Padding(
                      padding: EdgeInsets.only(top: Space.s1),
                      child: CustomerNote(noteKey: Key('pickerOffline'), icon: Icons.cloud_off_rounded, text: 'Needs internet to add a customer.'),
                    ),
            ),
            const SizedBox(height: Space.s2),
            Expanded(
              child: Obx(() {
                if (c.loading.value && c.items.isEmpty) return const SkeletonList(itemCount: 5, padding: EdgeInsets.zero);
                if (c.error.value != null && c.items.isEmpty) {
                  return EmptyState(icon: Icons.cloud_off_rounded, title: 'Could not load', message: c.error.value, actionLabel: 'Try again', onAction: c.reload, tone: p.danger);
                }
                if (c.items.isEmpty) return const EmptyState(icon: Icons.people_outline_rounded, title: 'No customers found.');
                final cur = c.cur.value;
                return ListView.builder(
                  key: const Key('pickerList'),
                  itemCount: c.items.length,
                  itemBuilder: (_, i) {
                    final customer = c.items[i];
                    return CustomerTile(
                      customer: customer,
                      cur: cur,
                      onTap: () => Get.back<CustomerPick>(result: CustomerPick(customer, cur)),
                    );
                  },
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
