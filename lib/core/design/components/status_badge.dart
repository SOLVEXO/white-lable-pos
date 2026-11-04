import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

enum StatusTone { success, warning, danger, info, accent, neutral }

/// Compact status pill: tinted background + text-safe foreground (≥ 4.5:1).
/// Meaning is carried by the label (and optional icon), never colour alone.
class StatusBadge extends StatelessWidget {
  const StatusBadge(
    this.label, {
    super.key,
    this.tone = StatusTone.neutral,
    this.icon,
    this.dot = false,
  });
  final String label;
  final StatusTone tone;
  final IconData? icon;

  /// Leading status dot instead of an icon.
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = switch (tone) {
      StatusTone.success => (p.successSoft, p.successFg),
      StatusTone.warning => (p.warningSoft, p.warningFg),
      StatusTone.danger => (p.dangerSoft, p.dangerFg),
      StatusTone.info => (p.infoSoft, p.infoFg),
      StatusTone.accent => (p.accentSoft, p.accentFg),
      StatusTone.neutral => (p.fill, p.textSecondary),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: Radii.rFull),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Space.s3,
            vertical: 5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dot) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              if (icon != null && !dot) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: context.type.caption.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
