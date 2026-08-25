import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step2StoreInfoForm extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step2StoreInfoForm({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const CustomText(
            text: 'Set up your store',
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: AppFontSize.veryLarge,
            fontWeight: FontWeight.bold,
            color: AppColors.black,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const CustomText(
            text: 'You can always update these details later from Settings.',
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(AppDimen.allPadding),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius + 4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LogoUpload(controller: controller),
                const SizedBox(height: 20),
                _FieldLabel(label: 'Store Name', required: true),
                const SizedBox(height: 6),
                CustomTextField(
                  controller: controller.storeNameCtrl,
                  onChanged: (v) => controller.storeName.value = v,
                  hintText: 'e.g. Creative Classroom Resources',
                  isborder: true,
                  fillColor: AppColors.textfldFillColor,
                ),
                const SizedBox(height: 16),
                _CategoryField(controller: controller),
                const SizedBox(height: 16),
                _CurrencyField(controller: controller),
                const SizedBox(height: 16),
                const _FieldLabel(label: 'Store Description', optional: true),
                const SizedBox(height: 6),
                CustomTextField(
                  controller: controller.storeDescCtrl,
                  onChanged: (v) => controller.storeDescription.value = v,
                  hintText: 'Tell buyers what makes your store special...',
                  isborder: true,
                  fillColor: AppColors.textfldFillColor,
                  maxLines: 4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
      ),
      child: Row(children: [
        Obx(() {
          final hasFile = controller.logoFile.value != null;
          return GestureDetector(
            onTap: controller.pickLogo,
            child: Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
                border: Border.all(
                  color: AppColors.primaryColor.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: hasFile
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
                      child: CommonImageView(
                        file: controller.logoFile.value,
                        fit: BoxFit.cover,
                        width: 70,
                        height: 70,
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_outlined,
                      size: 28,
                      color: AppColors.primaryColor,
                    ),
            ),
          );
        }),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CustomText(
              text: 'Upload your store logo',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
            const SizedBox(height: 4),
            const CustomText(
              text: 'PNG or JPG, min 200×200px.\nHelps buyers recognise your brand.',
              fontSize: AppFontSize.tiny,
              color: AppColors.grey,
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: controller.pickLogo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Obx(() => CustomText(
                  text: controller.logoFile.value != null ? 'Change Photo' : 'Choose File',
                  fontSize: AppFontSize.tiny,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryColor,
                )),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _CategoryField extends StatelessWidget {
  final SellerOnboardingController controller;
  const _CategoryField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Store Category'),
        const SizedBox(height: 6),
        Obx(
          () => GestureDetector(
            onTap: controller.pickCategory,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.textfldFillColor,
                borderRadius: BorderRadius.circular(AppDimen.borderRadius),
                border: Border.all(color: AppColors.lightGrey, width: 0.3),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CustomText(
                      text: controller.storeCategory.value.isEmpty
                          ? 'Select your main category...'
                          : controller.storeCategory.value,
                      fontSize: AppFontSize.verySmall,
                      color: controller.storeCategory.value.isEmpty
                          ? AppColors.grey
                          : AppColors.black,
                    ),
                  ),
                  controller.isLoadingCategories.value
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryColor),
                        )
                      : const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.grey),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrencyField extends StatelessWidget {
  final SellerOnboardingController controller;
  const _CurrencyField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel(label: 'Store Currency', required: true),
        const SizedBox(height: 6),
        Obx(
          () => GestureDetector(
            onTap: controller.pickCurrency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.textfldFillColor,
                borderRadius: BorderRadius.circular(AppDimen.borderRadius),
                border: Border.all(color: AppColors.lightGrey, width: 0.3),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: CustomText(
                      text: controller.storeCurrency.value.isEmpty
                          ? 'Select the currency for your prices...'
                          : controller.storeCurrency.value,
                      fontSize: AppFontSize.verySmall,
                      color: controller.storeCurrency.value.isEmpty
                          ? AppColors.grey
                          : AppColors.black,
                    ),
                  ),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.grey),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const CustomText(
          text: "This is the currency for your prices and payouts. It can't be changed after your store is created.",
          fontSize: AppFontSize.tiny,
          color: AppColors.grey,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  final bool optional;

  const _FieldLabel({
    required this.label,
    this.required = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CustomText(
          text: label,
          fontSize: AppFontSize.verySmall,
          fontWeight: FontWeight.w600,
          color: AppColors.black2,
        ),
        if (required)
          const CustomText(text: ' *', fontSize: AppFontSize.verySmall, fontWeight: FontWeight.w600, color: AppColors.red),
        if (optional)
          const CustomText(text: ' (optional)', fontSize: AppFontSize.tiny, color: AppColors.grey),
      ],
    );
  }
}
