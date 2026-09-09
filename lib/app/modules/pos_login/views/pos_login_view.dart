import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/custom_text_field.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/core/theme/base_shadows.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/core/widgets/buttons/base_buttons.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_login/controllers/pos_login_controller.dart';

/// Two fully-integrated ways in — email/password and "Continue with
/// Google" — both hitting the real backend as role 'seller'. See
/// PosLoginController.
class PosLoginView extends StatelessWidget {
  const PosLoginView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<PosLoginController>();
    final heroHeight = MediaQuery.of(context).size.height * 0.32;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Obx(() {
          // A saved session is being checked (see
          // PosLoginController._restoreSession) — don't flash the form for
          // a returning seller who's about to be routed straight past it.
          if (controller.isCheckingSession.value) {
            return Center(
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryColor),
              ),
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(height: heroHeight),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    BaseSpacing.xl,
                    BaseSpacing.xxl,
                    BaseSpacing.xl,
                    BaseSpacing.xl,
                  ),
                  child: _LoginCard(controller: controller),
                ),
                CustomText(
                  text:
                      'New store owners: signing up with Google creates your account automatically.',
                  fontSize: AppFontSize.extraSmall,
                  color: AppColors.lightGrey,
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: BaseSpacing.xl),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryColor,
            AppColors.primaryColor.withOpacity(0.80),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(BaseRadius.xxxl),
          bottomRight: Radius.circular(BaseRadius.xxxl),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: _Blob(size: 140, opacity: 0.10),
          ),
          Positioned(
            bottom: -20,
            left: -40,
            child: _Blob(size: 120, opacity: 0.08),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(BaseRadius.xl),
                  boxShadow: BaseShadows.md,
                ),
                alignment: Alignment.center,
                child: SvgIcon(
                  assetName: AppIcons.posIcon,
                  size: 35,
                  color: AppColors.primaryColor,
                ),
              ),
              SizedBox(height: BaseSpacing.md),
              CustomText(
                text: 'POS',
                fontSize: AppFontSize.veryLarge,
                fontWeight: FontWeight.w700,
                color: AppColors.white,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: BaseSpacing.xxs),
              CustomText(
                text: 'Sell anywhere. Run your store on the go.',
                fontSize: AppFontSize.small,
                color: AppColors.white,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.opacity});
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(opacity),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.controller});
  final PosLoginController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(BaseSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(BaseRadius.xl),
        border: Border.all(color: AppColors.lightGrey2),
        boxShadow: BaseShadows.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomText(
            text: 'Email',
            fontSize: AppFontSize.extraSmall,
            fontWeight: FontWeight.w600,
          ),
          SizedBox(height: BaseSpacing.xs),
          CustomTextField(
            controller: controller.emailController,
            hintText: 'Enter Email',
            fillColor: AppColors.lightGrey3,
            keyboardType: TextInputType.emailAddress,
            prefixIcon: SvgIcon(
              assetName: AppIcons.emailIcon,
              size: 18,
              color: AppColors.grey,
            ),
          ),
          SizedBox(height: BaseSpacing.md),
          CustomText(
            text: 'Password',
            fontSize: AppFontSize.extraSmall,
            fontWeight: FontWeight.w600,
          ),
          SizedBox(height: BaseSpacing.xs),
          Obx(
            () => CustomTextField(
              controller: controller.passwordController,
              hintText: 'Password',
              fillColor: AppColors.lightGrey3,
              obscureText: controller.obscurePassword.value,
              onFieldSubmitted: (_) => controller.loginWithEmail(),
              prefixIcon: Icon(
                Icons.lock_outline_rounded,
                size: 22,
                color: AppColors.grey,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  controller.obscurePassword.value
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.grey,
                ),
                onPressed: controller.toggleObscurePassword,
              ),
            ),
          ),
          SizedBox(height: BaseSpacing.lg),
          Obx(
            () => PrimaryButton(
              label: controller.isEmailLoading.value
                  ? 'Logging in...'
                  : 'Log in',
              isLoading: controller.isEmailLoading.value,
              onPressed: controller.isBusy ? null : controller.loginWithEmail,
            ),
          ),
          SizedBox(height: BaseSpacing.lg),
          _OrDivider(),
          SizedBox(height: BaseSpacing.lg),
          Obx(
            () => _GoogleButton(
              onTap: controller.continueWithGoogle,
              isLoading: controller.isGoogleLoading.value,
              disabled: controller.isBusy && !controller.isGoogleLoading.value,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.lightGrey2, thickness: 1)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: BaseSpacing.sm),
          child: CustomText(
            text: 'OR',
            fontSize: AppFontSize.extraSmall,
            fontWeight: FontWeight.w600,
            color: AppColors.grey,
          ),
        ),
        Expanded(child: Divider(color: AppColors.lightGrey2, thickness: 1)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.onTap,
    required this.isLoading,
    this.disabled = false,
  });
  final VoidCallback onTap;
  final bool isLoading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final inactive = isLoading || disabled;
    return GestureDetector(
      onTap: inactive ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: inactive ? 0.6 : 1,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(BaseRadius.pill),
            border: Border.all(color: AppColors.lightGrey2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: isLoading
                ? [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ]
                : [
                    SvgIcon(assetName: AppIcons.googleIcon, size: 22),
                    SizedBox(width: BaseSpacing.sm),
                    CustomText(
                      text: 'Continue with Google',
                      color: AppColors.black2,
                      fontSize: AppFontSize.small2,
                      fontWeight: FontWeight.w600,
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}
