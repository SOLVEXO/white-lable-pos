import 'package:solvexo_pos/app/data/services/branding_service.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AppColors {
  /// Tenant-swappable — reads through `BrandingService` (see Phase 4 white-
  /// label work); falls back to the hardcoded Solvexo terracotta before the
  /// service is registered (e.g. very first frame, or in widget tests that
  /// don't bootstrap it).
  static Color get primaryColor => Get.isRegistered<BrandingService>()
      ? Get.find<BrandingService>().config.value.primaryColor
      : const Color(0xFFd97757);

  static Color get secondryColor => Get.isRegistered<BrandingService>()
      ? Get.find<BrandingService>().config.value.secondaryColor
      : const Color(0xFF6FBF4A);

  static Color get accentColor => Get.isRegistered<BrandingService>()
      ? Get.find<BrandingService>().config.value.accentColor
      : const Color(0xFFd97757);

  static Gradient get appbarGradient => LinearGradient(
    colors: [AppColors.primaryColor, AppColors.lightgradianColor],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );
  // static const Color primaryColor = Color(0xFF7a73ff);
  // static const Color primaryColorLight = Color.fromARGB(168, 122, 115, 255);
  static const Color primaryColorLight = Color.fromARGB(179, 234, 140, 109);
  static const Color secondryColorLight = Color.fromARGB(179, 111, 191, 74);
  static const Color lightgradianColor = Color.fromARGB(
    69,
    194,
    102,
    72,
  ); // Gold
  // purple
  static const Color white = Color(0xFFFFFFFF);
  static const Color white2 = Color(0xFFF0F0F0);
  static const Color background = Color.fromARGB(242, 249, 249, 249);
  static const Color textPrimary = Color.fromARGB(190, 26, 26, 26);
  static const Color black = Color(0xFF000000);
  static const Color black2 = Color(0xFF343434);
  static const Color blackColor = Color(0xFF231F20);
  static const Color transparent = Colors.transparent;
  static const Color grey = Color(0xFF7D7D7D);
  static const Color lightGrey = Color(0xFF999999);
  static const Color lightGrey2 = Color(0xFFE8E8E8);
  static const Color lightGrey3 = Color(0xFFF9F9F9);
  static const Color lightGrey4 = Color(0xFFE7E7E7);
  static const Color lightGrey5 = Color(0xFF8C8C8C);
  static const Color lightGrey6 = Color(0xFF848484);
  static const Color lightGrey7 = Color(0xFFAEAEAE);
  static const Color lightGrey8 = Color(0xFF94A3B8);
  static const Color lightGrey9 = Color(0xFFA9A9A9);
  static const Color lightGrey10 = Color(0xFFF4F4F5);
  static const Color lightGrey11 = Color(0xFFE5E5E5);
  static const Color lightGrey12 = Color(0xFFADADAD);
  static const Color lightGrey13 = Color(0xFFDCDEE4);

  static const Color white10 = Color(0xffF2F2F2);
  static const Color textPrimaryColor = Color(0xFF999999);

  static const Color textfldFillColor = Color(0xFFF6F7F9);
  static const Color buttonDisableColor = Color(0xFFC8C8C8);
  static const Color notificationCircleBg = Color(0xFFF6F2E9);
  static const Color notificationBg = Color(0xFFF0E7D5);
  static const Color languageBg = Color(0xFFFDF4EE);

  static const Color accepted = Color(0xFF7AA79E);
  static const Color acceptedBg = Color(0xFFEFF8F5);

  static const Color failedBg = Color(0xFFFEF7EA);

  static const Color delete = Color(0xFFEC0071);
  static const Color green = Color(0xFF00FF36);
  static const Color green2 = Color(0xFF00C06F);
  static const Color red = Color(0xFFEC3B3B);
  static const Color error = Color(0xFFFF5A4E);

  static const Color orange = Color(0xFFDE8147);

  static const Color fieldsHeadingColor = Color(0xFF999999);
  static const Color textFieldBorderColor = Color(0xFFD1D5DB);
  static const Color dividerColor = Color(0xFFE6E6E6);
  static const Color separatorColor = Color(0xFFD9D9D9);
  static const Color barrierColor = Color(0xFF333333);
  static const Color bottomSheetDividerColor = Color(0xFFF7F7F7);
  static const Color gray600 = Color(0xFF7c7c7e);

  static const Color classBg = Color(0xFFFBF9F4);
  static const Color classBg2 = Color(0xFFFBFBFB);

  /// New Colors Alermin
  static const Color appBarColor = Color(0xFF006D5F);
  static const Color greyColor = Color(0xFF676977);
  static const Color dividerColorApp = Color(0xFFECECEC);
  static const Color lightPurple = Color(0xFFD9D4E8);
  static const Color lightGreen = Color(0xFFCBF6DF);
  static const Color lightCameo = Color(0xFFFFE7C7);
  static const Color lightRed = Color(0xFFF9D8D6);
  static const Color seaGreen = Color(0xFF3DD598);
  static const Color blue = Color(0xFF0062FF);
  static const Color americanBlue = Color(0xFF022169);
  static const Color lightPink = Color(0xFFF4DBEA);
  static const Color lightBlue = Color(0xFFBFE6F4);
  static const Color redStar = Color(0xFFFF3B30);

  static const Color greenContainerInnerColor = Color(0xFFEAF6ED);

  static const Color greenContainerBorderColor = Color(0xFF3CBA5E);
  static const Color darkGreen = Color(0xFF069952);

  static const Color bgColorSearchField = Color(0xFFF4F7FA);
  static const Color purpleColor = Color(0xFF582B87);

  static const Color lightGreyColor = Color(0xFFD8DDE6);

  static const Color multiSelectColor = Color(0xFFB7B7B7);

  static const Color dottedBorderColor = Color(0xFF707581);

  // Dark theme (seller / POS modules)
  // static const Color darkBackground = Color(0xFF1C1C1E);
  static const Color darkCard = Color(0xFF2C2C2E);
  static const Color iosGrey = Color(0xFF8E8E93);
  static const Color greenSuccess = Color(0xFF34C759);
  static const Color darkDivider = Color(0xFF3A3A3C);
  static const Color lightBorder = Color(0xFFE5E5EA);
  static const Color iosBlue = Color(0xFF007AFF);
  static const Color iosOrange = Color(0xFFFF9500);
  static const Color inactiveGrey = Color(0xFF636366);

  // Alert / warning
  static const Color yellowBg = Color(0xFFFFF8E7);
  static const Color yellow = Color(0xFFFFCC00);
  static const Color amberDark = Color(0xFFD97706);

  // Black opacity shortcuts
  static const Color black12 = Color(0x1F000000);
  static const Color black38 = Color(0x61000000);
  static const Color black54 = Color(0x8A000000);
  static const Color black87 = Color(0xDD000000);
  static const Color blackOverlay5 = Color(0x0D000000);
  static const Color blackOverlay10 = Color(0x1A000000);

  // Dark nav bar color (seller / POS bottom nav)
  static const Color darkNavBar = Color(0xFF1A1A1A);

  // Shimmer / skeleton
  static const Color shimmerBase = Color(0xFFE0E0E0);
  static const Color shimmerHighlight = Color(0xFFF5F5F5);
  static const Color shimmerShape = Color(0xFFD4D4D4);
  static const Color shimmerShapeAlt = Color(0xFFD6D6D6);
  static const Color productPageBg = Color(0xFFF8F8F8);

  // Material grey swatches
  static const Color greyDefault = Color(0xFF9E9E9E);
  static const Color greySwatch200 = Color(0xFFEEEEEE);
  static const Color greySwatch400 = Color(0xFFBDBDBD);
  static const Color greySwatch600 = Color(0xFF757575);

  // Category level accent colors
  static const Color categoryBlue = Color(0xFF4F7CFE);
  static const Color categoryPurple = Color(0xFF6B4EFF);
  static const Color categoryTeal = Color(0xFF00BFA5);
  static const Color categoryCoral = Color(0xFFFF6B6B);

  // Category item background colors
  static const Color categoryBg1 = Color(0xFFE7E6F2);
  static const Color categoryBg2 = Color(0xFFDDF0F1);
  static const Color categoryBg3 = Color(0xFFF4DFDF);
  static const Color categoryBg4 = Color(0xFFF2E8DC);

  // Material color equivalents
  static const Color materialAmber = Color(0xFFFFC107);
}
