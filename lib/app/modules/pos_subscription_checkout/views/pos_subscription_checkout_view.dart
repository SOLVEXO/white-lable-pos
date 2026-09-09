import 'package:solvexo_pos/app/components/buttons/app_button.dart';
import 'package:solvexo_pos/app/components/custom_app_bar_two.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/pos_subscription_checkout/controllers/pos_subscription_checkout_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PosSubscriptionCheckoutView extends StatelessWidget {
  PosSubscriptionCheckoutView({super.key});

  final PosSubscriptionCheckoutController c = Get.find();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      appBar: CustomAppBarTwo(
        title: 'Checkout',
        color: AppColors.black2,
        backgroundColor: AppColors.white,
      ),
      body: Obx(() {
        switch (c.uiState.value) {
          case PosSubscriptionCheckoutUiState.webview:
            final webViewController = c.webViewController;
            if (webViewController == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return WebViewWidget(controller: webViewController);
          case PosSubscriptionCheckoutUiState.confirming:
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  CustomText(
                    text: 'Confirming your purchase…',
                    fontSize: AppFontSize.small,
                    color: AppColors.grey,
                  ),
                ],
              ),
            );
          case PosSubscriptionCheckoutUiState.error:
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppDimen.allPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: AppColors.error, size: 40),
                    const SizedBox(height: 12),
                    CustomText(
                      text: c.errorMessage.value,
                      fontSize: AppFontSize.small,
                      color: AppColors.grey,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    AppButton(label: 'Check again', onPressed: c.retryConfirm),
                  ],
                ),
              ),
            );
        }
      }),
    );
  }
}
