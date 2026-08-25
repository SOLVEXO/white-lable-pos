/// Spacing scale — exactly these values, nothing in between. If a design
/// needs "15" or "18", round to the nearest token instead of hardcoding.
/// Every `SizedBox`, `EdgeInsets`, and `Gap` in a redesigned screen must
/// pick from here.
class BaseSpacing {
  BaseSpacing._();

  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;
  static const double s64 = 64;

  // Semantic aliases — prefer these in screen code; they read better than
  // s16/s24 and let the underlying scale value move in one place.
  static const double xxs = s4;
  static const double xs = s8;
  static const double sm = s12;
  static const double md = s16;
  static const double lg = s20;
  static const double xl = s24;
  static const double xxl = s32;
  static const double xxxl = s40;

  /// Standard screen edge padding.
  static const double screenPadding = md;
}

/// Corner-radius scale — exactly these values.
class BaseRadius {
  BaseRadius._();

  static const double r4 = 4;
  static const double r8 = 8;
  static const double r12 = 12;
  static const double r16 = 16;
  static const double r20 = 20;
  static const double r24 = 24;
  static const double r32 = 32;

  // Semantic aliases.
  static const double xs = r4;
  static const double sm = r8;
  static const double md = r12;
  static const double lg = r16;
  static const double xl = r20;
  static const double xxl = r24;
  static const double xxxl = r32;

  /// Fully circular — avatars, dot indicators, circular icon buttons.
  /// Not part of the numeric scale by design: it means "half of whichever
  /// side is shorter," not a fixed radius.
  static const double pill = 999;
}

/// Elevation system — 5 levels, each a fixed (shadow, blur, offset) preset.
/// Never call `BoxShadow(...)` inline in a redesigned screen; reach for
/// `BaseShadows.forLevel(BaseElevation.levelN)` instead.
enum BaseElevation {
  level1, // resting cards, list items
  level2, // raised cards, chips
  level3, // sticky headers, bottom bars
  level4, // dialogs, bottom sheets
  level5, // floating action buttons, toasts
}
