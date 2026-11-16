import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';
import 'empty_state.dart';
import 'status_badge.dart';

(Color, Color) _toneColors(AppPalette p, StatusTone tone) => switch (tone) {
      StatusTone.success => (p.successSoft, p.successFg),
      StatusTone.warning => (p.warningSoft, p.warningFg),
      StatusTone.danger => (p.dangerSoft, p.dangerFg),
      StatusTone.info => (p.infoSoft, p.infoFg),
      StatusTone.accent => (p.accentSoft, p.accentFg),
      StatusTone.neutral => (p.fill, p.textSecondary),
    };

/// A one-line notice inside a page (G6.3): offline ("Showing the last saved figures"), an older server ("needs the newer
/// Solvexo server"), a plan or permission note. Tinted by [tone]; the message carries the meaning, never colour alone.
class AppBanner extends StatelessWidget {
  const AppBanner({super.key, required this.message, this.title, this.icon, this.tone = StatusTone.info, this.actionLabel, this.onAction, this.inset = true});

  /// The standard offline notice.
  const AppBanner.offline({super.key, this.message = 'You are offline. Showing what this device last saw; selling still works.', this.actionLabel, this.onAction, this.inset = true})
      : title = null,
        icon = Icons.cloud_off_rounded,
        tone = StatusTone.warning;

  final String message;
  final String? title;
  final IconData? icon;
  final StatusTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// true = a rounded card inside the page gutters; false = full-bleed under an app bar.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = _toneColors(p, tone);
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s3, Space.s2, Space.s3),
      child: Row(
        children: [
          Icon(icon ?? Icons.info_outline_rounded, size: IconSizes.sm, color: fg),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) Text(title!, style: context.type.label.copyWith(color: fg)),
                Text(message, style: context.type.bodySmall.copyWith(color: fg)),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(minimumSize: const Size(Space.minTouch, Space.minTouch), foregroundColor: fg),
              child: Text(actionLabel!, style: context.type.label.copyWith(color: fg)),
            )
          else
            const SizedBox(width: Space.s2),
        ],
      ),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      child: inset
          ? DecoratedBox(decoration: BoxDecoration(color: bg, borderRadius: Radii.rMd), child: body)
          : ColoredBox(color: bg, child: body),
    );
  }
}

/// The standard "could not load" state: an [EmptyState] in the danger tone with a "Try again" action (G6.3, promoted from
/// the inventory screens' `InvErrorState`).
class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, required this.onRetry, this.title = 'Could not load'});
  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) =>
      EmptyState(icon: Icons.cloud_off_rounded, title: title, message: message, actionLabel: 'Try again', onAction: onRetry, tone: context.palette.danger);
}

/// The brand-ink headline card (the blueprint's `.hero`): a caption, one large figure and a line under it. Dark in both
/// modes ([AppPalette.heroStart] → [AppPalette.heroEnd]); [figure] is usually an `AmountText`.
class AppHero extends StatelessWidget {
  const AppHero({super.key, required this.caption, required this.figure, this.footnote, this.trailing, this.semanticLabel, this.child});
  final String caption;
  final Widget figure;
  final String? footnote;
  final Widget? trailing;
  final String? semanticLabel;

  /// Extra content under the footnote (e.g. a row of small figures).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final card = Container(
      padding: const EdgeInsets.all(Space.s5),
      decoration: BoxDecoration(
        borderRadius: Radii.rLg,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [p.heroStart, p.heroEnd]),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(caption, style: context.type.caption.copyWith(color: p.onHeroMuted))),
              ?trailing,
            ],
          ),
          const SizedBox(height: Space.s2),
          figure,
          if (footnote != null) ...[
            const SizedBox(height: Space.s2),
            Text(footnote!, style: context.type.bodySmall.copyWith(color: p.onHeroMuted)),
          ],
          if (child != null) ...[const SizedBox(height: Space.s4), child!],
        ],
      ),
    );
    if (semanticLabel == null) return card;
    return Semantics(container: true, label: semanticLabel, child: ExcludeSemantics(child: card));
  }
}
