import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'app_card.dart';

/// KPI tile with an animated count-up. [formatter] turns the (animating) number
/// into display text — pass `Money.format` for currency. Display only; the
/// number you pass in is shown as given, never recomputed here.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.formatter,
    this.icon,
    this.delta,
    this.deltaPositive,
    this.onTap,
  });
  final String label;
  final double value;
  final String Function(double) formatter;
  final IconData? icon;

  /// Small trend caption, e.g. "+12% vs yesterday".
  final String? delta;
  final bool? deltaPositive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final deltaColor = deltaPositive == null
        ? p.textMuted
        : (deltaPositive! ? p.successFg : p.dangerFg);
    return AppCard(
      onTap: onTap,
      semanticLabel:
          '$label ${formatter(value)}${delta == null ? '' : ', $delta'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: p.accentSoft,
                    borderRadius: Radii.rSm,
                  ),
                  child: Icon(icon, size: 18, color: p.accentFg),
                ),
                const SizedBox(width: Space.s2),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.label.copyWith(color: p.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value),
            duration: Motion.of(context, Motion.slower),
            curve: Motion.emphasized,
            builder: (context, v, _) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                formatter(v),
                maxLines: 1,
                style: context.type.amountLg.copyWith(color: p.textPrimary),
              ),
            ),
          ),
          if (delta != null) ...[
            const SizedBox(height: Space.s1),
            Text(
              delta!,
              style: context.type.caption.copyWith(
                color: deltaColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
