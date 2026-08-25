import 'package:solvexo_pos/app/data/models/branding/branding_config_model.dart';

/// This repo's one store — hardcoded here directly, not a build-time flag.
///
/// White-label model: each store gets its **own copy of this whole repo**
/// (duplicated on GitHub, not built as a flavor of one shared repo — see
/// STORE_ONBOARDING.md), so there is never more than one store's config to
/// choose between at build time. Setting up a new store's repo means editing
/// the values below directly, the same way `lib/config/onboarding_content.dart`
/// and `AppImages.logoImage` are edited per store.
///
/// [storeSlug] is the one store this app serves — the same slug
/// `StorefrontRepository.getStoreBySlug` resolves to a `storeId` for every
/// subsequent per-store call, so it's the only identifier needed up front.
/// Leaving it blank (the default in this template repo) makes the app
/// behave as an unconfigured/generic demo build — see [isConfigured].
class StoreConfig {
  const StoreConfig._();

  static const String storeSlug = '';

  static const String appName = 'Solvexo';
  static const String marketplaceName = 'Solvexo';
  static const String primaryColorHex = '#d97757';
  static const String secondaryColorHex = '#6FBF4A';
  static const String accentColorHex = '#d97757';

  /// True once a real store has been bound to this repo. False for the
  /// unconfigured template — callers that require a store (Home content,
  /// follow/reviews, etc.) should treat that as "nothing to load" rather
  /// than guessing one.
  static bool get isConfigured => storeSlug.isNotEmpty;

  static BrandingConfigModel toBrandingConfig() => BrandingConfigModel.fromStoreConfig(
    appName: appName,
    marketplaceName: marketplaceName,
    primaryColorHex: primaryColorHex,
    secondaryColorHex: secondaryColorHex,
    accentColorHex: accentColorHex,
  );
}
