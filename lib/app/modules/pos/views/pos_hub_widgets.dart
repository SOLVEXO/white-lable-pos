import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// One row of a hub list (Stock / More). Since G6.3 this is the design system's [AppListRow]; the name stays for the hubs.
class HubRow extends StatelessWidget {
  const HubRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.badge = 0, this.soon = false, this.locked = false});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final int badge;
  final bool soon;
  final bool locked;

  @override
  Widget build(BuildContext context) =>
      AppListRow(icon: icon, title: title, subtitle: subtitle, onTap: onTap, badge: badge, soon: soon, locked: locked, chevron: !soon);
}

/// A hub tab root — the design system's [AppTabPage].
class HubScaffold extends StatelessWidget {
  const HubScaffold({super.key, required this.title, required this.children, this.listKey});
  final String title;
  final List<Widget> children;
  final Key? listKey;

  @override
  Widget build(BuildContext context) => AppTabPage(title: title, listKey: listKey, children: children);
}

/// A titled group of hub rows — the design system's [AppSection].
class HubSection extends StatelessWidget {
  const HubSection(this.title, this.rows, {super.key});
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => AppSection(title, rows);
}
