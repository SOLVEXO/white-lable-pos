import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One row of a hub list (Stock / More): icon, title, subtitle, optional badge, chevron. A [soon] row is a visible but disabled
/// placeholder — hubs only pass those to managers / owners, never to cashiers.
class HubRow extends StatelessWidget {
  const HubRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.badge = 0,
    this.soon = false,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final int badge;
  final bool soon;

  /// Opens behind the owner gate / manager PIN (a small lock tells the user before they tap).
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      onTap: soon ? null : onTap,
      semanticLabel: [
        title,
        if (subtitle != null) subtitle!,
        if (soon) 'coming soon',
        if (locked) 'needs owner access',
        if (badge > 0) '$badge need attention',
      ].join('. '),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: soon ? p.fill : p.accentSoft,
              borderRadius: Radii.rMd,
            ),
            child: Icon(icon, size: 22, color: soon ? p.textMuted : p.accentFg),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.type.subtitle.copyWith(
                    color: soon ? p.textMuted : p.textPrimary,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: context.type.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (soon) const StatusBadge('Soon', tone: StatusTone.neutral),
          if (badge > 0) StatusBadge('$badge', tone: StatusTone.warning),
          if (locked && !soon)
            Padding(
              padding: const EdgeInsets.only(left: Space.s2),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: p.textMuted,
              ),
            ),
          if (!soon) Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ],
      ),
    );
  }
}

class HubScaffold extends StatelessWidget {
  const HubScaffold({
    super.key,
    required this.title,
    required this.children,
    this.listKey,
  });
  final String title;
  final List<Widget> children;
  final Key? listKey;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // dark icons on the light theme, light icons on the dark one (without this the clock is white on cream)
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: ListView(
            key: listKey,
            padding: const EdgeInsets.fromLTRB(
              Space.s4,
              Space.s4,
              Space.s4,
              Space.s8,
            ),
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: context.type.headline.copyWith(color: p.textPrimary),
                ),
              ),
              const SizedBox(height: Space.s4),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class HubSection extends StatelessWidget {
  const HubSection(this.title, this.rows, {super.key});
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            rows[i],
          ],
        ],
      ),
    );
  }
}
