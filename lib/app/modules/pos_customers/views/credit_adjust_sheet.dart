import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/credit_adjust_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Managers only: add or remove store credit by hand, with a required note. The server decides; above the manager's limit it asks for
/// the owner, and this says so in plain words.
class CreditAdjustSheet extends StatefulWidget {
  const CreditAdjustSheet({super.key, required this.controller, required this.currencyCode});
  final CreditAdjustController controller;
  final String currencyCode;

  static Future<bool?> open({required String customerId, required int exponent, required String currencyCode, CreditAdjustController? controller}) => AppBottomSheet.showGet<bool>(
    CreditAdjustSheet(
      controller: controller ?? CreditAdjustController(customerId: customerId, exponent: exponent),
      currencyCode: currencyCode,
    ),
    title: 'Adjust store credit',
  );

  @override
  State<CreditAdjustSheet> createState() => _CreditAdjustSheetState();
}

class _CreditAdjustSheetState extends State<CreditAdjustSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  CreditAdjustController get c => widget.controller;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await c.submit() && mounted) Get.back<bool>(result: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(
          () => Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  key: const Key('caAdd'),
                  label: const Center(child: Text('Add credit')),
                  selected: c.adding.value,
                  onSelected: (_) => c.adding.value = true,
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: ChoiceChip(
                  key: const Key('caRemove'),
                  label: const Center(child: Text('Remove credit')),
                  selected: !c.adding.value,
                  onSelected: (_) => c.adding.value = false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          key: const Key('caAmount'),
          label: 'Amount (${widget.currencyCode})',
          controller: _amount,
          mono: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: (s) => c.amountText.value = s,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('caNote'), label: 'Note (required)', controller: _note, maxLines: 2, onChanged: (s) => c.note.value = s),
        Obx(
          () => c.error.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    c.error.value!,
                    key: const Key('caError'),
                    style: t.body.copyWith(color: p.dangerFg),
                  ),
                ),
        ),
        const SizedBox(height: Space.s4),
        Obx(() => AppButton(key: const Key('caConfirm'), label: 'Confirm', loading: c.busy.value, onPressed: c.canSubmit ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
