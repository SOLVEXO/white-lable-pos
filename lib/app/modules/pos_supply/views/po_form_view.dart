import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/po_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/product_search_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One editable line: quantity stepper + unit cost in major units. Owns its text controller; the Obx lives in this widget.
class _PoFormLineCard extends StatefulWidget {
  const _PoFormLineCard({super.key, required this.line, required this.controller});
  final PoFormLine line;
  final PoFormController controller;
  @override
  State<_PoFormLineCard> createState() => _PoFormLineCardState();
}

class _PoFormLineCardState extends State<_PoFormLineCard> {
  late final _cost = TextEditingController(text: widget.line.costText.value);

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final l = widget.line;
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        radius: Radii.rMd,
        child: Obx(
          () => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.subtitle.copyWith(color: p.textPrimary),
                    ),
                  ),
                  IconButton(key: Key('poLineRemove_${l.variantId}'), tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: () => c.removeLine(l)),
                ],
              ),
              if (l.optionsLabel.isNotEmpty || l.sku != null)
                Text([if (l.sku != null) l.sku!, if (l.optionsLabel.isNotEmpty) l.optionsLabel].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  QuantityStepper(key: Key('poLineQty_${l.variantId}'), value: l.qty.value, min: 1, max: 1000000, onChanged: (v) => l.qty.value = v),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: AppTextField(
                      key: Key('poLineCost_${l.variantId}'),
                      label: 'Unit cost${c.cur.value == null ? '' : ' (${c.cur.value!.code})'}',
                      controller: _cost,
                      mono: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                      errorText: l.costText.value.isNotEmpty && c.unitCostMinor(l) == null ? 'Check the cost' : null,
                      onChanged: (s) => l.costText.value = s,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// New purchase order, or the edit of one (managers): supplier, lines added from the products already in the store, quantity and cost, expected date, notes.
class PoFormView extends StatefulWidget {
  const PoFormView({super.key, this.orderId, this.supplierId, this.controller});
  final String? orderId, supplierId;
  final PoFormController? controller;
  @override
  State<PoFormView> createState() => _PoFormViewState();
}

class _PoFormViewState extends State<PoFormView> {
  late final PoFormController c =
      widget.controller ??
      Get.put(
        PoFormController(orderId: widget.orderId, presetSupplierId: widget.supplierId),
        tag: 'po_${widget.orderId ?? 'new'}',
      );
  late final _notes = TextEditingController(text: c.notes.value);
  Worker? _sync;

  @override
  void initState() {
    super.initState();
    _sync = ever<String>(c.notes, (v) {
      if (_notes.text != v) _notes.text = v;
    });
  }

  @override
  void dispose() {
    _sync?.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickSupplier() async {
    final picked = await AppBottomSheet.showGet<Supplier>(_SupplierPicker(suppliers: c.suppliers), title: 'Choose a supplier');
    if (picked != null) c.pickSupplier(picked);
  }

  Future<void> _addProduct() async {
    final row = await SupplyProductSearchSheet.open(c.search);
    if (row != null) c.addProduct(row);
  }

  Future<void> _save() async {
    final o = await c.submit();
    if (o != null && mounted) Get.back<PurchaseOrder>(result: o);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return InvScaffold(
      title: c.isEdit ? 'Edit purchase order' : 'New purchase order',
      maxWidth: 760,
      body: Obx(() {
        if (!supplyOnlineRx().value) return const SupplyNeedsInternet(subject: 'Purchase orders');
        if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (c.loadError.value != null) return InvErrorState(message: c.loadError.value!, onRetry: c.reload);
        final total = c.totalMinor;
        final money = supplyMoney(total, c.cur.value);
        return ListView(
          key: const Key('poFormList'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            if (c.isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.s3),
                child: Text(
                  'Saving sends an approved order back to draft; it needs approving again.',
                  key: const Key('poFormEditNote'),
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
              ),
            AppCard(
              key: const Key('poFormSupplier'),
              radius: Radii.rMd,
              onTap: _pickSupplier,
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: p.textMuted),
                  const SizedBox(width: Space.s3),
                  Expanded(
                    child: Text(c.supplier.value?.name ?? 'Choose a supplier', style: t.subtitle.copyWith(color: c.supplier.value == null ? p.textMuted : p.textPrimary)),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.textMuted),
                ],
              ),
            ),
            const InvSectionTitle('Products'),
            if (c.lines.isEmpty) Text('No products yet. Add the products you are ordering.', style: t.body.copyWith(color: p.textMuted)),
            for (final l in c.lines) _PoFormLineCard(key: ObjectKey(l), line: l, controller: c),
            const SizedBox(height: Space.s2),
            AppButton(key: const Key('poAddProduct'), label: 'Add product', variant: AppButtonVariant.secondary, icon: Icons.add_rounded, onPressed: _addProduct),
            const SizedBox(height: Space.s2),
            // G5.1: scan item after item onto the order
            AppButton(key: const Key('poScanAdd'), label: 'Scan to add', variant: AppButtonVariant.ghost, icon: Icons.qr_code_scanner_rounded, onPressed: () => Get.to<String>(() => PosScanCameraView(title: 'Scan to add', onCode: c.addByCode))),
            if (money != null)
              Padding(
                padding: const EdgeInsets.only(top: Space.s3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Products total', style: t.body.copyWith(color: p.textSecondary)),
                    ),
                    Text(
                      money,
                      key: const Key('poFormTotal'),
                      style: t.amountLg.copyWith(color: p.textPrimary),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: Space.s4),
            SupplyDateField(
              label: 'Expected date',
              value: c.expectedAt.value,
              onPick: () async {
                final d = await pickSupplyDate(context, initial: c.expectedAt.value, first: DateTime.now().subtract(const Duration(days: 1)));
                if (d != null) c.expectedAt.value = d;
              },
              onClear: () => c.expectedAt.value = null,
            ),
            const SizedBox(height: Space.s3),
            AppTextField(key: const Key('poFormNotes'), label: 'Notes (optional)', controller: _notes, maxLines: 3, onChanged: (s) => c.notes.value = s),
            SupplyErrorText(c.error.value, errorKey: const Key('poFormError')),
            const SizedBox(height: Space.s4),
            AppButton(key: const Key('poFormSave'), label: c.isEdit ? 'Save changes' : 'Save as draft', loading: c.busy.value, onPressed: c.canSubmit ? _save : null),
          ],
        );
      }),
    );
  }
}

class _SupplierPicker extends StatelessWidget {
  const _SupplierPicker({required this.suppliers});
  final List<Supplier> suppliers;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (suppliers.isEmpty) {
      return const SizedBox(
        height: 200,
        child: EmptyState(icon: Icons.storefront_outlined, title: 'No suppliers', message: 'Add a supplier first (Suppliers).'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final s in suppliers)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: AppCard(
              key: Key('pickSupplier_${s.id}'),
              radius: Radii.rMd,
              onTap: () => Get.back<Supplier>(result: s),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(s.name, style: context.type.subtitle.copyWith(color: p.textPrimary)),
              ),
            ),
          ),
      ],
    );
  }
}
