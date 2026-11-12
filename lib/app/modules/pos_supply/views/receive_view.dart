import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/receive_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/product_search_sheet.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_home/widgets/pos_scan_camera_view.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// A date strictly before today (a warning only: the server decides what an expired lot means).
bool _isPast(DateTime? d) {
  if (d == null) return false;
  final now = DateTime.now();
  return DateTime(d.year, d.month, d.day).isBefore(DateTime(now.year, now.month, now.day));
}

/// One line being received. Owns its text controllers; the Obx is inside this widget's build().
class ReceiveLineCard extends StatefulWidget {
  const ReceiveLineCard({super.key, required this.line, required this.controller});
  final ReceiveLine line;
  final ReceiveController controller;
  @override
  State<ReceiveLineCard> createState() => _ReceiveLineCardState();
}

class _ReceiveLineCardState extends State<ReceiveLineCard> {
  late final _lot = TextEditingController(text: widget.line.lotNumber.value);
  late final _cost = TextEditingController(text: widget.line.costTextRx.value);
  late final _serials = TextEditingController(text: widget.line.serialsText.value);

  @override
  void dispose() {
    _serials.dispose();
    _lot.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final l = widget.line;
    final c = widget.controller;
    final key = l.poItemId ?? l.variantId ?? l.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('recvLine_$key'),
        radius: Radii.rMd,
        child: Obx(() {
          final maxGood = c.maxFor(l, good: true);
          final maxDamaged = c.maxFor(l, good: false);
          return Column(
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
                  if (c.direct) IconButton(key: Key('recvRemove_$key'), tooltip: 'Remove', icon: const Icon(Icons.close_rounded), onPressed: () => c.removeLine(l)),
                ],
              ),
              Text(
                [if (l.sku != null) l.sku!, if (l.optionsLabel.isNotEmpty) l.optionsLabel, if (l.remaining != null) '${l.remaining} still due'].join(' · '),
                style: t.caption.copyWith(color: p.textMuted),
              ),
              const SizedBox(height: Space.s2),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Good', style: t.caption.copyWith(color: p.textSecondary)),
                        QuantityStepper(key: Key('recvGood_$key'), value: l.good.value, min: 0, max: maxGood, onChanged: (v) => l.good.value = v),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Damaged', style: t.caption.copyWith(color: p.textSecondary)),
                        QuantityStepper(key: Key('recvDamaged_$key'), value: l.damaged.value, min: 0, max: maxDamaged, onChanged: (v) => l.damaged.value = v),
                      ],
                    ),
                  ),
                ],
              ),
              if (c.direct) ...[
                const SizedBox(height: Space.s3),
                AppTextField(
                  key: Key('recvCost_$key'),
                  label: 'Unit cost${c.cur.value == null ? '' : ' (${c.cur.value!.code})'}',
                  controller: _cost,
                  mono: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  onChanged: (s) => l.costTextRx.value = s,
                ),
              ],
              // G5.2: serial-tracked items — one serial per unit, typed or scanned (a scanner types into the box and presses Enter)
              if (l.trackSerials) ...[
                const SizedBox(height: Space.s3),
                AppTextField(key: Key('recvSerials_$key'), label: 'Serial numbers (one per line)', controller: _serials, mono: true, maxLines: 4, onChanged: (s) => l.serialsText.value = s),
                Padding(
                  padding: const EdgeInsets.only(top: Space.s1),
                  child: Text('${l.serials.length} of ${l.total} serial numbers', key: Key('recvSerialCount_$key'), style: t.caption.copyWith(color: l.serials.length == l.total ? p.successFg : p.warningFg)),
                ),
              ],
              if (l.showLot.value) ...[
                const SizedBox(height: Space.s3),
                AppTextField(key: Key('recvLot_$key'), label: 'Lot number', controller: _lot, mono: true, onChanged: (s) => l.lotNumber.value = s),
                const SizedBox(height: Space.s2),
                SupplyDateField(
                  key: Key('recvExpiry_$key'),
                  label: 'Expiry date',
                  value: l.expiry.value,
                  onPick: () async {
                    final d = await pickSupplyDate(context, initial: l.expiry.value, first: DateTime.now().subtract(const Duration(days: 365)));
                    if (d != null) l.expiry.value = d;
                  },
                  onClear: () => l.expiry.value = null,
                ),
                if (_isPast(l.expiry.value))
                  Padding(
                    padding: const EdgeInsets.only(top: Space.s2),
                    child: Row(
                      key: Key('recvExpiryPast_$key'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: p.warningFg),
                        const SizedBox(width: Space.s2),
                        Expanded(
                          child: Text('This date has already passed — the stock will be treated as expired.', style: t.caption.copyWith(color: p.warningFg)),
                        ),
                      ],
                    ),
                  ),
              ] else
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(key: Key('recvAddLot_$key'), onPressed: () => l.showLot.value = true, child: const Text('Add lot number')),
                ),
            ],
          );
        }),
      ),
    );
  }
}

