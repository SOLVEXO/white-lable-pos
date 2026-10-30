import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/app/modules/onboarding/controllers/onboarding_controller.dart';
import 'package:solvexo_pos/config/onboarding_content.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/config/resources/app_text_styles.dart';
import 'package:solvexo_pos/core/theme/base_shadows.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<OnboardingController>();
    return Scaffold(
      backgroundColor: AppColors.blackColor,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppDimen.allPadding,
                  BaseSpacing.sm,
                  AppDimen.allPadding,
                  0,
                ),
                child: TextButton(
                  onPressed: controller.skip,
                  child: CustomText(
                    text: 'Skip',
                    color: AppColors.white.withOpacity(0.6),
                    fontSize: AppFontSize.verySmall,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: controller.pageController,
                onPageChanged: controller.onPageChanged,
                itemCount: controller.slides.length,
                itemBuilder: (_, i) =>
                    _OnboardingSlide(slide: controller.slides[i]),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                AppDimen.allPadding * 1.6,
                0,
                AppDimen.allPadding * 1.6,
                BaseSpacing.xl,
              ),
              child: Row(
                children: [
                  Obx(
                    () => Row(
                      children: List.generate(
                        controller.slides.length,
                        (i) => _PageIndicator(
                          isActive: i == controller.currentPage.value,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Obx(
                    () => _NextButton(
                      isLastPage: controller.isLastPage,
                      onTap: controller.next,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Slide content ────────────────────────────────────────────────────────

class _OnboardingSlide extends StatelessWidget {
  final OnboardingSlideContent slide;
  const _OnboardingSlide({required this.slide});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Scales the whole hero graphic down on short screens instead of
        // letting it overflow — everything below is relative to this.
        final heroSize = constraints.maxHeight < 560 ? 180.0 : 220.0;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimen.allPadding * 1.6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: _HeroGraphic(
                    icon: slide.icon,
                    imageAsset: slide.imageAsset,
                    size: heroSize,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    CustomText(
                      text: slide.title,
                      textAlign: TextAlign.left,
                      color: AppColors.white,
                      fontFamily: AppTextStyles.headingFontFamily,
                      fontSize: AppFontSize.veryLarge,
                      fontWeight: FontWeight.w800,
                    ),
                    SizedBox(height: BaseSpacing.sm),
                    CustomText(
                      text: slide.subtitle,
                      textAlign: TextAlign.left,
                      color: AppColors.white.withOpacity(0.6),
                      fontSize: AppFontSize.small2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Hero graphic — dotted bounding box + corner nodes framing the slide
// icon, echoing the tag-corner notch motif used elsewhere in the app ───────

class _HeroGraphic extends StatelessWidget {
  final IconData icon;
  final String? imageAsset;
  final double size;
  const _HeroGraphic({
    required this.icon,
    this.imageAsset,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final panelSize = size * 0.82;
    const nodeSize = 14.0;
    final asset = imageAsset;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _DottedBoxPainter(
              color: AppColors.white.withOpacity(0.22),
            ),
          ),
          Container(
            width: panelSize,
            height: panelSize,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(BaseRadius.xxl),
              boxShadow: BaseShadows.glow(AppColors.primaryColor),
            ),
            alignment: Alignment.center,
            child: (asset != null && asset.isNotEmpty)
                ? Image.asset(
                    asset,
                    height: panelSize,
                    width: panelSize,
                    fit: BoxFit.cover,
                  )
                : Icon(icon, size: panelSize * 0.45, color: AppColors.primaryColor),
          ),
          for (final alignment in const [
            Alignment.topLeft,
            Alignment.topRight,
            Alignment.bottomLeft,
            Alignment.bottomRight,
          ])
            Align(
              alignment: alignment,
              child: Container(
                width: nodeSize,
                height: nodeSize,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor,
                  borderRadius: BorderRadius.circular(BaseRadius.xs),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DottedBoxPainter extends CustomPainter {
  final Color color;
  const _DottedBoxPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashWidth = 6.0;
    const dashGap = 5.0;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    void drawDashedLine(Offset start, Offset end) {
      final total = (end - start).distance;
      final direction = (end - start) / total;
      var covered = 0.0;
      while (covered < total) {
        final segment = covered + dashWidth < total
            ? dashWidth
            : total - covered;
        final p1 = start + direction * covered;
        final p2 = start + direction * (covered + segment);
        canvas.drawLine(p1, p2, paint);
        covered += dashWidth + dashGap;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _DottedBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Bottom controls — dash/dot progress + circular next button ─────────────

class _PageIndicator extends StatelessWidget {
  final bool isActive;
  const _PageIndicator({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: EdgeInsets.symmetric(horizontal: BaseSpacing.xxs / 2),
      width: isActive ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primaryColor
            : AppColors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(BaseRadius.pill),
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final bool isLastPage;
  final VoidCallback onTap;
  const _NextButton({required this.isLastPage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isLastPage ? 'Get Started' : 'Next',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.white,
            shape: BoxShape.circle,
            boxShadow: BaseShadows.forLevel(BaseElevation.level3),
          ),
          alignment: Alignment.center,
          child: Icon(
            isLastPage ? Icons.check_rounded : Icons.arrow_forward_rounded,
            color: AppColors.blackColor,
            size: 22,
          ),
        ),
      ),
    );
  }
}
