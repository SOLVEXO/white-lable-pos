import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/controllers/seller_pos_locations_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Bottom-sheet form for adding a branch or editing an existing one
/// (pass [existing] to pre-fill for editing).
class LocationFormSheet extends StatefulWidget {
  final SellerPosLocationsController controller;
  final StoreLocationModel? existing;
  const LocationFormSheet({super.key, required this.controller, this.existing});

  static void show(BuildContext context, SellerPosLocationsController controller,
      {StoreLocationModel? existing}) {
    AppBottomSheet.showGet(
      LocationFormSheet(controller: controller, existing: existing),
      title: existing != null ? 'Edit Location' : 'Add Location',
    );
  }

  @override
  State<LocationFormSheet> createState() => _LocationFormSheetState();
}

class _LocationFormSheetState extends State<LocationFormSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _phoneCtrl;
  late bool _active;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _addressCtrl = TextEditingController(text: e?.addressLine1 ?? '');
    _cityCtrl = TextEditingController(text: e?.city ?? '');
    _phoneCtrl = TextEditingController(text: e?.phone ?? '');
    _active = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final address = _addressCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    bool ok;
    if (_isEdit) {
      ok = await widget.controller.updateLocation(
        widget.existing!,
        name: name,
        addressLine1: address,
        city: city,
        phone: phone,
        status: _active ? 'active' : 'archived',
      );
    } else {
      ok = await widget.controller.createLocation(
        name: name,
        addressLine1: address.isEmpty ? null : address,
        city: city.isEmpty ? null : city,
        phone: phone.isEmpty ? null : phone,
      );
    }
    if (ok && mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          label: 'Branch Name',
          hint: 'e.g. Downtown Branch',
          controller: _nameCtrl,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          label: 'Address (optional)',
          hint: 'Street address',
          controller: _addressCtrl,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          label: 'City (optional)',
          controller: _cityCtrl,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: Space.s3),
        AppTextField(
          label: 'Phone (optional)',
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
        ),
        if (_isEdit) ...[
          const SizedBox(height: Space.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Active', style: context.type.subtitle.copyWith(color: p.textPrimary)),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
        ],
        const SizedBox(height: Space.s5),
        Obx(
          () => AppButton(
            label: _isEdit ? 'Save Changes' : 'Add Location',
            loading: widget.controller.isSaving.value,
            onPressed: widget.controller.isSaving.value ? null : _submit,
          ),
        ),
      ],
    );
  }
}
