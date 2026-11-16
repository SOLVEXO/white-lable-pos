import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// The one list row (G6.3, promoted from the hubs' `HubRow`): a tinted icon tile, title, optional subtitle, an optional
/// trailing widget / badge / lock, and a chevron when it navigates. Card-shaped, ≥ 48 dp tall, one semantic label.
///
/// [tone] tints the icon tile for status rows (an alert is warning / danger; a plain navigation row is accent).
/// There is deliberately no "coming soon" variant: an entry whose screen does not exist is hidden, never shown disabled (G6.3 guard).
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.badge = 0,
    this.locked = false,
    this.tone = StatusTone.accent,
    this.trailing,
    this.chevron,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final int badge;

  /// Opens behind the owner gate / manager PIN (a small lock tells the user before they tap).
  final bool locked;
  final StatusTone tone;

  /// Replaces the badge / chevron area (e.g. an amount or a status pill).
  final Widget? trailing;

  /// Defaults to "shown when the row can be tapped".
  final bool? chevron;

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
    final showChevron = chevron ?? (onTap != null);
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: Space.s4, vertical: Space.s3),
      onTap: onTap,
      semanticLabel: [
        title,
        if (subtitle != null) subtitle!,
        if (locked) 'needs owner access',
        if (badge > 0) '$badge need attention',
      ].join('. '),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Space.minTouch - Space.s3),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, borderRadius: Radii.rMd),
              child: Icon(icon, size: IconSizes.md, color: fg),
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.type.subtitle.copyWith(color: p.textPrimary)),
                  if (subtitle != null) Text(subtitle!, style: context.type.bodySmall.copyWith(color: p.textSecondary)),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: Space.s2), trailing!],
            if (badge > 0) StatusBadge('$badge', tone: StatusTone.warning),
            if (locked)
              Padding(
                padding: const EdgeInsets.only(left: Space.s2),
                child: Icon(Icons.lock_outline_rounded, size: IconSizes.xs, color: p.textMuted),
              ),
            if (showChevron) Icon(Icons.chevron_right_rounded, color: p.textMuted),
          ],
        ),
      ),
    );
  }
}
