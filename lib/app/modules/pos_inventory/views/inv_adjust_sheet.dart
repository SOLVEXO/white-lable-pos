import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_inventory/controllers/inv_adjust_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Adjust stock: a − / + stepper or a typed number, a reason, a note (required for "Other") and Confirm. The server decides whether it is
/// allowed; a change above a cashier's limit asks a manager's PIN and is sent again with their approval.
class InvAdjustSheet extends StatefulWidget {
  const InvAdjustSheet({super.key, required this.variantId, required this.currentStock, this.productName, this.controller});
  final String variantId;
  final int currentStock;
  final String? productName;
  final InvAdjustController? controller;

  @override
  State<InvAdjustSheet> createState() => _InvAdjustSheetState();
}

class _InvAdjustSheetState extends State<InvAdjustSheet> {
  late final InvAdjustController c = widget.controller ?? InvAdjustController(variantId: widget.variantId, currentStock: widget.currentStock);
  final _delta = TextEditingController(text: '0');
  final _note = TextEditingController();
  Worker? _sync;

  @override
  void initState() {
    super.initState();
    // the stepper and the typed number are one value
    _sync = ever<int>(c.delta, (v) {
      if ((int.tryParse(_delta.text) ?? 0) != v) _delta.text = '$v';
    });
  }

  @override
  void dispose() {
    _sync?.dispose();
    _delta.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final ok = await c.submit();
    if (ok && mounted) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.productName != null)
          Text(
            widget.productName!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.subtitle.copyWith(color: p.textPrimary),
          ),
        Text('${widget.currentStock} on hand', style: t.bodySmall.copyWith(color: p.textMuted)),
        const SizedBox(height: Space.s4),
        Row(
          children: [
            Obx(() => QuantityStepper(key: const Key('invAdjustStepper'), value: c.delta.value, min: -1000000, max: 1000000, onChanged: c.setDelta)),
            const SizedBox(width: Space.s3),
            Expanded(
              child: AppTextField(
                key: const Key('invAdjustDelta'),
                label: 'Change (+ adds, − removes)',
                controller: _delta,
                mono: true,
                keyboardType: const TextInputType.numberWithOptions(signed: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d{0,7}'))],
                onChanged: (s) => c.setDelta(int.tryParse(s) ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s2),
        Obx(
          () => c.preview.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  c.preview,
                  key: const Key('invAdjustPreview'),
                  style: t.bodySmall.copyWith(color: p.textSecondary),
                ),
        ),
        const SizedBox(height: Space.s3),
        Text('Reason', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            runSpacing: Space.s1,
            children: [
              for (final (code, label) in InvAdjustController.reasons)
                ChoiceChip(key: Key('invReason_$code'), label: Text(label), selected: c.reason.value == code, onSelected: (_) => c.pickReason(code)),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppTextField(key: const Key('invAdjustNote'), label: c.noteRequired ? 'Note (required)' : 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s)),
        Obx(
          () => c.error.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    c.error.value!,
                    key: const Key('invAdjustError'),
                    style: t.body.copyWith(color: p.danger),
                  ),
                ),
        ),
        const SizedBox(height: Space.s4),
        Obx(() => AppButton(key: const Key('invAdjustConfirm'), label: 'Confirm', loading: c.busy.value, onPressed: c.canSubmit ? _confirm : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
