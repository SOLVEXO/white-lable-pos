import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_stock_ops_models.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/views/inv_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_reports/controllers/reports_common.dart';
import 'package:solvexo_pos/app/modules/pos_reports/views/report_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_stock_ops/controllers/transfers_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// G4.6 transfers: open / received / cancelled / all, a row per transfer (what, from → to, how many arrived), Receive and Cancel on open ones, and
/// "Send stock" to ship a variant to another location.
class TransfersView extends StatefulWidget {
  const TransfersView({super.key, this.controller});
  final TransfersController? controller;
  @override
  State<TransfersView> createState() => _TransfersViewState();
}

class _TransfersViewState extends State<TransfersView> {
  late final String _tag = 'transfers_${identityHashCode(this)}';
  late final TransfersController c = widget.controller ?? Get.put(TransfersController(), tag: _tag);

  @override
  void dispose() {
    if (widget.controller == null) Get.delete<TransfersController>(tag: _tag);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InvScaffold(
      title: 'Transfers',
      actions: [
        Obx(() => TextButton.icon(key: const Key('transferNew'), onPressed: c.busy.value ? null : () => ShipTransferSheet.open(c), icon: const Icon(Icons.local_shipping_outlined), label: const Text('Send stock'))),
      ],
      body: Obx(() {
        if (!reportsOnlineRx().value && c.transfers.isEmpty) return const ReportsNeedsInternet(subject: 'Transfers');
        final p = context.palette;
        return ListView(
          key: const Key('transferList'),
          padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s8),
          children: [
            Wrap(
              spacing: Space.s2,
              children: [
                for (final (id, label) in TransfersController.statuses)
                  ChoiceChip(key: Key('transferStatus_$id'), label: Text(label), selected: c.status.value == id, onSelected: (_) => c.setStatus(id)),
              ],
            ),
            const SizedBox(height: Space.s2),
            if (c.notice.value != null) ReportInfo(key: const Key('transferNotice'), c.notice.value!, icon: Icons.check_circle_outline_rounded),
            if (c.actionError.value != null)
              Container(
                key: const Key('transferError'),
                margin: const EdgeInsets.only(bottom: Space.s2),
                padding: const EdgeInsets.all(Space.s3),
                decoration: BoxDecoration(color: p.dangerSoft, borderRadius: Radii.rMd),
                child: Text(c.actionError.value!, style: context.type.bodySmall.copyWith(color: p.dangerFg)),
              ),
            if (c.loading.value && c.transfers.isEmpty)
              const Padding(padding: EdgeInsets.all(Space.s6), child: Center(child: CircularProgressIndicator(key: Key('transferLoading'))))
            else if (c.error.value != null && c.transfers.isEmpty)
              InvErrorState(message: c.error.value!, onRetry: c.load)
            else if (c.transfers.isEmpty)
              EmptyState(key: const Key('transferEmpty'), icon: Icons.local_shipping_outlined, title: 'No transfers', message: c.status.value == 'open' ? 'Nothing is on its way between locations.' : 'None with this status.')
            else
              for (final t in c.transfers) _TransferCard(c: c, t: t),
          ],
        );
      }),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({required this.c, required this.t});
  final TransfersController c;
  final StockTransfer t;

  Future<void> _cancel(BuildContext context) async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Cancel this transfer?'),
        content: Text('${t.quantity} × ${t.itemName} go back to ${t.fromLocationName}.'),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text('Keep it')),
          TextButton(key: const Key('transferCancelConfirm'), onPressed: () => Get.back(result: true), child: const Text('Cancel transfer')),
        ],
      ),
    );
    if (ok == true) await c.cancel(t);
  }

  @override
  Widget build(BuildContext context) => Obx(() => _build(context)); // reads c.busy: its own Obx

  Widget _build(BuildContext context) {
    final p = context.palette;
    final tt = context.type;
    final tone = switch (t.status) {
      'received' => StatusTone.success,
      'cancelled' => StatusTone.neutral,
      'partially_received' => StatusTone.warning,
      _ => StatusTone.accent,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: AppCard(
        key: Key('transfer_${t.id}'),
        radius: Radii.rMd,
        padding: const EdgeInsets.all(Space.s3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.itemName, style: tt.subtitle.copyWith(color: p.textPrimary))),
                StatusBadge(t.statusLabel, tone: tone),
              ],
            ),
            const SizedBox(height: Space.s1),
            Text('${t.fromLocationName}  →  ${t.toLocationName}', style: tt.body.copyWith(color: p.textSecondary)),
            Text(
              [
                t.receivedQuantity > 0 && t.open ? '${t.receivedQuantity} of ${t.quantity} arrived' : '${t.quantity} unit${t.quantity == 1 ? '' : 's'}',
                if (t.createdAt != null) 'sent ${DateFormat('d MMM, HH:mm').format(t.createdAt!)}',
                if (t.transferredByName != null) 'by ${t.transferredByName}',
              ].join(' · '),
              style: tt.caption.copyWith(color: p.textMuted),
            ),
            if (t.note != null) Text(t.note!, style: tt.caption.copyWith(color: p.textMuted)),
            if (t.open)
              Padding(
                padding: const EdgeInsets.only(top: Space.s2),
                child: Wrap(
                  spacing: Space.s2,
                  children: [
                    FilledButton.tonal(key: Key('transferReceive_${t.id}'), onPressed: c.busy.value ? null : () => ReceiveTransferSheet.open(c, t), child: const Text('Receive')),
                    if (t.cancellable) TextButton(key: Key('transferCancel_${t.id}'), onPressed: c.busy.value ? null : () => _cancel(context), child: const Text('Cancel')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// How many of an open transfer arrived (all that is outstanding by default).
class ReceiveTransferSheet extends StatefulWidget {
  const ReceiveTransferSheet({super.key, required this.c, required this.t});
  final TransfersController c;
  final StockTransfer t;
  static Future<void> open(TransfersController c, StockTransfer t) => Get.bottomSheet(ReceiveTransferSheet(c: c, t: t), isScrollControlled: true, backgroundColor: Colors.transparent);
  @override
  State<ReceiveTransferSheet> createState() => _ReceiveTransferSheetState();
}

class _ReceiveTransferSheetState extends State<ReceiveTransferSheet> {
  late final TextEditingController _qty = TextEditingController(text: '${widget.t.outstanding}');
  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppSheetSurface(
    key: const Key('receiveSheet'),
    title: 'Receive · ${widget.t.itemName}',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${widget.t.outstanding} on the way to ${widget.t.toLocationName}.', style: context.type.bodySmall.copyWith(color: context.palette.textSecondary)),
        const SizedBox(height: Space.s2),
        TextField(
          key: const Key('receiveQty'),
          controller: _qty,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'How many arrived'),
        ),
        const SizedBox(height: Space.s3),
        Obx(
          () => AppButton(
            key: const Key('receiveConfirm'),
            label: 'Receive',
            loading: widget.c.busy.value,
            onPressed: widget.c.busy.value
                ? null
                : () async {
                    final ok = await widget.c.receive(widget.t, int.tryParse(_qty.text) ?? 0);
                    if (ok) Get.back();
                  },
          ),
        ),
        Obx(
          () => widget.c.actionError.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s2),
                  child: Text(widget.c.actionError.value!, key: const Key('receiveError'), style: context.type.caption.copyWith(color: context.palette.dangerFg)),
                ),
        ),
      ],
    ),
  );
}

