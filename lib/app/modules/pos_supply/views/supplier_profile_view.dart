import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/custom_app_snack_bar.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_profile_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/pay_supplier_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_form_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supplier_return_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One supplier: NTN / STRN, payment terms, what is owed with its aging, recent purchase orders and receipts. Actions: edit, order, pay, return, ledger.
class SupplierProfileView extends StatelessWidget {
  SupplierProfileView({super.key, required String supplierId, SupplierProfileController? controller}) : c = controller ?? Get.put(SupplierProfileController(supplierId: supplierId), tag: supplierId);
  final SupplierProfileController c;

  Future<void> _edit(SupplierProfile p) async {
    final saved = await SupplierFormSheet.open(existing: p.supplier);
    if (saved != null) c.applyEdit(saved);
  }

  Future<void> _pay(SupplierProfile p) async {
    final cur = p.cur;
    if (cur == null) return;
    final ok = await PaySupplierSheet.open(supplierId: p.supplier.id, exponent: cur.exponent, currencyCode: cur.code, balanceMinor: p.aging.balanceMinor);
    if (ok == true) await c.load();
  }

  Future<void> _return(SupplyReceipt r) async {
    final ok = await SupplierReturnSheet.open(receipt: r);
    if (ok == true) {
      CustomAppSnackbar.success('Return recorded.');
      await c.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Supplier',
      maxWidth: 760,
      body: Obx(() {
        if (!supplyOnlineRx().value && c.profile.value == null) return const SupplyNeedsInternet(subject: 'Supplier details');
        final p = c.profile.value;
        if (c.loading.value && p == null) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (p == null) return InvErrorState(message: c.error.value ?? 'Try again.', onRetry: c.load);
        return RefreshIndicator(onRefresh: c.load, child: _content(context, p));
      }),
    );
  }

  Widget _content(BuildContext context, SupplierProfile p) {
    final pal = context.palette;
    final t = context.type;
    final s = p.supplier;
    final owed = supplyMoney(p.aging.balanceMinor, p.cur);
    Widget detail(String label, String? value) => value == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.s1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(label, style: t.caption.copyWith(color: pal.textSecondary)),
                ),
                Expanded(
                  child: Text(value, style: t.body.copyWith(color: pal.textPrimary)),
                ),
              ],
            ),
          );
    return ListView(
      key: const Key('supplierProfileList'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        Text(s.name, style: t.title.copyWith(color: pal.textPrimary)),
        const SizedBox(height: Space.s3),
        AppCard(
          key: const Key('supplierDetails'),
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              detail('Contact', s.contactName),
              detail('Phone', s.phone),
              detail('E-mail', s.email),
              detail('Address', s.address),
              detail('NTN', s.ntn),
              detail('STRN', s.strn),
              detail('Payment terms', s.paymentTerms),
              detail('Lead time', s.leadTimeDays == null ? null : '${s.leadTimeDays} days'),
              detail('Notes', s.notes),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        AppCard(
          key: const Key('supplierOwedCard'),
          radius: Radii.rMd,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You owe', style: t.caption.copyWith(color: pal.textSecondary)),
              if (owed != null) AmountText(owed, key: const Key('supplierBalance'), style: t.amountLg, animate: false),
              const SizedBox(height: Space.s3),
              AgingBuckets(aging: p.aging, cur: p.cur),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        Wrap(
          spacing: Space.s2,
          runSpacing: Space.s2,
          children: [
            AppButton(key: const Key('supplierEdit'), label: 'Edit', variant: AppButtonVariant.secondary, expand: false, onPressed: () => _edit(p)),
            AppButton(
              key: const Key('supplierNewPo'),
              label: 'New order',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => Get.toNamed(Routes.posSupplyOrderForm, arguments: {'supplierId': s.id}),
            ),
            AppButton(key: const Key('supplierPay'), label: 'Pay', expand: false, onPressed: p.cur == null || !supplyOnlineRx().value ? null : () => _pay(p)),
            AppButton(
              key: const Key('supplierLedger'),
              label: 'Ledger',
              variant: AppButtonVariant.secondary,
              expand: false,
              onPressed: () => Get.toNamed(Routes.posSupplyLedger, arguments: {'supplierId': s.id}),
            ),
          ],
        ),
        const InvSectionTitle('Recent purchase orders'),
        if (p.orders.isEmpty)
          Text('No purchase orders yet.', style: t.body.copyWith(color: pal.textMuted))
        else
          for (final o in p.orders)
            PoTile(
              order: o,
              cur: p.cur,
              onTap: () => Get.toNamed(Routes.posSupplyOrder, arguments: {'orderId': o.id}),
            ),
        const InvSectionTitle('Recent receipts'),
        if (p.receipts.isEmpty)
          Text('Nothing received yet.', style: t.body.copyWith(color: pal.textMuted))
        else
          for (final r in p.receipts) _ReceiptTile(receipt: r, cur: p.cur, onReturn: () => _return(r)),
      ],
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt, required this.cur, required this.onReturn});
  final SupplyReceipt receipt;
  final dynamic cur;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final t = context.type;
    final money = supplyMoney(receipt.totalMinor, receipt.cur ?? cur);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('receipt_${receipt.id}'),
        radius: Radii.rMd,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(receipt.receiptNumber, style: t.subtitle.copyWith(color: pal.textPrimary)),
                  Text(
                    [
                      invDate(receipt.createdAt),
                      if (receipt.poNumber != null) 'PO ${receipt.poNumber}',
                      if (receipt.supplierInvoiceNumber != null) 'Invoice ${receipt.supplierInvoiceNumber}',
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: t.caption.copyWith(color: pal.textMuted),
                  ),
                ],
              ),
            ),
            if (money != null) Text(money, style: t.amountMd.copyWith(color: pal.textPrimary)),
            IconButton(key: Key('receiptReturn_${receipt.id}'), tooltip: 'Return to supplier', icon: const Icon(Icons.assignment_return_outlined), onPressed: onReturn),
          ],
        ),
      ),
    );
  }
}
