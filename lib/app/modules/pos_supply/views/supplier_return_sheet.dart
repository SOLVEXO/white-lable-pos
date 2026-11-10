import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_return_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One receipt line of a supplier return: how many go back, and whether they come from the damaged pool. The Obx lives in this widget.
class _ReturnLineRow extends StatelessWidget {
  const _ReturnLineRow({required this.line});
  final ReturnLine line;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s3),
      child: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(line.name, style: t.subtitle.copyWith(color: p.textPrimary)),
            Text([if (line.lotNumber != null) 'Lot ${line.lotNumber}', '${line.max} received'].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
            const SizedBox(height: Space.s1),
            Row(
              children: [
                QuantityStepper(key: Key('retQty_${line.variantId}'), value: line.qty.value, min: 0, max: line.max, onChanged: (v) => line.qty.value = v),
                const SizedBox(width: Space.s3),
                FilterChip(key: Key('retDamaged_${line.variantId}'), label: const Text('From damaged'), selected: line.fromDamaged.value, onSelected: (v) => line.fromDamaged.value = v),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Return stock to a supplier (managers): pick a receipt (when opened from the supplier), the lines and quantities, a reason. Shows the credit created.
class SupplierReturnSheet extends StatefulWidget {
  const SupplierReturnSheet({super.key, required this.controller});
  final SupplierReturnController controller;

  static Future<bool?> open({SupplyReceipt? receipt, String? supplierId, SupplierReturnController? controller}) => AppBottomSheet.showGet<bool>(
    SupplierReturnSheet(
      controller: controller ?? SupplierReturnController(receipt: receipt, supplierId: supplierId),
    ),
    title: 'Return to supplier',
  );

  @override
  State<SupplierReturnSheet> createState() => _SupplierReturnSheetState();
}

class _SupplierReturnSheetState extends State<SupplierReturnSheet> {
  final _note = TextEditingController();
  SupplierReturnController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Obx(() {
      final done = c.result.value;
      if (done != null) return _done(context, done);
      if (!supplyOnlineRx().value) return const SizedBox(height: 260, child: SupplyNeedsInternet(subject: 'Returns'));
      if (c.picked.value == null) return _picker(context);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${c.picked.value!.receiptNumber} · ${c.picked.value!.supplierName}', style: t.subtitle.copyWith(color: p.textPrimary)),
          const SizedBox(height: Space.s3),
          for (final l in c.lines) _ReturnLineRow(line: l),
          Text('Reason', style: t.caption.copyWith(color: p.textSecondary)),
          Wrap(
            spacing: Space.s2,
            children: [
              for (final (code, label) in supplierReturnReasons)
                ChoiceChip(key: Key('retReason_$code'), label: Text(label), selected: c.reason.value == code, onSelected: (_) => c.reason.value = code),
            ],
          ),
          const SizedBox(height: Space.s3),
          AppTextField(key: const Key('retNote'), label: 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s),
          SupplyErrorText(c.error.value, errorKey: const Key('retError')),
          const SizedBox(height: Space.s3),
          AppButton(key: const Key('retConfirm'), label: 'Return to supplier', loading: c.busy.value, onPressed: c.canSubmit ? c.submit : null),
          const SizedBox(height: Space.s2),
        ],
      );
    });
  }

  Widget _picker(BuildContext context) {
    final p = context.palette;
    if (c.loading.value) {
      return const SizedBox(
        height: 160,
        child: Center(child: CircularProgressIndicator(key: Key('supplyLoading'))),
      );
    }
    if (c.error.value != null) {
      return SizedBox(
        height: 260,
        child: InvErrorState(message: c.error.value!, onRetry: c.reload),
      );
    }
    if (c.receipts.isEmpty) {
      return const SizedBox(
        height: 220,
        child: EmptyState(icon: Icons.inbox_outlined, title: 'No receipts', message: 'Nothing has been received from this supplier yet.'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Pick the receipt the goods came in on', style: context.type.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s2),
        for (final r in c.receipts)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: AppCard(
              key: Key('retReceipt_${r.id}'),
              radius: Radii.rMd,
              onTap: () => c.pick(r),
              child: Text('${r.receiptNumber} · ${invDate(r.createdAt)}', style: context.type.subtitle.copyWith(color: p.textPrimary)),
            ),
          ),
      ],
    );
  }

  Widget _done(BuildContext context, SupplierReturnResult r) {
    final p = context.palette;
    final t = context.type;
    final credit = supplyMoney(r.creditMinor, r.cur);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.check_circle_rounded, color: p.successFg, size: 40),
        const SizedBox(height: Space.s2),
        Text(
          'Return ${r.returnNumber}',
          key: const Key('retNumber'),
          textAlign: TextAlign.center,
          style: t.title.copyWith(color: p.textPrimary),
        ),
        if (credit != null) ...[
          const SizedBox(height: Space.s2),
          Text(
            'Credit created',
            textAlign: TextAlign.center,
            style: t.caption.copyWith(color: p.textSecondary),
          ),
          AmountText(credit, key: const Key('retCredit'), style: t.amountLg, alignment: MainAxisAlignment.center, animate: false),
        ],
        const SizedBox(height: Space.s4),
        AppButton(key: const Key('retDone'), label: 'Done', onPressed: () => Get.back<bool>(result: true)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
