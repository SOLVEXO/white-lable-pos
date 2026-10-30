import 'dart:math' as math;
import 'package:solvexo_pos/app/components/animated_background_circles.dart';
import 'package:solvexo_pos/app/components/common_image_view.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/components/svg_icon.dart';
import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:solvexo_pos/app/modules/splash_screen/controllers/splash_screen_controller.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_icons.dart';
import 'package:solvexo_pos/config/resources/app_images.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SplashScreenView extends StatelessWidget {
  const SplashScreenView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<SplashScreenController>();
    return Scaffold(
      // The gradient background bleeds edge-to-edge behind the status bar;
      // content itself still wraps in SafeArea below.
      body: Stack(
        children: [
          // ── Gradient background ──────────────────────────────────────────
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(gradient: AppColors.appbarGradient),
          ),

          // ── Animated background circles ──────────────────────────────────
          const AnimatedBackgroundCircles(),

          // ── Main content ─────────────────────────────────────────────────
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // Logo with glow pulse
                AnimatedBuilder(
                  animation: Listenable.merge([
                    controller.logoController,
                    controller.glowController,
                  ]),
                  builder: (context, _) {
                    final glow = controller.glowAnim.value;
                    return SlideTransition(
                      position: controller.slideAnim,
                      child: ScaleTransition(
                        scale: controller.scaleAnim,
                        child: Container(
                          height: 100,
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(BaseRadius.xxl),
                            boxShadow: [
                              // Base shadow
                              BoxShadow(
                                color: AppColors.black.withOpacity(0.15),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                              // Animated glow
                              BoxShadow(
                                color: AppColors.white.withOpacity(
                                  0.15 + 0.25 * glow,
                                ),
                                blurRadius: 20 + 30 * glow,
                                spreadRadius: 2 + 10 * glow,
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(3),
                            child: CommonImageView(
                              imagePath: AppImages.logoImage,
                              fit: BoxFit.contain,
                              radius: BorderRadius.circular(BaseRadius.xxl),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                SizedBox(height: BaseSpacing.xxl - BaseSpacing.xxs),

                // Brand name + slogan
                AnimatedBuilder(
                  animation: controller.logoController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: controller.brandFade.value,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Brand name
                          Obx(
                            () => CustomText(
                              text:
                                  '${Get.find<BrandingService>().config.value.appName} POS',
                              textAlign: TextAlign.center,
                              color: AppColors.white,
                              fontFamily: AppTextStyles.headingFontFamily,
                              fontSize: AppFontSize.large,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),

                          SizedBox(height: BaseSpacing.xxs + 2),

                          // Thin divider
                          Container(
                            width: 40,
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: AppColors.white.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(
                                BaseRadius.xs,
                              ),
                            ),
                          ),

                          SizedBox(height: BaseSpacing.sm + BaseSpacing.xxs),

                          // Animated slogan
                          SizedBox(
                            height: 22,
                            child: Center(
                              child: AnimatedBuilder(
                                animation: controller.sloganController,
                                builder: (context, _) {
                                  return Opacity(
                                    opacity: controller.sloganFade.value,
                                    child: Obx(
                                      () => CustomText(
                                        text: controller.currentSlogan,
                                        textAlign: TextAlign.center,
                                        color: AppColors.white.withOpacity(
                                          0.85,
                                        ),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const Spacer(flex: 4),

                // ── Bottom logo mark + loading dots ──────────────────────
                Padding(
                  padding: EdgeInsets.only(
                    bottom: BaseSpacing.xxl + BaseSpacing.xxs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _AnimatedDots(glowAnim: controller.glowAnim),
                      SizedBox(height: BaseSpacing.lg),
                      Container(
                        padding: EdgeInsets.all(BaseSpacing.xxs - 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BaseRadius.sm),
                          color: AppColors.white.withOpacity(0.2),
                        ),
                        child: SvgIcon(
                          assetName: AppIcons.posIcon,
                          size: 22,
                          color: AppColors.white,
                        ),
                      ),
                    ],
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

// ── Animated loading dots ───────────────────────────────────────────────────

class _AnimatedDots extends StatelessWidget {
  const _AnimatedDots({required this.glowAnim});
  final Animation<double> glowAnim;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: glowAnim,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot peaks at a different phase of the 0→1 cycle
            final phase = i / 3.0;
            final raw = math.sin(math.pi * ((glowAnim.value - phase) % 1.0));
            final t = raw.clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: BaseSpacing.xxs - 0.5),
              child: Container(
                width: 6 + 2 * t,
                height: 6 + 2 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.white.withOpacity(0.3 + 0.6 * t),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
