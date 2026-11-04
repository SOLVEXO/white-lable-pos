import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../responsive/breakpoints.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';
import '../tokens/typography.dart';

/// Read tokens from any [BuildContext]: `context.palette`, `context.type`.
extension DesignContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppPalette.dark
          : AppPalette.light);

  /// Type scale for the current width class (phone vs tablet step).
  AppTypeScale get type =>
      ScreenClass.of(this).isPhone ? AppTypeScale.phone : AppTypeScale.tablet;

  ScreenClass get screen => ScreenClass.of(this);
  bool get isPhone => screen.isPhone;

  List<BoxShadow> get softShadow => AppShadows.soft(Theme.of(this).brightness);
  List<BoxShadow> get raisedShadow =>
      AppShadows.raised(Theme.of(this).brightness);
  List<BoxShadow> get overlayShadow =>
      AppShadows.overlay(Theme.of(this).brightness);
}

abstract final class AppTheme {
  static final ThemeData light = _build(AppPalette.light);
  static final ThemeData dark = _build(AppPalette.dark);

  static ThemeData _build(AppPalette p) {
    final isDark = p.isDark;
    final scheme = ColorScheme(
      brightness: p.brightness,
      primary: p.accent,
      onPrimary: p.onAccent,
      secondary: p.accentStrong,
      onSecondary: p.onAccent,
      error: p.danger,
      onError: p.onDanger,
      surface: p.surface,
      onSurface: p.textPrimary,
      surfaceContainerHighest: p.fill,
      onSurfaceVariant: p.textSecondary,
      outline: p.border,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: p.scrim,
    );
    final text = AppTypeScale.phone.toTextTheme(p.textPrimary, p.textSecondary);
    final inputBorder = OutlineInputBorder(
      borderRadius: Radii.rMd,
      borderSide: BorderSide(color: p.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      fontFamily: AppTypeScale.sans,
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      splashFactory: InkRipple.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypeScale.phone.title.copyWith(color: p.textPrimary),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.fill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.s4,
          vertical: Space.s4,
        ),
        labelStyle: AppTypeScale.phone.body.copyWith(color: p.textMuted),
        floatingLabelStyle: AppTypeScale.phone.label.copyWith(
          color: p.accentFg,
        ),
        hintStyle: AppTypeScale.phone.body.copyWith(color: p.textMuted),
        errorStyle: AppTypeScale.phone.caption.copyWith(color: p.dangerFg),
        helperStyle: AppTypeScale.phone.caption.copyWith(color: p.textMuted),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: p.accent, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: p.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: p.danger, width: 2),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: p.border.withValues(alpha: 0.5)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accent.withValues(alpha: 0.28),
        selectionHandleColor: p.accent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: p.scrim,
        // Material 3 caps sheets at 640; AppSheetSurface / AppBottomSheet.show set each sheet's own max width instead.
        constraints: const BoxConstraints(maxWidth: double.infinity),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rLg,
          side: BorderSide(color: p.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceRaised,
        contentTextStyle: AppTypeScale.phone.body.copyWith(
          color: p.textPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: Radii.rMd),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAccent : p.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.accent : p.fill,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? Colors.transparent : p.border,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.fill,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: Radii.rSm,
          border: Border.all(color: p.border),
        ),
        textStyle: AppTypeScale.phone.caption.copyWith(color: p.textPrimary),
      ),
      extensions: <ThemeExtension<dynamic>>[p],
    );
  }
}
