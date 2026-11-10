import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_list_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One supplier row: name, contact, what is owed (only when the server stated it) and open orders.
class SupplierTile extends StatelessWidget {
  const SupplierTile({super.key, required this.supplier, required this.cur, required this.onTap});
  final Supplier supplier;
  final InvCur? cur;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final owed = supplyMoney(supplier.balanceMinor, cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('supplier_${supplier.id}'),
        radius: Radii.rMd,
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    supplier.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.subtitle.copyWith(color: p.textPrimary),
                  ),
                  if (supplier.contact.isNotEmpty)
                    Text(
                      supplier.contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.caption.copyWith(color: p.textMuted),
                    ),
                  if ((supplier.openOrders ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: Space.s1),
                      child: StatusBadge('${supplier.openOrders} open order${supplier.openOrders == 1 ? '' : 's'}', tone: StatusTone.info),
                    ),
                ],
              ),
            ),
            if (owed != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Owed', style: t.caption.copyWith(color: p.textSecondary)),
                  AmountText(owed, key: Key('supplierOwed_${supplier.id}'), style: t.amountMd, animate: false),
                ],
              ),
            Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Suppliers (managers / owners). Online only.
class SupplierListView extends StatelessWidget {
  SupplierListView({super.key, SupplierListController? controller}) : c = controller ?? Get.put(SupplierListController());
  final SupplierListController c;

  Future<void> _add() async {
    final saved = await SupplierFormSheet.open();
    if (saved == null) return;
    c.upsert(saved);
    CustomAppSnackbar.success('${saved.name} added.');
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Suppliers',
      actions: [
        Obx(
          () => IconButton(
            key: const Key('suppliersAdd'),
            tooltip: supplyOnlineRx().value ? 'Add supplier' : 'Add supplier (needs internet)',
            icon: const Icon(Icons.add_business_outlined),
            onPressed: supplyOnlineRx().value ? _add : null,
          ),
        ),
      ],
      body: Obx(() {
        if (!supplyOnlineRx().value) return const SupplyNeedsInternet(subject: 'Suppliers');
        if (c.loading.value && c.items.isEmpty) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (c.error.value != null && c.items.isEmpty) return InvErrorState(message: c.error.value!, onRetry: c.load);
        if (c.items.isEmpty) {
          return EmptyState(icon: Icons.storefront_outlined, title: 'No suppliers yet', message: 'Add a supplier to start purchase orders.', actionLabel: 'Add supplier', onAction: _add);
        }
        final list = c.visible;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s2),
              child: AppSearchBar(hint: 'Search suppliers', onChanged: (q) => c.query.value = q),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(icon: Icons.search_off_rounded, title: 'No suppliers found', message: 'Try another name.')
                  : RefreshIndicator(
                      onRefresh: c.load,
                      child: ListView.builder(
                        key: const Key('supplierList'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s6),
                        itemCount: list.length,
                        itemBuilder: (_, i) => SupplierTile(
                          supplier: list[i],
                          cur: c.cur.value,
                          onTap: () => Get.toNamed(Routes.posSupplySupplier, arguments: {'supplierId': list[i].id}),
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
