import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

/// Icon medallion + headline + supporting lines: the shared "PIN gate" look used
/// by the PIN login, the auto-lock screen and the owner gate.
class GateHeader extends StatelessWidget {
  const GateHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.footnote,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: p.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 30, color: p.accentFg),
        ),
        const SizedBox(height: Space.s4),
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: context.type.headline.copyWith(color: p.textPrimary),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Space.s2),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: context.type.body.copyWith(color: p.textSecondary),
          ),
        ],
        if (footnote != null) ...[
          const SizedBox(height: Space.s1),
          Text(
            footnote!,
            textAlign: TextAlign.center,
            style: context.type.caption.copyWith(color: p.textMuted),
          ),
        ],
      ],
    );
  }
}
