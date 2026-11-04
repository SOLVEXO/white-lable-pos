import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/onboarding/controllers/onboarding_controller.dart';
import 'package:solvexo_pos/config/onboarding_content.dart';
import 'package:solvexo_pos/core/design/design.dart';

class OnboardingView extends StatelessWidget {
  const OnboardingView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.find<OnboardingController>();
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Space.s4,
                      Space.s2,
                      Space.s4,
                      0,
                    ),
                    child: TextButton(
                      onPressed: c.skip,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(Space.minTouch, Space.minTouch),
                        foregroundColor: p.textSecondary,
                      ),
                      child: Text(
                        'Skip',
                        style: context.type.label.copyWith(
                          color: p.textSecondary,
                          fontSize: context.type.body.fontSize,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: c.pageController,
                    onPageChanged: c.onPageChanged,
                    itemCount: c.slides.length,
                    itemBuilder: (_, i) => _Slide(slide: c.slides[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s6,
                    Space.s4,
                    Space.s6,
                    Space.s6,
                  ),
                  child: Row(
                    children: [
                      Obx(
                        () => _Dots(
                          count: c.slides.length,
                          index: c.currentPage.value,
                        ),
                      ),
                      const Spacer(),
                      Obx(() => _Cta(isLast: c.isLastPage, onTap: c.next)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.slide});
  final OnboardingSlideContent slide;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = context.type;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Semantics(
          header: true,
          child: Text(
            slide.title,
            style: t.display.copyWith(color: p.textPrimary),
          ),
        ),
        const SizedBox(height: Space.s3),
        Text(
          slide.subtitle,
          style: t.body.copyWith(
            color: p.textSecondary,
            fontSize: t.subtitle.fontSize,
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 720;
        final hero = _Hero(
          icon: slide.icon,
          imageAsset: slide.imageAsset,
          size: wide ? 260 : (box.maxHeight < 560 ? 168 : 216),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s6),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: Center(child: hero)),
                    const SizedBox(width: Space.s8),
                    Expanded(child: text),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: Center(child: hero)),
                    Expanded(flex: 3, child: text),
                  ],
                ),
        );
      },
    );
  }
}

/// Concentric accent rings around an icon (or bundled illustration).
class _Hero extends StatelessWidget {
  const _Hero({
    required this.icon,
    required this.imageAsset,
    required this.size,
  });
  final IconData icon;
  final String? imageAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accentSoft.withValues(alpha: 0.5),
              ),
            ),
            Container(
              width: size * 0.74,
              height: size * 0.74,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accentSoft,
              ),
            ),
            Container(
              width: size * 0.48,
              height: size * 0.48,
              decoration: BoxDecoration(
                color: p.surface,
                borderRadius: Radii.rXl,
                border: Border.all(color: p.border),
                boxShadow: context.raisedShadow,
              ),
              child: imageAsset != null
                  ? Padding(
                      padding: const EdgeInsets.all(Space.s4),
                      child: Image.asset(imageAsset!, fit: BoxFit.contain),
                    )
                  : Icon(icon, size: size * 0.24, color: p.accent),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: Motion.of(context, Motion.slow),
              curve: Motion.emphasized,
              margin: const EdgeInsets.only(right: 6),
              width: i == index ? 28 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? p.accent : p.border,
                borderRadius: Radii.rFull,
              ),
            ),
        ],
      ),
    );
  }
}

/// "Next" → "Get started": the label cross-fades and the button's width morphs.
class _Cta extends StatelessWidget {
  const _Cta({required this.isLast, required this.onTap});
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Motion.of(context, Motion.slow),
      curve: Motion.emphasized,
      alignment: Alignment.centerRight,
      child: AppButton(
        label: isLast ? 'Get started' : 'Next',
        icon: isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
        size: AppButtonSize.lg,
        expand: false,
        onPressed: onTap,
      ),
    );
  }
}
