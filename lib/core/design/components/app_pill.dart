import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// A filter / toggle pill (G6.3): "All · Held · Refunded", "This register · All registers", a date-range chip. Selected = accent tint
/// with an accent-coloured label and a check; unselected = fill. At least 48 dp tall, one semantic label with its selected state.
/// Use a `Wrap` of pills for a filter row; for a single-select set, exactly one is [selected].
class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.label, required this.onTap, this.selected = false, this.icon, this.trailingIcon});
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final IconData? icon;

  /// e.g. a dropdown chevron for a pill that opens a picker, or a clear "×".
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final fg = selected ? p.accentFg : p.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? p.accentSoft : p.fill,
        shape: RoundedRectangleBorder(borderRadius: Radii.rFull, side: BorderSide(color: selected ? p.accent : p.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Space.minTouch, minWidth: Space.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected && icon == null) ...[Icon(Icons.check_rounded, size: IconSizes.xs, color: fg), const SizedBox(width: Space.s1)],
                  if (icon != null) ...[Icon(icon, size: IconSizes.xs, color: fg), const SizedBox(width: Space.s1)],
                  Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.type.label.copyWith(color: fg))),
                  if (trailingIcon != null) ...[const SizedBox(width: Space.s1), Icon(trailingIcon, size: IconSizes.xs, color: fg)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
