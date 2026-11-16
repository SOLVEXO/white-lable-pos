import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step2StoreInfoForm extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step2StoreInfoForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: Space.s2),
          Text(
            'Set up your store',
            style: t.headline.copyWith(color: p.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s2),
          Text(
            'You can always update these details later from Settings.',
            style: t.bodySmall.copyWith(color: p.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.s6),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LogoUpload(controller: controller),
                const SizedBox(height: Space.s5),
                AppTextField(
                  label: 'Store Name *',
                  controller: controller.storeNameCtrl,
                  onChanged: (v) => controller.storeName.value = v,
                  hint: 'e.g. Creative Classroom Resources',
                ),
                const SizedBox(height: Space.s4),
                _CurrencyField(controller: controller),
                const SizedBox(height: Space.s4),
                AppTextField(
                  label: 'Store Description (optional)',
                  controller: controller.storeDescCtrl,
                  onChanged: (v) => controller.storeDescription.value = v,
                  hint: 'Tell buyers what makes your store special...',
                  maxLines: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
        ],
      ),
    );
  }
}

class _LogoUpload extends StatelessWidget {
  final SellerOnboardingController controller;
  const _LogoUpload({required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Container(
      padding: const EdgeInsets.all(Space.s3),
      decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rMd),
      child: Row(
        children: [
          Obx(() {
            final file = controller.logoFile.value;
            return Semantics(
              button: true,
              label: 'Upload your store logo',
              child: GestureDetector(
                onTap: controller.pickLogo,
                child: Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: Radii.rMd,
                    border: Border.all(color: p.accent, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: file != null
                      ? Image.file(file, fit: BoxFit.cover, width: 70, height: 70)
                      : Icon(
                          Icons.camera_alt_outlined,
                          size: IconSizes.lg,
                          color: p.accentFg,
                        ),
                ),
              ),
            );
          }),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload your store logo',
                  style: t.label.copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: Space.s1),
                Text(
                  'PNG or JPG, min 200×200px.\nHelps buyers recognise your brand.',
                  style: t.caption.copyWith(color: p.textSecondary),
                ),
                const SizedBox(height: Space.s2),
                Obx(
                  () => AppButton(
                    label: controller.logoFile.value != null
                        ? 'Change Photo'
                        : 'Choose File',
                    variant: AppButtonVariant.secondary,
                    expand: false,
                    onPressed: controller.pickLogo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-pick field: drawn by the theme's input decoration so it matches the
/// [AppTextField]s around it, but opens the currency sheet instead of a keyboard.
class _CurrencyField extends StatelessWidget {
  final SellerOnboardingController controller;
  const _CurrencyField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Obx(() {
          final value = controller.storeCurrency.value;
          return Semantics(
            button: true,
            child: InkWell(
              onTap: controller.pickCurrency,
              borderRadius: Radii.rMd,
              child: InputDecorator(
                isEmpty: value.isEmpty,
                decoration: InputDecoration(
                  labelText: 'Store Currency *',
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  hintText: 'Select the currency for your prices...',
                  suffixIcon: controller.isLoadingCurrencies.value
                      ? Padding(
                          padding: const EdgeInsets.all(Space.s4),
                          child: SizedBox(
                            width: IconSizes.xxs,
                            height: IconSizes.xxs,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: p.accent,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: IconSizes.sm,
                          color: p.textMuted,
                        ),
                ),
                child: Text(
                  value,
                  style: t.body.copyWith(color: p.textPrimary),
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: Space.s2),
        Text(
          "This is the currency for your prices and payouts. It can't be changed after your store is created.",
          style: t.caption.copyWith(color: p.textSecondary),
        ),
      ],
    );
  }
}
