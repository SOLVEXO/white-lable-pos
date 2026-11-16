import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'section_header.dart';

/// The page frame every pushed screen uses (G6.3, promoted from the inventory screens' `InvScaffold`): a flat app bar on the
/// page background, a safe area, and a width cap so a tablet is not a stretched phone. Tab roots use [AppTabPage] instead.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.title, required this.body, this.maxWidth = 720, this.actions, this.bottom, this.floatingAction, this.banner});
  final String title;
  final Widget body;

  /// Content width cap on wide screens (720 for lists and forms; pass a larger value for two-column tablet layouts).
  final double maxWidth;
  final List<Widget>? actions;

  /// Sticky footer (e.g. the primary action of a form), drawn above the safe area.
  final Widget? bottom;
  final Widget? floatingAction;

  /// A full-width notice under the app bar (offline, older server, plan) — an [AppBanner].
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: Text(title), backgroundColor: p.background, foregroundColor: p.textPrimary, elevation: 0, actions: actions),
      floatingActionButton: floatingAction,
      body: SafeArea(
        child: Column(
          children: [
            ?banner,
            Expanded(
              child: Center(
                child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: body),
              ),
            ),
            if (bottom != null)
              Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Padding(padding: const EdgeInsets.fromLTRB(Space.s4, Space.s2, Space.s4, Space.s3), child: bottom),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tab root (Home, Stock, More): no back button, a large page title, a scrolling list with the standard gutters
/// (promoted from the hubs' `HubScaffold`).
class AppTabPage extends StatelessWidget {
  const AppTabPage({super.key, required this.title, required this.children, this.listKey, this.subtitle, this.trailing, this.onRefresh});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final Key? listKey;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final list = ListView(
      key: listKey,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s4, Space.s4, Space.s8),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text(title, style: context.type.headline.copyWith(color: p.textPrimary))),
                  if (subtitle != null) ...[
                    const SizedBox(height: Space.s1),
                    Text(subtitle!, style: context.type.bodySmall.copyWith(color: p.textSecondary)),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: Space.s4),
        ...children,
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // dark status-bar icons on the light theme, light ones on the dark theme
      value: p.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(child: onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list)),
      ),
    );
  }
}

/// A titled group of rows with the standard spacing (hidden when it has no rows).
class AppSection extends StatelessWidget {
  const AppSection(this.title, this.rows, {super.key, this.action, this.onAction});
  final String title;
  final List<Widget> rows;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title, actionLabel: action, onAction: onAction),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: Space.s2),
            rows[i],
          ],
        ],
      ),
    );
  }
}
