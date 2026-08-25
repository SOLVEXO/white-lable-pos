import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  /// Single app-wide typeface — headings, body, buttons, badges, prices.
  /// Every `CustomText`/`CustomButton` defaults here unless overridden.
  static const String fontFamily = 'Inter';

  /// Kept as aliases (not a second typeface) so the ~90 existing call sites
  /// that opt into these names still resolve to the one app font.
  static const String headingFontFamily = fontFamily;
  static const String altBodyFontFamily = fontFamily;
  static const String monoFontFamily = fontFamily;
  static const TextStyle headlineLarge = TextStyle(
    fontFamily: 'Inter',
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.black,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: 'Inter',
    fontSize: 19,
    fontWeight: FontWeight.w600,
    color: AppColors.black,
  );

  static const TextStyle body = TextStyle(
    fontFamily: 'Inter',
    fontSize: 16,
    color: AppColors.black,
  );

  static const TextTheme textTheme = TextTheme(
    headlineLarge: headlineLarge,
    headlineMedium: headlineMedium,
    bodyMedium: body,
  );
}
