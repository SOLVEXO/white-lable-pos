import 'package:solvexo_pos/config/app_brand.dart';
import 'package:solvexo_pos/app/modules/seller_onboarding/controllers/seller_onboarding_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class Step5GoLive extends StatelessWidget {
  final SellerOnboardingController controller;

  const Step5GoLive({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final marketplaceName = AppBrand.marketplaceName;
    final p = context.palette;
    final t = context.type;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        children: [
          const SizedBox(height: Space.s2),
          AppCard(
            child: Column(
              children: [
                const SizedBox(height: Space.s3),
                ExcludeSemantics(child: Text('🎉', style: t.display)),
                const SizedBox(height: Space.s4),
                Text(
                  'Your store setup is ready!',
                  style: t.headline.copyWith(color: p.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s2),
                Text(
                  'Welcome to $marketplaceName. One more step: verify your business details so our team can approve your store — you can only publish products on $marketplaceName once it\'s approved.',
                  style: t.bodySmall.copyWith(color: p.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.s6),
                _SetupSummary(controller: controller),
                const SizedBox(height: Space.s6),
                const _SectionTitle(title: 'What happens next'),
                const SizedBox(height: Space.s3),
                const _NextStepsTimeline(),
                const SizedBox(height: Space.s5),
              ],
            ),
          ),
          const SizedBox(height: Space.s4),
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
    final appName = AppBrand.appName;
    final p = context.palette;
    return Obx(
      () => Container(
        padding: const EdgeInsets.all(Space.s3),
        decoration: BoxDecoration(color: p.fill, borderRadius: Radii.rMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your $appName Setup',
              style: context.type.label.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.s3),
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
            const _SummaryRow(
              emoji: '💳',
              label: 'Plan',
              value: 'Starter — Free',
            ),
            const _SummaryRow(
              emoji: '✨',
              label: 'AI Credits',
              value: '100 free credits included',
            ),
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
    final p = context.palette;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: ExcludeSemantics(child: Text(emoji, style: t.bodySmall)),
          ),
          const SizedBox(width: Space.s2),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: t.caption.copyWith(color: p.textSecondary),
            ),
          ),
          const SizedBox(width: Space.s1),
          Expanded(
            child: Text(
              value,
              style: t.caption.copyWith(
                color: p.textPrimary,
                fontWeight: FontWeight.w600,
              ),
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
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: context.type.subtitle.copyWith(
            color: context.palette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    final marketplaceName = AppBrand.marketplaceName;
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
    final p = context.palette;
    final t = context.type;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: p.fill,
            shape: BoxShape.circle,
            border: Border.all(color: p.border),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(emoji, style: t.bodySmall),
            ),
          ),
        ),
        const SizedBox(width: Space.s3),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 2, top: Space.s1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: t.label.copyWith(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: t.caption.copyWith(color: p.textSecondary),
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
      child: Container(width: 1.5, height: 18, color: context.palette.border),
    );
  }
}
