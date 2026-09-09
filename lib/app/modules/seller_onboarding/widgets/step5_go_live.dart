import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step5GoLive extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step5GoLive({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final marketplaceName = Get.find<BrandingService>().config.value.marketplaceName;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      child: Column(
        children: [
          const SizedBox(height: 8),
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
              children: [
                const SizedBox(height: 12),
                const CustomText(text: '🎉', fontSize: 52),
                const SizedBox(height: 16),
                const CustomText(
                  text: 'Your store setup is ready!',
                  fontSize: AppFontSize.veryLarge,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                CustomText(
                  text: 'Welcome to $marketplaceName. One more step: verify your business details so our team can approve your store — you can only publish products on $marketplaceName once it\'s approved.',
                  fontSize: AppFontSize.verySmall,
                  color: AppColors.grey,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _SetupSummary(controller: controller),
                const SizedBox(height: 24),
                const _SectionTitle(title: 'What happens next'),
                const SizedBox(height: 14),
                const _NextStepsTimeline(),
                const SizedBox(height: 20),
                _UpgradeNote(),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Setup summary card ────────────────────────────────────────────────────────

class _SetupSummary extends StatelessWidget {
  final SellerOnboardingController controller;
  const _SetupSummary({required this.controller});

  @override
  Widget build(BuildContext context) {
    final appName = Get.find<BrandingService>().config.value.appName;
    return Obx(
      () => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppDimen.serviceCountTileRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomText(
              text: 'Your $appName Setup',
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.bold,
              color: AppColors.black,
            ),
            const SizedBox(height: 12),
            _SummaryRow(
              emoji: '🏪',
              label: 'Store',
              value: controller.storeName.value.isEmpty
                  ? 'My $appName Store'
                  : controller.storeName.value,
            ),
            _SummaryRow(
              emoji: '👤',
              label: 'Seller type',
              value: controller.sellerTypeName.isEmpty
                  ? 'Not selected'
                  : controller.sellerTypeName,
            ),
            const _SummaryRow(
              emoji: '📦',
              label: 'Products',
              value: 'Physical Products',
            ),
            _SummaryRow(emoji: '💳', label: 'Plan', value: 'Starter — Free'),
            const _SummaryRow(emoji: '✨', label: 'AI Credits', value: '100 free credits included'),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;

  const _SummaryRow({
    required this.emoji,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: CustomText(text: emoji, fontSize: 14),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: CustomText(
              text: label,
              fontSize: AppFontSize.tiny,
              color: AppColors.grey,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: CustomText(
              text: value,
              fontSize: AppFontSize.tiny,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Next steps ────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: CustomText(
        text: title,
        fontFamily: AppTextStyles.headingFontFamily,
        fontSize: AppFontSize.verySmall,
        fontWeight: FontWeight.bold,
        color: AppColors.black,
      ),
    );
  }
}

// Mirrors the real backend sequence (StoreService.createStore → status
// 'pending'; StoreService.submitVerification; AdminMarketplaceService.
// approveLead → status 'active', the only state ProductsService lets a
// seller create products in) — purely informational, since tapping the
// primary button below creates the store and drops the seller straight
// into the verification form automatically.
class _NextStepsTimeline extends StatelessWidget {
  const _NextStepsTimeline();

  @override
  Widget build(BuildContext context) {
    final marketplaceName = Get.find<BrandingService>().config.value.marketplaceName;
    return Column(
      children: [
        const _TimelineStep(
          emoji: '📋',
          title: 'Verify your business',
          subtitle: 'Submit a few business details & documents — required next.',
        ),
        const _TimelineConnector(),
        const _TimelineStep(
          emoji: '✅',
          title: 'Get approved',
          subtitle: 'Our team reviews it — usually within 1–2 business days.',
        ),
        const _TimelineConnector(),
        _TimelineStep(
          emoji: '🛍️',
          title: 'Start selling',
          subtitle: 'Once approved, add products and go live on $marketplaceName.',
          isLast: true,
        ),
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool isLast;

  const _TimelineStep({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.lightGrey2),
          ),
          alignment: Alignment.center,
          child: CustomText(text: emoji, fontSize: 15),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 2, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  text: title,
                  fontSize: AppFontSize.verySmall,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black2,
                ),
                const SizedBox(height: 2),
                CustomText(
                  text: subtitle,
                  fontSize: AppFontSize.tiny,
                  color: AppColors.grey,
                  height: 1.35,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimelineConnector extends StatelessWidget {
  const _TimelineConnector();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.5),
      child: Container(width: 1.5, height: 18, color: AppColors.lightGrey2),
    );
  }
}

// ── Upgrade note ──────────────────────────────────────────────────────────────
// Plan upgrades are managed on Seller Web, not in this app — static text only.

class _UpgradeNote extends StatelessWidget {
  const _UpgradeNote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "You're on the free Starter plan. Upgrade anytime to unlock unlimited "
      'products, AI Studio, POS, and custom domain.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 11, color: AppColors.grey),
    );
  }
}
