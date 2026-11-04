import 'package:flutter/widgets.dart';

/// Phone < 600, tablet 600–1100, large > 1100 (logical px, by width).
enum ScreenClass {
  phone,
  tablet,
  large;

  static const double tabletMin = 600;
  static const double largeMin = 1100;

  static ScreenClass fromWidth(double w) =>
      w < tabletMin ? phone : (w <= largeMin ? tablet : large);

  static ScreenClass of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  bool get isPhone => this == phone;
  bool get isTabletUp => this != phone;
}

/// Picks a value per [ScreenClass]; tablet falls back to phone and large to tablet.
T responsiveValue<T>(
  BuildContext context, {
  required T phone,
  T? tablet,
  T? large,
}) {
  switch (ScreenClass.of(context)) {
    case ScreenClass.phone:
      return phone;
    case ScreenClass.tablet:
      return tablet ?? phone;
    case ScreenClass.large:
      return large ?? tablet ?? phone;
  }
}
