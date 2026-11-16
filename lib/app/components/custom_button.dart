import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Legacy button API, now drawn as the design-system [AppButton] (G6.3). New code uses [AppButton] directly.
///
/// The old colour options map onto [AppButtonVariant]: a transparent fill (an outlined button) → `secondary`, a red
/// fill → `danger`, anything else → `primary`; pass [variant] to choose explicitly. Text styling options
/// ([fontFamily], [fontSize], [fontWeight], [textColor], [borderRadius]) are kept only so existing callers compile —
/// the design system owns type and shape. A [prefix] [Icon] becomes the button's icon; an empty [label] with a
/// [prefix] (the callers' "spinner instead of text" pattern) shows the button's loading state.
class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.label,
    this.fontFamily,
    this.color,
    required this.onPressed,
    this.enabled = true,
    this.textColor,
    this.fontSize,
    this.fontWeight = FontWeight.w500,
    this.prefix,
    this.suffix,
    this.borderColor,
    this.borderRadius = Radii.md,
    this.width,
    this.height = Space.minTouch,
    this.variant,
  });

  final String label;
  final String? fontFamily;
  final Color? color;
  final Color? textColor;
  final Color? borderColor;
  final bool enabled;
  final void Function()? onPressed;
  final double? fontSize;
  final FontWeight fontWeight;
  final Widget? prefix;
  final Widget? suffix;
  final double? width;
  final double height;
  final double borderRadius;
  final AppButtonVariant? variant;

  AppButtonVariant get _variant {
    if (variant != null) return variant!;
    final c = color;
    if (c == null) return AppButtonVariant.primary;
    if (c.a == 0) return AppButtonVariant.secondary;
    final hsv = HSVColor.fromColor(c);
    final reddish = (hsv.hue < 15 || hsv.hue > 345) && hsv.saturation > 0.5 && hsv.value > 0.4;
    return reddish ? AppButtonVariant.danger : AppButtonVariant.primary;
  }

  @override
  Widget build(BuildContext context) {
    final loading = label.isEmpty && prefix != null;
    final pre = prefix;
    final button = AppButton(
      label: label,
      variant: _variant,
      icon: pre is Icon ? pre.icon : null,
      loading: loading,
      expand: width != null,
      onPressed: enabled ? onPressed : null,
    );
    return width == null ? button : SizedBox(width: width, child: button);
  }
}
