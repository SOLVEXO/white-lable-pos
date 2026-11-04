import 'package:flutter/material.dart';

/// "Ink & Ember" colour tokens. Fixed values — nothing is generated at runtime
/// and nothing here reads from the legacy `AppColors` / `AppBrand`.
///
/// Read with `context.palette`. Light and dark are two const instances of one
/// [ThemeExtension], so a screen never branches on brightness itself.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.fill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentStrong,
    required this.accentSoft,
    required this.accentFg,
    required this.onAccent,
    required this.accentFill,
    required this.onAccentFill,
    required this.success,
    required this.successSoft,
    required this.successFg,
    required this.warning,
    required this.warningSoft,
    required this.warningFg,
    required this.danger,
    required this.dangerSoft,
    required this.dangerFg,
    required this.onDanger,
    required this.info,
    required this.infoSoft,
    required this.infoFg,
    required this.scrim,
  });

  final Brightness brightness;

  // Neutrals
  final Color background;
  final Color surface;
  final Color surfaceRaised;

  /// Input / chip / well fill — one step off [surface].
  final Color fill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;

  // Accent (Solvexo coral)
  final Color accent;
  final Color accentStrong;

  /// Accent tint — soft backgrounds (opaque in light, translucent in dark).
  final Color accentSoft;

  /// Accent usable as *text/icon* on [surface] (≥ 4.5:1 in both modes).
  final Color accentFg;

  /// Label colour on an [accent] fill. White only reaches 3.08:1 on #DC7758,
  /// so this is the brand ink (5.78:1).
  final Color onAccent;

  /// Darker coral for the BACKGROUND of filled primary buttons, paired with
  /// white [onAccentFill] labels (#B4553A → 4.88:1). [accent] stays #DC7758 for
  /// icons, highlights, selected states, focus rings and the splash.
  final Color accentFill;
  final Color onAccentFill;

  // Semantic — fills, soft tint backgrounds, and text-safe foregrounds.
  final Color success;
  final Color successSoft;
  final Color successFg;
  final Color warning;
  final Color warningSoft;
  final Color warningFg;
  final Color danger;
  final Color dangerSoft;
  final Color dangerFg;
  final Color onDanger;
  final Color info;
  final Color infoSoft;
  final Color infoFg;

  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  // Brand coral from the Solvexo POS blueprint (design-tokens.json). Used for icons, highlights, selected states, focus
  // rings and illustrations — NEVER as a text colour or a white-label button fill (white on it is only 3.08:1).
  static const Color _accent = Color(0xFFDC7758);
  static const Color _accentLight = Color(0xFFF39072);
  static const Color _ink = Color(0xFF15181D);

  /// Dark mode keeps the blueprint's brand ink (#15181D) as its surface — the blueprint itself is light-only, so these dark
  /// values are ours, re-based on the same warm-neutral ink instead of the earlier navy.
  static const AppPalette dark = AppPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0F1114),
    surface: _ink,
    surfaceRaised: Color(0xFF1D2127),
    fill: Color(0xFF1D2127),
    border: Color(0xFF2C313A),
    textPrimary: Color(0xFFF4F1EE),
    textSecondary: Color(0xFFB9BEC6),
    textMuted: Color(0xFF9298A2),
    accent: _accent,
    accentStrong: _accentLight,
    accentSoft: Color(0x24DC7758),
    accentFg: _accentLight,
    onAccent: _ink,
    accentFill: Color(0xFFB4553A),
    onAccentFill: Color(0xFFFFFFFF),
    success: Color(0xFF20976B),
    successSoft: Color(0x2920976B),
    successFg: Color(0xFF4FD3A0),
    warning: Color(0xFFE8A22B),
    warningSoft: Color(0x29E8A22B),
    warningFg: Color(0xFFEBB04D),
    danger: Color(0xFFE5707E),
    dangerSoft: Color(0x29D94C5C),
    dangerFg: Color(0xFFFF8591),
    onDanger: _ink,
    info: Color(0xFF5B82E8),
    infoSoft: Color(0x334D72DB),
    infoFg: Color(0xFF8FAEFF),
    scrim: Color(0xB3080A0D),
  );

  static const AppPalette light = AppPalette(
    brightness: Brightness.light,
    background: Color(0xFFF4F1EE),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    fill: Color(0xFFEDE9E4),
    border: Color(0xFFE8E9EC),
    textPrimary: _ink,
    textSecondary: Color(0xFF4B515A),
    textMuted: Color(0xFF5F666E),
    accent: _accent,
    accentStrong: _accentLight,
    accentSoft: Color(0xFFFFF0EB),
    accentFg: Color(0xFFA84B31),
    onAccent: _ink,
    accentFill: Color(0xFFB4553A),
    onAccentFill: Color(0xFFFFFFFF),
    success: Color(0xFF20976B),
    successSoft: Color(0xFFE7F7F0),
    successFg: Color(0xFF157553),
    warning: Color(0xFFE8A22B),
    warningSoft: Color(0xFFFFF6DF),
    warningFg: Color(0xFF8A5A00),
    danger: Color(0xFFC23B4B),
    dangerSoft: Color(0xFFFFEDEF),
    dangerFg: Color(0xFFB83A49),
    onDanger: Color(0xFFFFFFFF),
    info: Color(0xFF4D72DB),
    infoSoft: Color(0xFFEDF2FF),
    infoFg: Color(0xFF3A5BC0),
    scrim: Color(0x66101215),
  );

  @override
  AppPalette copyWith() => this;

  /// Palettes are discrete (light/dark); lerp snaps at the midpoint rather than
  /// blending, which keeps theme switches from flashing muddy in-between greys.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}
