import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/data/models/pos/store_location_model.dart';
import 'package:solvexo_pos/app/modules/seller_pos_locations/controllers/seller_pos_locations_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
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
    Get.bottomSheet(
      LocationFormSheet(controller: controller, existing: existing),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(BaseSpacing.lg, BaseSpacing.sm, BaseSpacing.lg, BaseSpacing.lg),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: EdgeInsets.only(bottom: BaseSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.lightGrey2,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  CustomText(
                    text: _isEdit ? 'Edit Location' : 'Add Location',
                    color: AppColors.black2,
                    fontSize: AppFontSize.small2,
                    fontWeight: FontWeight.bold,
                  ),
                  SizedBox(height: BaseSpacing.md),
                  CustomTextField(
                    label: 'Branch Name',
                    hintText: 'e.g. Downtown Branch',
                    controller: _nameCtrl,
                    isborder: true,
                  ),
                  SizedBox(height: BaseSpacing.sm),
                  CustomTextField(
                    label: 'Address (optional)',
                    hintText: 'Street address',
                    controller: _addressCtrl,
                    isborder: true,
                  ),
                  SizedBox(height: BaseSpacing.sm),
                  CustomTextField(
                    label: 'City (optional)',
                    controller: _cityCtrl,
                    isborder: true,
                  ),
                  SizedBox(height: BaseSpacing.sm),
                  CustomTextField(
                    label: 'Phone (optional)',
                    controller: _phoneCtrl,
                    isborder: true,
                    keyboardType: TextInputType.phone,
                  ),
                  if (_isEdit) ...[
                    SizedBox(height: BaseSpacing.sm),
                    Row(
                      children: [
                        const Expanded(
                          child: CustomText(
                            text: 'Active',
                            color: AppColors.black2,
                            fontSize: AppFontSize.verySmall,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Switch(
                          value: _active,
                          activeColor: AppColors.primaryColor,
                          onChanged: (v) => setState(() => _active = v),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: BaseSpacing.lg),
                  Obx(
                    () => GestureDetector(
                      onTap: widget.controller.isSaving.value ? null : _submit,
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 50),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor,
                          borderRadius: BorderRadius.circular(BaseRadius.md),
                        ),
                        child: widget.controller.isSaving.value
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                              )
                            : CustomText(
                                text: _isEdit ? 'Save Changes' : 'Add Location',
                                color: AppColors.white,
                                fontSize: AppFontSize.small,
                                fontWeight: FontWeight.w700,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
