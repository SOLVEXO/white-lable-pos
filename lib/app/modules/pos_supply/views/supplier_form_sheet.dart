import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supplier_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_supply/controllers/supply_common.dart';
import 'package:solvexo_pos/app/modules/pos_supply/views/supply_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Add or edit a supplier. Only the name is needed. Closes with the saved [Supplier].
class SupplierFormSheet extends StatefulWidget {
  const SupplierFormSheet({super.key, this.controller, this.existing});
  final SupplierFormController? controller;
  final Supplier? existing;

  static Future<Supplier?> open({Supplier? existing}) => AppBottomSheet.showGet<Supplier>(SupplierFormSheet(existing: existing), title: existing == null ? 'Add supplier' : 'Edit supplier');

  @override
  State<SupplierFormSheet> createState() => _SupplierFormSheetState();
}

class _SupplierFormSheetState extends State<SupplierFormSheet> {
  late final SupplierFormController c = widget.controller ?? SupplierFormController(existing: widget.existing);
  late final _name = TextEditingController(text: c.name.value);
  late final _contact = TextEditingController(text: c.contactName.value);
  late final _phone = TextEditingController(text: c.phone.value);
  late final _email = TextEditingController(text: c.email.value);
  late final _address = TextEditingController(text: c.address.value);
  late final _ntn = TextEditingController(text: c.ntn.value);
  late final _strn = TextEditingController(text: c.strn.value);
  late final _terms = TextEditingController(text: c.paymentTerms.value);
  late final _lead = TextEditingController(text: c.leadTimeDays.value);
  late final _notes = TextEditingController(text: c.notes.value);

  @override
  void dispose() {
    for (final t in [_name, _contact, _phone, _email, _address, _ntn, _strn, _terms, _lead, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await c.submit();
    if (saved != null && mounted) Get.back<Supplier>(result: saved);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.s3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(key: const Key('sfName'), label: 'Name', controller: _name, onChanged: (s) => c.name.value = s),
        gap,
        AppTextField(key: const Key('sfContact'), label: 'Contact person (optional)', controller: _contact, onChanged: (s) => c.contactName.value = s),
        gap,
        AppTextField(key: const Key('sfPhone'), label: 'Phone (optional)', controller: _phone, keyboardType: TextInputType.phone, onChanged: (s) => c.phone.value = s),
        gap,
        AppTextField(key: const Key('sfEmail'), label: 'E-mail (optional)', controller: _email, keyboardType: TextInputType.emailAddress, onChanged: (s) => c.email.value = s),
        gap,
        AppTextField(key: const Key('sfAddress'), label: 'Address (optional)', controller: _address, onChanged: (s) => c.address.value = s),
        gap,
        AppTextField(key: const Key('sfNtn'), label: 'NTN (optional)', controller: _ntn, mono: true, onChanged: (s) => c.ntn.value = s),
        gap,
        AppTextField(key: const Key('sfStrn'), label: 'STRN (optional)', controller: _strn, mono: true, onChanged: (s) => c.strn.value = s),
        gap,
        AppTextField(key: const Key('sfTerms'), label: 'Payment terms (optional)', controller: _terms, onChanged: (s) => c.paymentTerms.value = s),
        gap,
        AppTextField(
          key: const Key('sfLead'),
          label: 'Lead time in days (optional)',
          controller: _lead,
          mono: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (s) => c.leadTimeDays.value = s,
        ),
        gap,
        AppTextField(key: const Key('sfNotes'), label: 'Notes (optional)', controller: _notes, maxLines: 3, onChanged: (s) => c.notes.value = s),
        Obx(() => SupplyErrorText(c.error.value, errorKey: const Key('sfError'))),
        Obx(
          () => supplyOnlineRx().value
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: Space.s3),
                  child: Text(
                    'Needs internet. A supplier can only be saved while the till is online.',
                    key: const Key('sfOffline'),
                    style: context.type.caption.copyWith(color: context.palette.textSecondary),
                  ),
                ),
        ),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('sfSave'), label: c.isEdit ? 'Save changes' : 'Save supplier', loading: c.busy.value, onPressed: (c.canSubmit && supplyOnlineRx().value) ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
