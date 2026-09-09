import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_plan_model.dart';
import 'package:solvexo_pos/app/modules/pos_subscription_paywall/controllers/pos_subscription_paywall_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class PosSubscriptionPaywallView extends StatelessWidget {
  PosSubscriptionPaywallView({super.key});

  final PosSubscriptionPaywallController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBarTwo(
        title: 'Choose a Plan',
        color: AppColors.black2,
        backgroundColor: AppColors.white,
      ),
      body: Obx(() {
        switch (c.uiState.value) {
          case PosSubscriptionPaywallUiState.loading:
            return const Center(child: CircularProgressIndicator());
          case PosSubscriptionPaywallUiState.error:
            return _ErrorState(
              message: c.errorMessage.value,
              onRetry: c.retryLoad,
            );
          case PosSubscriptionPaywallUiState.empty:
            return const _EmptyState();
          case PosSubscriptionPaywallUiState.ready:
          case PosSubscriptionPaywallUiState.processing:
            return _PlanListState(
              controller: c,
              isProcessing: c.uiState.value == PosSubscriptionPaywallUiState.processing,
            );
        }
      }),
    );
  }
}

class _PlanListState extends StatelessWidget {
  const _PlanListState({required this.controller, required this.isProcessing});

  final PosSubscriptionPaywallController controller;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppDimen.allPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: controller.isExpired ? AppColors.lightRed : AppColors.white,
              borderRadius: BorderRadius.circular(AppDimen.borderRadius),
              border: Border.all(
                color: controller.isExpired ? AppColors.posStatusRed : AppColors.lightGrey2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  controller.isExpired ? Icons.error_outline : Icons.lock_outline,
                  color: controller.isExpired ? AppColors.posStatusRed : AppColors.accentColor,
                  size: 32,
                ),
                const SizedBox(height: 12),
                CustomText(
                  text: controller.isExpired
                      ? 'Your plan expired${controller.expiresAt != null ? ' on ${_formatDate(controller.expiresAt!)}' : ''} — choose a plan to continue'
                      : 'Unlock POS for "${controller.storeName}"',
                  fontSize: AppFontSize.medium,
                  fontWeight: FontWeight.w700,
                  color: AppColors.black2,
                ),
                const SizedBox(height: 8),
                CustomText(
                  text: 'This store needs a POS plan before its terminal can be used.',
                  fontSize: AppFontSize.small,
                  color: AppColors.grey,
                  height: 1.4,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Obx(
            () => Column(
              children: controller.plans
                  .map(
                    (plan) => _PlanCard(
                      plan: plan,
                      selected: controller.selectedPlan.value?.id == plan.id,
                      onTap: () => controller.selectPlan(plan),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (controller.errorMessage.value.isNotEmpty) ...[
            const SizedBox(height: 12),
            CustomText(
              text: controller.errorMessage.value,
              fontSize: AppFontSize.small,
              color: AppColors.error,
            ),
          ],
          const SizedBox(height: 12),
          Obx(
            () => AppButton(
              label: isProcessing ? 'Please wait…' : 'Pay Now',
              onPressed: (isProcessing || controller.selectedPlan.value == null) ? null : controller.confirm,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    final date = DateTime.tryParse(iso);
    if (date == null) return iso;
    return '${date.month}/${date.day}/${date.year}';
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.selected, required this.onTap});

  final PosPlanModel plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            border: Border.all(
              color: selected ? AppColors.accentColor : AppColors.lightGrey2,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      text: plan.name,
                      fontSize: AppFontSize.small2,
                      fontWeight: FontWeight.w700,
                      color: AppColors.black2,
                    ),
                    const SizedBox(height: 4),
                    CustomText(
                      text: '${plan.durationInDays} days — ${plan.currency} ${plan.price}',
                      fontSize: AppFontSize.small,
                      color: AppColors.grey,
                    ),
                    if (plan.description?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      CustomText(
                        text: plan.description!,
                        fontSize: AppFontSize.verySmall,
                        color: AppColors.grey,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? AppColors.accentColor : AppColors.lightGrey2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.inventory_2_outlined, color: AppColors.grey, size: 40),
            SizedBox(height: 12),
            CustomText(
              text: 'No plans are available right now. Please check back later.',
              fontSize: AppFontSize.small,
              color: AppColors.grey,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimen.allPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            CustomText(
              text: message.isEmpty ? 'Something went wrong.' : message,
              fontSize: AppFontSize.small,
              color: AppColors.grey,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            AppButton(label: 'Try again', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
