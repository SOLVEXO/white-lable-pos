import 'package:flutter/material.dart';

/// App-wide white-label branding — distinct from a single seller's own store
/// branding (`StoreModel.logo`/name/colors), which is unrelated and stays as
/// it is. This describes who operates *this build of the app itself*.
///
/// No backend endpoint for this exists yet (see `BrandingRepository`) — the
/// shape below is what Phase 4 needs from the platform-config/tenant team;
/// [BrandingConfigModel.defaults] is what the app renders until then, and is
/// identical to today's hardcoded Solvexo branding so nothing visually
/// changes before the backend field lands.
class BrandingConfigModel {
  final String appName;
  final String marketplaceName;

  /// Empty string means "use the bundled default asset" — see `AppImages.logoImage`.
  final String logoUrl;

  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;

  /// App-wide UI feature toggles (UI-level only — this never replaces a real
  /// backend entitlement/permission check). Unknown keys default to enabled
  /// via [isFeatureEnabled] so a flag missing from the backend response never
  /// hides a feature by accident.
  final Map<String, bool> featureFlags;

  const BrandingConfigModel({
    required this.appName,
    required this.marketplaceName,
    required this.logoUrl,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.featureFlags,
  });

  bool isFeatureEnabled(String key) => featureFlags[key] ?? true;

  factory BrandingConfigModel.defaults() => const BrandingConfigModel(
    appName: 'Solvexo',
    marketplaceName: 'Solvexo',
    logoUrl: '',
    primaryColor: Color(0xFFd97757),
    secondaryColor: Color(0xFF6FBF4A),
    accentColor: Color(0xFFd97757),
    featureFlags: {},
  );

  /// Builds branding from this app build's compile-time [StoreConfig] values
  /// (Phase 8 of the white-label conversion — one app binary per store).
  /// Blank strings/unparseable colors fall back to [defaults] field-by-field,
  /// same rule as [fromJson], so an unconfigured build renders identically
  /// to today's app. No logo param — the app logo is always the bundled
  /// `AppImages.logoImage` asset now, never runtime config (see
  /// STORE_ONBOARDING.md); a new store's logo is set by replacing that file.
  factory BrandingConfigModel.fromStoreConfig({
    required String appName,
    required String marketplaceName,
    required String? primaryColorHex,
    required String? secondaryColorHex,
    required String? accentColorHex,
  }) {
    final defaults = BrandingConfigModel.defaults();
    return BrandingConfigModel(
      appName: appName.trim().isNotEmpty ? appName : defaults.appName,
      marketplaceName: marketplaceName.trim().isNotEmpty ? marketplaceName : defaults.marketplaceName,
      logoUrl: defaults.logoUrl,
      primaryColor: _parseColor(primaryColorHex) ?? defaults.primaryColor,
      secondaryColor: _parseColor(secondaryColorHex) ?? defaults.secondaryColor,
      accentColor: _parseColor(accentColorHex) ?? defaults.accentColor,
      featureFlags: const {},
    );
  }

  factory BrandingConfigModel.fromJson(Map<String, dynamic> json) {
    final defaults = BrandingConfigModel.defaults();
    return BrandingConfigModel(
      appName: (json['appName'] as String?)?.trim().isNotEmpty == true
          ? json['appName'] as String
          : defaults.appName,
      marketplaceName: (json['marketplaceName'] as String?)?.trim().isNotEmpty == true
          ? json['marketplaceName'] as String
          : defaults.marketplaceName,
      logoUrl: (json['logoUrl'] as String?) ?? defaults.logoUrl,
      primaryColor: _parseColor(json['primaryColor']) ?? defaults.primaryColor,
      secondaryColor: _parseColor(json['secondaryColor']) ?? defaults.secondaryColor,
      accentColor: _parseColor(json['accentColor']) ?? defaults.accentColor,
      featureFlags: (json['featureFlags'] as Map?)?.map(
            (k, v) => MapEntry(k.toString(), v == true),
          ) ??
          defaults.featureFlags,
    );
  }

  Map<String, dynamic> toJson() => {
    'appName': appName,
    'marketplaceName': marketplaceName,
    'logoUrl': logoUrl,
    'primaryColor': '#${primaryColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
    'secondaryColor': '#${secondaryColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
    'accentColor': '#${accentColor.value.toRadixString(16).padLeft(8, '0').substring(2)}',
    'featureFlags': featureFlags,
  };

  /// Accepts `#RRGGBB`/`#AARRGGBB` (leading `#` optional).
  static Color? _parseColor(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    final hex = value.startsWith('#') ? value.substring(1) : value;
    final normalized = hex.length == 6 ? 'FF$hex' : hex;
    final parsed = int.tryParse(normalized, radix: 16);
    return parsed == null ? null : Color(parsed);
  }
}
