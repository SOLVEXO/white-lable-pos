import 'package:flutter/material.dart';

/// Fixed logical sizes with a tablet step — deliberately NOT `responsive_sizer`'s
/// `.sp`, because the OS `textScaler` already scales these and a second scaling
/// layer would compound.
///
/// Styles carry no colour; components pick one from the palette.
/// Display / headline / title use Manrope, body text uses DM Sans (the Solvexo POS blueprint).
/// Money always uses the `amount*` styles: JetBrains Mono (monospaced), because DM Sans has no
/// OpenType `tnum` — checked against the font file and on the real engine — so digits would
/// jitter while a value updates. (Manrope does have `tnum` and could replace it: owner's call.)
///
/// Manrope and DM Sans are variable fonts: Flutter does NOT move the `wght` axis from `FontWeight`
/// (Manrope's default instance is weight 200!), so every style sets it explicitly.
@immutable
class AppTypeScale {
  const AppTypeScale._({
    required this.display,
    required this.headline,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.caption,
    required this.amountXl,
    required this.amountLg,
    required this.amountMd,
  });

  static const String displayFamily = 'Manrope';
  static const String sans = 'DMSans';
  static const String mono = 'JetBrainsMono';

  static const _tabular = [FontFeature.tabularFigures()];

  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle subtitle;
  final TextStyle body;
  final TextStyle bodySmall;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle amountXl;
  final TextStyle amountLg;
  final TextStyle amountMd;

  static TextStyle _s(
    double size,
    double line,
    FontWeight w, {
    String family = sans,
    double ls = 0,
    bool tabular = true,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: line / size,
    fontWeight: w,
    // variable fonts only: pin the axis to the weight (JetBrains Mono is static)
    fontVariations: family == mono ? null : [FontVariation('wght', w.value.toDouble())],
    letterSpacing: ls,
    fontFeatures: tabular ? _tabular : null,
    leadingDistribution: TextLeadingDistribution.even,
  );

  static final AppTypeScale phone = AppTypeScale._(
    display: _s(32, 40, FontWeight.w800, family: displayFamily, ls: -0.6),
    headline: _s(24, 32, FontWeight.w700, family: displayFamily, ls: -0.3),
    title: _s(18, 24, FontWeight.w700, family: displayFamily, ls: -0.1),
    subtitle: _s(16, 22, FontWeight.w600),
    body: _s(15, 22, FontWeight.w400),
    bodySmall: _s(13, 18, FontWeight.w400),
    label: _s(13, 16, FontWeight.w600, ls: 0.2),
    caption: _s(12, 16, FontWeight.w500, ls: 0.2),
    amountXl: _s(36, 44, FontWeight.w600, family: mono, ls: -0.5),
    amountLg: _s(24, 32, FontWeight.w600, family: mono, ls: -0.3),
    amountMd: _s(16, 22, FontWeight.w500, family: mono),
  );

  static final AppTypeScale tablet = AppTypeScale._(
    display: _s(40, 48, FontWeight.w800, family: displayFamily, ls: -0.8),
    headline: _s(28, 36, FontWeight.w700, family: displayFamily, ls: -0.4),
    title: _s(20, 28, FontWeight.w700, family: displayFamily, ls: -0.1),
    subtitle: _s(17, 24, FontWeight.w600),
    body: _s(16, 24, FontWeight.w400),
    bodySmall: _s(14, 20, FontWeight.w400),
    label: _s(14, 18, FontWeight.w600, ls: 0.2),
    caption: _s(12, 16, FontWeight.w500, ls: 0.2),
    amountXl: _s(44, 52, FontWeight.w600, family: mono, ls: -0.6),
    amountLg: _s(28, 36, FontWeight.w600, family: mono, ls: -0.3),
    amountMd: _s(17, 24, FontWeight.w500, family: mono),
  );

  /// Material [TextTheme] so stock widgets (dialogs, pickers, etc.) match.
  TextTheme toTextTheme(Color primary, Color secondary) => TextTheme(
    displayLarge: display.copyWith(color: primary),
    displayMedium: display.copyWith(color: primary),
    displaySmall: headline.copyWith(color: primary),
    headlineLarge: headline.copyWith(color: primary),
    headlineMedium: headline.copyWith(color: primary),
    headlineSmall: title.copyWith(color: primary),
    titleLarge: title.copyWith(color: primary),
    titleMedium: subtitle.copyWith(color: primary),
    titleSmall: label.copyWith(color: primary),
    bodyLarge: body.copyWith(color: primary),
    bodyMedium: body.copyWith(color: primary),
    bodySmall: bodySmall.copyWith(color: secondary),
    labelLarge: label.copyWith(color: primary),
    labelMedium: label.copyWith(color: secondary),
    labelSmall: caption.copyWith(color: secondary),
  );
}
