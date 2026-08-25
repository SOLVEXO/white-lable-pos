import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/onboarding_bottom_bar.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/onboarding_step_bar.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/step2_store_info_form.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/step3_seller_type_grid.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/step4_what_you_sell_grid.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/widgets/step5_go_live.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_images.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SellerOnboardingView extends StatelessWidget {
  SellerOnboardingView({super.key});

  final SellerOnboardingController controller = Get.put(
    SellerOnboardingController(),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _TopHeader(context: context, controller: controller),
          OnboardingStepBar(controller: controller),
          const Divider(height: 1, color: AppColors.lightGrey2),
          Expanded(
            child: Obx(() {
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(parent: anim, curve: Curves.easeOut),
                        ),
                    child: child,
                  ),
                ),
                child: _stepContent(controller.step.value),
              );
            }),
          ),
        ],
      ),
      bottomNavigationBar: OnboardingBottomBar(controller: controller),
    );
  }

  Widget _stepContent(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.storeInfo:
        return Step2StoreInfoForm(
          key: const ValueKey('s1'),
          controller: controller,
        );
      case OnboardingStep.sellerType:
        return Step3SellerTypeGrid(
          key: const ValueKey('s2'),
          controller: controller,
        );
      case OnboardingStep.whatYouSell:
        return Step4WhatYouSellGrid(
          key: const ValueKey('s3'),
          controller: controller,
        );
      case OnboardingStep.goLive:
        return Step5GoLive(key: const ValueKey('s4'), controller: controller);
    }
  }
}

// ── Top header (logo + sign-in link) ─────────────────────────────────────────

class _TopHeader extends StatelessWidget {
  final BuildContext context;
  final SellerOnboardingController controller;

  const _TopHeader({required this.context, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: AppDimen.allPadding,
        right: AppDimen.allPadding,
        bottom: 10,
      ),
      child: Row(
        children: [
          SvgIcon(assetName: AppImages.logoImage, size: 40),
          const SizedBox(width: 5),
          CustomText(
            text: Get.find<BrandingService>().config.value.appName.toUpperCase(),
            fontFamily: AppTextStyles.headingFontFamily,
            fontSize: AppFontSize.medium,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryColor,
          ),
          const Spacer(),
          const CustomText(
            text: 'Set up your store',
            fontSize: AppFontSize.tiny,
            color: AppColors.grey,
          ),
        ],
      ),
    );
  }
}