/// Ship a variant: find the product, pick the variant, from → to, how many, an optional note.
class ShipTransferSheet extends StatefulWidget {
  const ShipTransferSheet({super.key, required this.c});
  final TransfersController c;
  static Future<void> open(TransfersController c) {
    c.actionError.value = null;
    return Get.bottomSheet(ShipTransferSheet(c: c), isScrollControlled: true, backgroundColor: Colors.transparent);
  }

  @override
  State<ShipTransferSheet> createState() => _ShipTransferSheetState();
}

class _ShipTransferSheetState extends State<ShipTransferSheet> {
  final _q = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  List<PosProductModel> _found = const [];
  PosProductModel? _product;
  PosProductVariant? _variant;
  String? _from, _to;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  void _search(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final r = await widget.c.search(v);
      if (mounted) setState(() => _found = r);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final locs = widget.c.locations;
    return AppSheetSurface(
      key: const Key('shipSheet'),
      title: 'Send stock to another location',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_product == null) ...[
            TextField(key: const Key('shipSearch'), controller: _q, decoration: const InputDecoration(labelText: 'Find a product (name, SKU, barcode)'), onChanged: _search),
            for (final pr in _found.take(8))
              ListTile(
                key: Key('shipProduct_${pr.productId}'),
                contentPadding: EdgeInsets.zero,
                title: Text(pr.name),
                subtitle: Text('${pr.variants.length} variant${pr.variants.length == 1 ? '' : 's'}'),
                onTap: () => setState(() {
                  _product = pr;
                  _variant = pr.variants.length == 1 ? pr.variants.first : null;
                }),
              ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_product!.name, style: t.subtitle.copyWith(color: p.textPrimary)),
              trailing: TextButton(onPressed: () => setState(() => _product = _variant = null), child: const Text('Change')),
            ),
            if (_product!.variants.length > 1)
              Wrap(
                spacing: Space.s2,
                children: [
                  for (final v in _product!.variants)
                    ChoiceChip(key: Key('shipVariant_${v.variantId}'), label: Text(v.label), selected: _variant?.variantId == v.variantId, onSelected: (_) => setState(() => _variant = v)),
                ],
              ),
          ],
          const SizedBox(height: Space.s2),
          if (locs.length < 2)
            Text('Transfers need at least two locations. Add one in Locations.', key: const Key('shipNoLocations'), style: t.caption.copyWith(color: p.warningFg))
          else ...[
            DropdownButtonFormField<String>(
              key: const Key('shipFrom'),
              initialValue: _from,
              decoration: const InputDecoration(labelText: 'From'),
              items: [for (final l in locs) DropdownMenuItem(value: l.id, child: Text(l.name))],
              onChanged: (v) => setState(() => _from = v),
            ),
            DropdownButtonFormField<String>(
              key: const Key('shipTo'),
              initialValue: _to,
              decoration: const InputDecoration(labelText: 'To'),
              items: [
                for (final l in locs)
                  if (l.id != _from) DropdownMenuItem(value: l.id, child: Text(l.name)),
              ],
              onChanged: (v) => setState(() => _to = v),
            ),
          ],
          TextField(
            key: const Key('shipQty'),
            controller: _qty,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'How many'),
          ),
          TextField(key: const Key('shipNote'), controller: _note, maxLength: 300, decoration: const InputDecoration(labelText: 'Note (optional)')),
          Obx(() => widget.c.actionError.value == null ? const SizedBox.shrink() : Text(widget.c.actionError.value!, key: const Key('shipError'), style: t.caption.copyWith(color: p.dangerFg))),
          const SizedBox(height: Space.s2),
          Obx(
            () => AppButton(
              key: const Key('shipConfirm'),
              label: 'Send',
              loading: widget.c.busy.value,
              onPressed: widget.c.busy.value || _variant == null || _from == null || _to == null
                  ? null
                  : () async {
                      final ok = await widget.c.ship(variantId: _variant!.variantId, fromLocationId: _from!, toLocationId: _to!, quantity: int.tryParse(_qty.text) ?? 0, note: _note.text);
                      if (ok) Get.back();
                    },
            ),
          ),
        ],
      ),
    );
  }
}
