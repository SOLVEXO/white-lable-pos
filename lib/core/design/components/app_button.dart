import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'press_scale.dart';

enum AppButtonVariant {
  /// Filled brand button: [AppPalette.accentFill] with a white label (≥ 4.5:1).
  primary,

  /// Alternative fill: the brand coral #DC7758 with a dark-ink label (5.78:1).
  /// Kept for the design-gallery comparison; not the default.
  primaryBright,
  secondary,
  ghost,
  danger,
}

enum AppButtonSize { md, lg }

/// Primary / secondary / ghost / danger button with press-scale and a loading
/// state. Minimum height 48 (56 for [AppButtonSize.lg]). While [loading] the
/// button keeps its width (the label is hidden, not removed) and ignores taps.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.md,
    this.icon,
    this.loading = false,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final bool loading;

  /// Fill the available width (default) or hug the content.
  final bool expand;

  /// Spoken label; needed for an icon-only button (empty [label]), otherwise defaults to [label].
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = onPressed != null && !loading;
    final (bg, fg, side) = switch (variant) {
      AppButtonVariant.primary => (
        p.accentFill,
        p.onAccentFill,
        BorderSide.none,
      ),
      AppButtonVariant.primaryBright => (p.accent, p.onAccent, BorderSide.none),
      AppButtonVariant.secondary => (
        p.fill,
        p.textPrimary,
        BorderSide(color: p.border),
      ),
      AppButtonVariant.ghost => (
        Colors.transparent,
        p.accentFg,
        BorderSide.none,
      ),
      AppButtonVariant.danger => (p.danger, p.onDanger, BorderSide.none),
    };
    final height = size == AppButtonSize.lg ? 56.0 : Space.minTouch;
    final textStyle =
        (size == AppButtonSize.lg
                ? context.type.subtitle
                : context.type.label.copyWith(
                    fontSize: context.type.body.fontSize,
                  ))
            .copyWith(color: fg, fontWeight: FontWeight.w700);

    // An empty label with an icon is an icon-only button: just the centred icon, no gap, no side padding.
    final iconOnly = label.isEmpty && icon != null;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) Icon(icon, size: 20, color: fg),
        if (icon != null && !iconOnly) const SizedBox(width: Space.s2),
        if (!iconOnly) Flexible(child: Text(label, style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: enabled ? onPressed : null,
      child: Opacity(
        opacity: onPressed == null && !loading ? 0.45 : 1,
        child: PressScale(
          enabled: enabled,
          child: Material(
            color: bg,
            shape: RoundedRectangleBorder(borderRadius: Radii.rMd, side: side),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              overlayColor: WidgetStatePropertyAll(fg.withValues(alpha: 0.10)),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: height,
                  minWidth: Space.minTouch,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: iconOnly ? Space.s1 : Space.s5, vertical: Space.s2),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AnimatedOpacity(
                        opacity: loading ? 0 : 1,
                        duration: Motion.of(context, Motion.base),
                        child: content,
                      ),
                      if (loading)
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: fg,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
