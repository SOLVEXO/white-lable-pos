import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';

/// Premium, dark-mode-ready color tokens for the new `core/` design system.
///
/// This is an *evolution* of [AppColors], not a replacement — every existing
/// screen still using [AppColors] keeps working unchanged. [BaseColors]
/// layers semantic, theme-aware tokens (surface/onSurface/border, gradients,
/// elevation overlays) on top of the same brand palette so newly-redesigned
/// screens and legacy screens still look like one product.
class BaseColors {
  BaseColors._();

  // ── Brand (same source of truth as AppColors) ─────────────────────────────
  static Color get primary => AppColors.primaryColor;
  static const Color primaryLight = AppColors.primaryColorLight;
  static Color get accent => AppColors.accentColor;
  static Color get secondary => AppColors.secondryColor;

  static Gradient get primaryGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, accent],
  );

  static Gradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [const Color(0xFFE8846A), primary, const Color(0xFFB85C3F)],
  );

  // ── Semantic (light) ───────────────────────────────────────────────────────
  static const Color surfaceLight = AppColors.white;
  static const Color surfaceVariantLight = Color(0xFFF7F5F3);
  static const Color backgroundLight = AppColors.background;
  static const Color onSurfaceLight = Color(0xFF1A1A1A);
  static const Color onSurfaceMutedLight = AppColors.gray600;
  static const Color borderLight = AppColors.lightGrey2;
  static const Color dividerLight = AppColors.dividerColor;

  // ── Semantic (dark) ─────────────────────────────────────────────────────────
  static const Color surfaceDark = Color(0xFF1C1C1E);
  static const Color surfaceVariantDark = Color(0xFF2C2C2E);
  static const Color backgroundDark = Color(0xFF121214);
  static const Color onSurfaceDark = Color(0xFFF2F2F2);
  static const Color onSurfaceMutedDark = Color(0xFFA1A1A6);
  static const Color borderDark = Color(0xFF38383A);
  static const Color dividerDark = Color(0xFF2C2C2E);

  // ── Status ───────────────────────────────────────────────────────────────
  static const Color success = AppColors.greenSuccess;
  static const Color warning = AppColors.amberDark;
  static const Color danger = AppColors.error;
  static const Color info = AppColors.iosBlue;

  // ── Glass / overlay ────────────────────────────────────────────────────────
  static Color glassLight = AppColors.white.withOpacity(0.72);
  static Color glassDark = const Color(0xFF1C1C1E).withOpacity(0.72);
  static Color scrim = AppColors.black.withOpacity(0.45);
}