/// Receive stock: against an approved purchase order (arguments `orderId`), or without one (managers; pick the supplier and cost each line).
/// Per line: good and damaged quantities, and a lot number with expiry when the product tracks lots. Shows the receipt (GRN number) afterwards.
class ReceiveView extends StatefulWidget {
  const ReceiveView({super.key, this.orderId, this.supplierId, this.controller});
  final String? orderId, supplierId;
  final ReceiveController? controller;
  @override
  State<ReceiveView> createState() => _ReceiveViewState();
}

class _ReceiveViewState extends State<ReceiveView> {
  late final ReceiveController c =
      widget.controller ??
      Get.put(
        ReceiveController(orderId: widget.orderId, presetSupplierId: widget.supplierId),
        tag: 'recv_${widget.orderId ?? 'direct'}',
      );
  final _invoice = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _invoice.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickSupplier() async {
    final picked = await AppBottomSheet.showGet<Supplier>(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.suppliers.isEmpty)
            const SizedBox(
              height: 160,
              child: EmptyState(icon: Icons.storefront_outlined, title: 'No suppliers', message: 'Add a supplier first.'),
            ),
          for (final s in c.suppliers)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.s2),
              child: AppCard(
                key: Key('pickSupplier_${s.id}'),
                radius: Radii.rMd,
                onTap: () => Get.back<Supplier>(result: s),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(s.name, style: context.type.subtitle.copyWith(color: context.palette.textPrimary)),
                ),
              ),
            ),
        ],
      ),
      title: 'Choose a supplier',
    );
    if (picked != null) c.pickSupplier(picked);
  }

  Future<void> _addProduct() async {
    final row = await SupplyProductSearchSheet.open(c.search);
    if (row != null) c.addProduct(row);
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: c.direct ? 'Receive stock' : 'Receive against order',
      maxWidth: 760,
      body: Obx(() {
        if (!supplyOnlineRx().value && c.result.value == null) return const SupplyNeedsInternet(subject: 'Receiving stock');
        if (c.loading.value) return const Center(child: CircularProgressIndicator(key: Key('supplyLoading')));
        if (c.loadError.value != null) return InvErrorState(message: c.loadError.value!, onRetry: c.reload);
        final done = c.result.value;
        if (done != null) return _done(context, done);
        return _form(context);
      }),
    );
  }

  Widget _form(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final o = c.order.value;
    return ListView(
      key: const Key('receiveList'),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
      children: [
        if (!c.direct && o != null) ...[
          Text(o.poNumber, style: t.title.copyWith(color: p.textPrimary)),
          Text(o.supplierName, style: t.body.copyWith(color: p.textSecondary)),
        ] else
          AppCard(
            key: const Key('recvSupplier'),
            radius: Radii.rMd,
            onTap: _pickSupplier,
            child: Row(
              children: [
                Icon(Icons.storefront_outlined, color: p.textMuted),
                const SizedBox(width: Space.s3),
                Expanded(
                  child: Text(c.supplier.value?.name ?? 'Choose the supplier', style: t.subtitle.copyWith(color: c.supplier.value == null ? p.textMuted : p.textPrimary)),
                ),
                Icon(Icons.chevron_right_rounded, color: p.textMuted),
              ],
            ),
          ),
        const InvSectionTitle('Products'),
        if (c.lines.isEmpty)
          Text(
            c.direct ? 'Add the products that arrived.' : 'Everything on this order has been received.',
            key: const Key('recvNoLines'),
            style: t.body.copyWith(color: p.textMuted),
          ),
        for (final l in c.lines) ReceiveLineCard(key: ObjectKey(l), line: l, controller: c),
        if (c.direct) AppButton(key: const Key('recvAddProduct'), label: 'Add product', variant: AppButtonVariant.secondary, icon: Icons.add_rounded, onPressed: _addProduct),
        // G5.1: count what arrived by scanning each item
        Padding(
          padding: const EdgeInsets.only(top: Space.s2),
          child: AppButton(key: const Key('recvScan'), label: 'Scan to receive', variant: AppButtonVariant.ghost, icon: Icons.qr_code_scanner_rounded, onPressed: () => Get.to<String>(() => PosScanCameraView(title: 'Scan to receive', onCode: c.addByCode))),
        ),
        const InvSectionTitle('Supplier invoice (optional)'),
        AppTextField(key: const Key('recvInvoice'), label: 'Invoice number', controller: _invoice, mono: true, onChanged: (s) => c.invoiceNumber.value = s),
        const SizedBox(height: Space.s2),
        Obx(
          () => SupplyDateField(
            key: const Key('recvInvoiceDate'),
            label: 'Invoice date',
            value: c.invoiceDate.value,
            onPick: () async {
              final d = await pickSupplyDate(context, initial: c.invoiceDate.value, last: DateTime.now());
              if (d != null) c.invoiceDate.value = d;
            },
            onClear: () => c.invoiceDate.value = null,
          ),
        ),
        const SizedBox(height: Space.s2),
        AppTextField(key: const Key('recvNote'), label: 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('recvError'))),
        const SizedBox(height: Space.s4),
        Obx(() => AppButton(key: const Key('recvConfirm'), label: 'Confirm receipt', loading: c.busy.value, onPressed: c.canSubmit ? c.submit : null)),
      ],
    );
  }

  Widget _done(BuildContext context, ReceiveResult r) {
    final p = context.palette;
    final t = context.type;
    final rc = r.receipt;
    final total = supplyMoney(rc.totalMinor, rc.cur ?? r.cur);
    return ListView(
      key: const Key('receiveDone'),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s6, Space.s4, Space.s8),
      children: [
        Icon(Icons.check_circle_rounded, color: p.successFg, size: 48),
        const SizedBox(height: Space.s2),
        Text(
          'Stock received',
          textAlign: TextAlign.center,
          style: t.title.copyWith(color: p.textPrimary),
        ),
        Text(
          rc.receiptNumber,
          key: const Key('recvGrn'),
          textAlign: TextAlign.center,
          style: t.amountLg.copyWith(color: p.textPrimary),
        ),
        if (r.duplicate)
          Text(
            'This receipt had already been recorded.',
            key: const Key('recvDuplicate'),
            textAlign: TextAlign.center,
            style: t.caption.copyWith(color: p.textSecondary),
          ),
        Text(
          [rc.supplierName, if (rc.poNumber != null) 'PO ${rc.poNumber}'].join(' · '),
          textAlign: TextAlign.center,
          style: t.body.copyWith(color: p.textSecondary),
        ),
        const SizedBox(height: Space.s4),
        for (final l in rc.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: AppCard(
              radius: Radii.rMd,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l.name, style: t.subtitle.copyWith(color: p.textPrimary)),
                        Text([if (l.lotNumber != null) 'Lot ${l.lotNumber}', if (l.expiryDate != null) 'Expires ${invDate(l.expiryDate)}'].join(' · '), style: t.caption.copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                  Text('${l.qtyGood} good${l.qtyDamaged > 0 ? ' · ${l.qtyDamaged} damaged' : ''}', style: t.bodySmall.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
          ),
        if (total != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.s2),
            child: Text(
              'Total $total',
              key: const Key('recvTotal'),
              textAlign: TextAlign.end,
              style: t.amountMd.copyWith(color: p.textPrimary),
            ),
          ),
        const SizedBox(height: Space.s4),
        AppButton(
          key: const Key('recvDone'),
          label: 'Done',
          onPressed: () => Get.back<ReceiveResult>(result: r),
        ),
      ],
    );
  }
}
