import 'package:flutter/material.dart';

/// First-launch onboarding slides for the POS app — shown once, before the
/// seller login screen. Each slide is a short title/subtitle plus a
/// Material [icon] (tinted with the tenant's own primary color, so it needs
/// no bundled artwork) or a bundled [OnboardingSlideContent.imageAsset]
/// path if a tenant build wants its own illustration instead.
class OnboardingSlideContent {
  final String title;
  final String subtitle;
  final IconData icon;

  /// Optional — a bundled asset path. When set, this renders instead of
  /// [icon].
  final String? imageAsset;

  const OnboardingSlideContent({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.imageAsset,
  });
}

const List<OnboardingSlideContent> onboardingSlides = [
  OnboardingSlideContent(
    title: 'Sell Anywhere, Anytime',
    subtitle: 'Ring up sales in seconds from any counter or device.',
    icon: Icons.point_of_sale_rounded,
  ),
  OnboardingSlideContent(
    title: 'Track Every Sale Live',
    subtitle: 'Watch revenue, orders, and shifts update in real time.',
    icon: Icons.receipt_long_rounded,
  ),
  OnboardingSlideContent(
    title: 'Manage Stock with Ease',
    subtitle: 'Keep inventory accurate across every register and store.',
    icon: Icons.inventory_2_rounded,
  ),
];
