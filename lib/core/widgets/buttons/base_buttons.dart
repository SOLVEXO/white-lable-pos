import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import '../../theme/base_colors.dart';
import '../../theme/base_shadows.dart';
import '../../theme/base_spacing.dart';
import '../../theme/base_animations.dart';

/// Shared visual size contract every button in the family honors, so a
/// [PrimaryButton] and an [OutlineButton] on the same row always line up.
class _ButtonMetrics {
  static const double height = 52;
  static const double heightCompact = 44;
  static const double iconGap = BaseSpacing.xs;
  static const double radius = 14;
}

enum _ButtonKind { primary, secondary, outline, ghost, danger, gradient }

/// Internal shared button shell — every public button below is a thin
/// configuration of this one widget, so press-animation, disabled state,
/// loading state, and icon layout behave identically across the family.
class _BaseButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final _ButtonKind kind;
  final Widget? leadingIcon;
  final bool isLoading;
  final bool expand;
  final bool compact;
  final Gradient? gradient;

  const _BaseButton({
    required this.label,
    required this.onPressed,
    required this.kind,
    this.leadingIcon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
    this.gradient,
  });

  bool get _disabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final height = compact ? _ButtonMetrics.heightCompact : _ButtonMetrics.height;

    Color bg;
    Color fg;
    Border? border;
    List<BoxShadow> shadow = BaseShadows.none;

    switch (kind) {
      case _ButtonKind.primary:
        bg = _disabled ? BaseColors.primary.withOpacity(0.35) : BaseColors.primary;
        fg = Colors.white;
        shadow = _disabled ? BaseShadows.none : BaseShadows.forLevel(BaseElevation.level2);
        break;
      case _ButtonKind.secondary:
        bg = _disabled ? BaseColors.secondary.withOpacity(0.35) : BaseColors.secondary;
        fg = Colors.white;
        break;
      case _ButtonKind.outline:
        bg = Colors.transparent;
        fg = _disabled ? BaseColors.onSurfaceMutedLight : BaseColors.primary;
        border = Border.all(color: _disabled ? BaseColors.borderLight : BaseColors.primary, width: 1.4);
        break;
      case _ButtonKind.ghost:
        bg = Colors.transparent;
        fg = _disabled ? BaseColors.onSurfaceMutedLight : BaseColors.onSurfaceLight;
        break;
      case _ButtonKind.danger:
        bg = _disabled ? BaseColors.danger.withOpacity(0.35) : BaseColors.danger;
        fg = Colors.white;
        break;
      case _ButtonKind.gradient:
        bg = Colors.transparent;
        fg = Colors.white;
        shadow = _disabled ? BaseShadows.none : BaseShadows.glow();
        break;
    }

    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, valueColor: AlwaysStoppedAnimation(fg)),
          ),
          SizedBox(width: _ButtonMetrics.iconGap + BaseSpacing.xxs),
        ] else if (leadingIcon != null) ...[
          IconTheme(data: IconThemeData(color: fg, size: 20), child: leadingIcon!),
          SizedBox(width: _ButtonMetrics.iconGap + BaseSpacing.xxs),
        ],
        // Flexible is what lets the ellipsis actually engage — without it a
        // narrow button (half-width Row slots, loading spinner + long label)
        // overflows instead of truncating. Only for expanding buttons:
        // shrink-wrap ones (GhostButton) can sit in unbounded Rows, where a
        // flex child would throw instead of helping.
        if (expand)
          Flexible(
            child: CustomText(
              text: label,
              color: fg,
              fontSize: compact ? 13 : 15,
              fontWeight: FontWeight.w600,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          )
        else
          CustomText(
            text: label,
            color: fg,
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w600,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );

    return PressableScale(
      onTap: _disabled ? null : () { HapticFeedback.selectionClick(); onPressed!(); },
      scaleTo: 0.97,
      child: Container(
        width: expand ? double.infinity : null,
        height: height,
        padding: EdgeInsets.symmetric(horizontal: BaseSpacing.lg),
        decoration: BoxDecoration(
          color: kind == _ButtonKind.gradient ? null : bg,
          gradient: kind == _ButtonKind.gradient
              ? (_disabled ? null : (gradient ?? BaseColors.primaryGradient))
              : null,
          border: border,
          borderRadius: BorderRadius.circular(_ButtonMetrics.radius),
          boxShadow: shadow,
        ),
        alignment: Alignment.center,
        child: content,
      ),
    );
  }
}

/// Main call-to-action — one per screen, typically. "Sign In", "Checkout".
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool expand;
  final bool compact;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.primary,
        leadingIcon: icon,
        isLoading: isLoading,
        expand: expand,
        compact: compact,
      );
}

/// Secondary emphasis action, brand-adjacent color — "Save for later".
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool expand;
  final bool compact;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.secondary,
        leadingIcon: icon,
        isLoading: isLoading,
        expand: expand,
        compact: compact,
      );
}

/// Low-emphasis alternative next to a [PrimaryButton] — "Cancel", "Skip".
class OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool expand;
  final bool compact;

  const OutlineButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.outline,
        leadingIcon: icon,
        isLoading: isLoading,
        expand: expand,
        compact: compact,
      );
}

/// Lowest emphasis — text-only tap targets inline with content, e.g.
/// "Forgot password?", "Resend code". Prefer this over a bare [TextButton]
/// so spacing/typography stay tied to the token system.
class GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool compact;

  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.ghost,
        leadingIcon: icon,
        expand: false,
        compact: compact,
      );
}

/// Destructive actions — "Delete account", "Remove item".
class DangerButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool expand;
  final bool compact;

  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.danger,
        leadingIcon: icon,
        isLoading: isLoading,
        expand: expand,
        compact: compact,
      );
}

/// Hero-moment CTA with the brand gradient + glow shadow — use sparingly
/// (welcome screens, onboarding finales), not as the default primary button.
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final bool expand;
  final bool compact;
  final Gradient? gradient;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) => _BaseButton(
        label: label,
        onPressed: onPressed,
        kind: _ButtonKind.gradient,
        leadingIcon: icon,
        isLoading: isLoading,
        expand: expand,
        compact: compact,
        gradient: gradient,
      );
}

/// Circular icon-only tap target — 48x48 minimum touch area is enforced
/// regardless of the visible icon size, per accessibility requirements.
class AppIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final Color? background;
  final double size;

  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.background,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    final tapSize = size < 48 ? 48.0 : size;
    return PressableScale(
      onTap: onPressed == null ? null : () { HapticFeedback.selectionClick(); onPressed!(); },
      child: Container(
        width: tapSize,
        height: tapSize,
        decoration: BoxDecoration(
          color: background ?? BaseColors.surfaceVariantLight,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: icon,
      ),
    );
  }
}
