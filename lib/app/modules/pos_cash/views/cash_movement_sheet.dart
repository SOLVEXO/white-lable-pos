import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/views/cash_widgets.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Cash in / cash out on the open shift: a reason (category chips), the amount, a note (required for "other"). Works offline: it is saved on this device
/// and sent when the till is online. Closes with the [CashOutcome] (booked now, or queued).
class CashMovementSheet extends StatefulWidget {
  const CashMovementSheet({super.key, required this.controller});
  final CashMovementController controller;

  static Future<CashOutcome?> open({String type = 'cash_in', CashMovementController? controller}) => AppBottomSheet.showGet<CashOutcome>(
    CashMovementSheet(controller: controller ?? CashMovementController(initialType: type)),
    title: 'Cash in / out',
  );

  @override
  State<CashMovementSheet> createState() => _CashMovementSheetState();
}

class _CashMovementSheetState extends State<CashMovementSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  CashMovementController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await c.submit() && mounted) Get.back<CashOutcome>(result: c.outcome.value);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.queue != null)
          Obx(() {
            final n = c.hasOpenShift ? c.queue!.waitingForSession(c.sessionId.value!).length : 0;
            return n == 0
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: Space.s3),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: WaitingToSyncBadge(count: n),
                    ),
                  );
          }),
        Obx(
          () => Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  key: const Key('cmIn'),
                  label: const Center(child: Text('Cash in')),
                  selected: c.isIn,
                  onSelected: (_) => c.setType('cash_in'),
                ),
              ),
              const SizedBox(width: Space.s2),
              Expanded(
                child: ChoiceChip(
                  key: const Key('cmOut'),
                  label: const Center(child: Text('Cash out')),
                  selected: !c.isIn,
                  onSelected: (_) => c.setType('cash_out'),
                ),
              ),
            ],
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
              for (final cat in c.categories) ChoiceChip(key: Key('cmCat_$cat'), label: Text(cashCategoryLabel(cat)), selected: c.category.value == cat, onSelected: (_) => c.pickCategory(cat)),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        Obx(
          () => AppTextField(
            key: const Key('cmAmount'),
            label: c.cur == null ? 'Amount' : 'Amount (${c.cur!.code})',
            controller: _amount,
            mono: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (s) => c.amountText.value = s,
          ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppTextField(key: const Key('cmNote'), label: c.noteRequired ? 'Note (required)' : 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s)),
        Obx(
          () => c.hasOpenShift || c.loadingConfig.value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Open a shift to record cash in or out.',
                    key: const Key('cmNoShift'),
                    style: t.caption.copyWith(color: p.warningFg),
                  ),
                ),
        ),
        Obx(
          () => !c.loadingConfig.value && c.cur == null
              ? Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Connect once so the till can learn the store currency.',
                    key: const Key('cmNoCurrency'),
                    style: t.caption.copyWith(color: p.warningFg),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('cmError'))),
        Obx(
          () => cashOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Offline. This will be saved on this device and sent when the till is online.',
                    key: const Key('cmOffline'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('cmConfirm'), label: cashOnlineRx().value ? 'Record' : 'Save on this device', loading: c.busy.value, onPressed: c.canSubmit ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
