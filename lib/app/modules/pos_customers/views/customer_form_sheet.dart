import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_form_controller.dart';
import 'package:solvexo_pos/app/modules/pos_customers/views/customer_widgets.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Add a customer (or edit one). Only the name is needed; every other field is optional. Closes with the saved [PosCustomer]
/// (its `existing` flag says the phone number already belonged to that customer).
class CustomerFormSheet extends StatefulWidget {
  const CustomerFormSheet({super.key, this.controller, this.existing});
  final CustomerFormController? controller;
  final PosCustomer? existing;

  static Future<PosCustomer?> open({PosCustomer? existing}) => AppBottomSheet.showGet<PosCustomer>(CustomerFormSheet(existing: existing), title: existing == null ? 'Add customer' : 'Edit customer');

  @override
  State<CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends State<CustomerFormSheet> {
  late final CustomerFormController c = widget.controller ?? CustomerFormController(existing: widget.existing);
  late final _name = TextEditingController(text: c.name.value);
  late final _phone = TextEditingController(text: c.phone.value);
  late final _email = TextEditingController(text: c.email.value);
  late final _address = TextEditingController(text: c.address.value);
  late final _ntn = TextEditingController(text: c.ntn.value);
  late final _cnic = TextEditingController(text: c.cnic.value);
  late final _group = TextEditingController(text: c.group.value);
  late final _notes = TextEditingController(text: c.notes.value);

  @override
  void dispose() {
    for (final t in [_name, _phone, _email, _address, _ntn, _cnic, _group, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await c.submit();
    if (saved != null && mounted) Get.back<PosCustomer>(result: saved);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    Widget gap() => const SizedBox(height: Space.s3);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Obx(() => AppTextField(key: const Key('cfName'), label: 'Name', controller: _name, prefixIcon: Icons.person_outline_rounded, errorText: c.fieldErrors['name'], onChanged: (s) => c.name.value = s)),
        gap(),
        Obx(() => AppTextField(key: const Key('cfPhone'), label: 'Phone (optional)', controller: _phone, prefixIcon: Icons.phone_outlined, keyboardType: TextInputType.phone, errorText: c.fieldErrors['phone'], onChanged: (s) => c.phone.value = s)),
        gap(),
        Obx(() => AppTextField(key: const Key('cfEmail'), label: 'E-mail (optional)', controller: _email, prefixIcon: Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress, errorText: c.fieldErrors['email'], onChanged: (s) => c.email.value = s)),
        gap(),
        AppTextField(key: const Key('cfAddress'), label: 'Address (optional)', controller: _address, prefixIcon: Icons.home_outlined, onChanged: (s) => c.address.value = s),
        gap(),
        Obx(() => AppTextField(key: const Key('cfNtn'), label: 'NTN (optional)', controller: _ntn, mono: true, errorText: c.fieldErrors['ntn'], onChanged: (s) => c.ntn.value = s)),
        gap(),
        Obx(() => AppTextField(key: const Key('cfCnic'), label: 'CNIC (optional)', controller: _cnic, mono: true, errorText: c.fieldErrors['cnic'], onChanged: (s) => c.cnic.value = s)),
        gap(),
        Text('Registration (optional)', style: t.caption.copyWith(color: p.textSecondary)),
        const SizedBox(height: Space.s1),
        Obx(
          () => Wrap(
            spacing: Space.s2,
            children: [
              for (final (id, label) in const [('registered', 'Registered'), ('unregistered', 'Unregistered')])
                ChoiceChip(key: Key('cfReg_$id'), label: Text(label), selected: c.registrationType.value == id, onSelected: (_) => c.setRegistrationType(id)),
            ],
          ),
        ),
        Obx(() => c.fieldErrors['registrationType'] == null ? const SizedBox.shrink() : Text(c.fieldErrors['registrationType']!, style: t.caption.copyWith(color: p.dangerFg))),
        gap(),
        AppTextField(key: const Key('cfGroup'), label: 'Group (optional)', controller: _group, prefixIcon: Icons.label_outline_rounded, onChanged: (s) => c.group.value = s),
        gap(),
        AppTextField(key: const Key('cfNotes'), label: 'Notes (optional)', controller: _notes, maxLines: 3, onChanged: (s) => c.notes.value = s),
        const SizedBox(height: Space.s2),
        Obx(
          () => SwitchListTile(
            key: const Key('cfConsent'),
            contentPadding: EdgeInsets.zero,
            value: c.marketingConsent.value,
            onChanged: (v) => c.marketingConsent.value = v,
            title: Text('OK to send offers', style: t.body.copyWith(color: p.textPrimary)),
            subtitle: Text('The customer agreed to marketing messages.', style: t.caption.copyWith(color: p.textMuted)),
          ),
        ),
        Obx(
          () => c.error.value == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: Space.s2),
                  child: Text(c.error.value!, key: const Key('cfError'), style: t.body.copyWith(color: p.dangerFg)),
                ),
        ),
        Obx(() => customersOnlineRx().value ? const SizedBox.shrink() : const CustomerNote(noteKey: Key('cfOffline'), icon: Icons.cloud_off_rounded, text: 'Needs internet. A customer can only be saved while the till is online.')),
        const SizedBox(height: Space.s3),
        Obx(() => AppButton(key: const Key('cfSave'), label: c.isEdit ? 'Save changes' : 'Save customer', loading: c.busy.value, onPressed: (c.canSubmit && customersOnlineRx().value) ? _save : null)),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}
