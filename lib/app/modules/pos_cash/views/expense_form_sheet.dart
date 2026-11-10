import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/components/app_image_picker.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_common.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/cash_movement_controller.dart';
import 'package:solvexo_pos/app/modules/pos_cash/controllers/expense_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Add an expense: category, amount, payee, how it was paid, a note ("other" needs one) and an optional receipt photo. Cash from the drawer works offline
/// (saved on this device, sent later); bank / other need internet. Closes with the [CashOutcome].
class ExpenseFormSheet extends StatefulWidget {
  const ExpenseFormSheet({super.key, required this.controller, this.pickPhoto});
  final ExpenseFormController controller;

  /// how a photo is chosen (camera / library); null uses the app's own picker
  final void Function(ValueChanged<File> onPicked)? pickPhoto;

  static Future<CashOutcome?> open({ExpenseFormController? controller}) =>
      AppBottomSheet.showGet<CashOutcome>(ExpenseFormSheet(controller: controller ?? ExpenseFormController()), title: 'Add expense');

  @override
  State<ExpenseFormSheet> createState() => _ExpenseFormSheetState();
}

class _ExpenseFormSheetState extends State<ExpenseFormSheet> {
  final _amount = TextEditingController();
  final _payee = TextEditingController();
  final _note = TextEditingController();
  ExpenseFormController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.start();
  }

  @override
  void dispose() {
    _amount.dispose();
    _payee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (await c.submit() && mounted) Get.back<CashOutcome>(result: c.outcome.value);
  }

  void _choosePhoto() {
    final pick = widget.pickPhoto;
    if (pick != null) {
      pick(c.setPhoto);
    } else {
      AppImagePicker.show(onPicked: c.setPhoto, title: 'Receipt photo', canRemove: c.photo.value != null, onRemove: () => c.setPhoto(null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Category', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            runSpacing: Space.s1,
            children: [
              for (final cat in c.config.value.expenseCategories)
                ChoiceChip(key: Key('exCat_$cat'), label: Text(cashCategoryLabel(cat)), selected: c.category.value == cat, onSelected: (_) => c.pickCategory(cat)),
            ],
          ),
        ),
        const SizedBox(height: Space.s3),
        Obx(
          () => AppTextField(
            key: const Key('exAmount'),
            label: c.cur == null ? 'Amount' : 'Amount (${c.cur!.code})',
            controller: _amount,
            mono: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (s) => c.amountText.value = s,
          ),
        ),
        const SizedBox(height: Space.s3),
        AppTextField(key: const Key('exPayee'), label: 'Paid to (optional)', controller: _payee, onChanged: (s) => c.payee.value = s),
        const SizedBox(height: Space.s3),
        Text('Paid by', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            children: [
              for (final m in c.config.value.expenseMethods)
                ChoiceChip(
                  key: Key('exMethod_$m'),
                  label: Text(expenseMethodLabel(m)),
                  selected: c.method.value == m,
                  onSelected: c.methodAllowed(m) && (m != 'cash' || c.hasOpenShift) ? (_) => c.pickMethod(m) : null,
                ),
            ],
          ),
        ),
        Obx(
          () => c.hasOpenShift || c.loadingConfig.value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s2),
                  child: Text(
                    'Open a shift to pay from the drawer.',
                    key: const Key('exNoShift'),
                    style: t.caption.copyWith(color: p.warningFg),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppTextField(key: const Key('exNote'), label: c.noteRequired ? 'Note (required)' : 'Note (optional)', controller: _note, onChanged: (s) => c.note.value = s)),
        const SizedBox(height: Space.s3),
        Obx(() {
          final f = c.photo.value;
          return Row(
            children: [
              if (f != null)
                ClipRRect(
                  borderRadius: Radii.rMd,
                  child: Image.file(
                    f,
                    key: const Key('exPhotoThumb'),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: p.fill,
                      child: Icon(Icons.image_outlined, color: p.textMuted),
                    ),
                  ),
                ),
              if (f != null) const SizedBox(width: Space.s3),
              Expanded(
                child: AppButton(
                  key: const Key('exPhoto'),
                  label: f == null ? 'Add receipt photo' : 'Change photo',
                  variant: AppButtonVariant.secondary,
                  icon: Icons.photo_camera_outlined,
                  onPressed: _choosePhoto,
                ),
              ),
              if (f != null) IconButton(key: const Key('exPhotoRemove'), tooltip: 'Remove photo', icon: const Icon(Icons.close_rounded), onPressed: () => c.setPhoto(null)),
            ],
          );
        }),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('exError'))),
        Obx(
          () => cashOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Offline. An expense paid from the drawer is saved on this device and sent when the till is online. Bank and other need internet.',
                    key: const Key('exOffline'),
                    style: t.caption.copyWith(color: p.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('exConfirm'), label: cashOnlineRx().value ? 'Save expense' : 'Save on this device', loading: c.busy.value, onPressed: c.canSubmit ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
