import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.only(bottom: Space.s3),
  });
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: context.type.title.copyWith(color: p.textPrimary),
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.type.bodySmall.copyWith(color: p.textMuted),
                  ),
              ],
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(Space.minTouch, Space.minTouch),
                foregroundColor: p.accentFg,
              ),
              child: Text(
                actionLabel!,
                style: context.type.label.copyWith(color: p.accentFg),
              ),
            ),
        ],
      ),
    );
  }
}
