import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'breakpoints.dart';

class AppDestination {
  const AppDestination({
    required this.icon,
    required this.label,
    this.selectedIcon,
    this.badge = 0,
  });
  final IconData icon;
  final IconData? selectedIcon;
  final String label;

  /// 0 = no badge.
  final int badge;
}

/// The one responsive navigation shell: bottom bar on phones, a collapsible
/// rail on tablets / large screens. It only renders chrome — the caller owns the
/// selected index and decides what [body] is (e.g. an `IndexedStack` to keep tab
/// state). [topBanner] sits above the body on every size (offline / restricted
/// banners).
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.body,
    this.topBanner,
    this.railHeader,
    this.railFooter,
  });

  final List<AppDestination> destinations;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final Widget? topBanner;

  /// Brand slot at the top of the rail; receives whether the rail is expanded.
  final Widget Function(bool extended)? railHeader;
  final Widget Function(bool extended)? railFooter;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  bool? _userExtended;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screen = context.screen;
    final content = Column(
      children: [
        if (widget.topBanner != null) widget.topBanner!,
        Expanded(child: widget.body),
      ],
    );

    if (screen.isPhone) {
      return Scaffold(
        backgroundColor: p.background,
        body: content,
        bottomNavigationBar: _BottomBar(
          destinations: widget.destinations,
          index: widget.currentIndex,
          onTap: widget.onDestinationSelected,
        ),
      );
    }

    final extended = _userExtended ?? (screen == ScreenClass.large);
    return Scaffold(
      backgroundColor: p.background,
      body: Row(
        children: [
          _Rail(
            destinations: widget.destinations,
            index: widget.currentIndex,
            onTap: widget.onDestinationSelected,
            extended: extended,
            onToggle: () => setState(() => _userExtended = !extended),
            header: widget.railHeader,
            footer: widget.railFooter,
          ),
          VerticalDivider(width: 1, color: p.border),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.destinations,
    required this.index,
    required this.onTap,
  });
  final List<AppDestination> destinations;
  final int index;
  final ValueChanged<int> onTap;

  static const double _pillW = 64;
  static const double _pillH = 32;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth / destinations.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: Motion.of(context, Motion.slow),
                    curve: Motion.emphasized,
                    left: index * w + (w - _pillW) / 2,
                    top: 10,
                    width: _pillW,
                    height: _pillH,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: p.accentSoft,
                        borderRadius: Radii.rFull,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < destinations.length; i++)
                        Expanded(
                          child: _BarItem(
                            d: destinations[i],
                            selected: i == index,
                            onTap: () => onTap(i),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.d,
    required this.selected,
    required this.onTap,
  });
  final AppDestination d;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accentFg : p.textMuted;
    return Semantics(
      button: true,
      selected: selected,
      label: d.badge > 0 ? '${d.label}, ${d.badge} new' : d.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.rLg,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Icon(
                    selected ? (d.selectedIcon ?? d.icon) : d.icon,
                    size: 24,
                    color: color,
                  ),
                  if (d.badge > 0)
                    Positioned(top: 0, right: -14, child: _Badge(d.badge)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              d.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.caption.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.destinations,
    required this.index,
    required this.onTap,
    required this.extended,
    required this.onToggle,
    this.header,
    this.footer,
  });
  final List<AppDestination> destinations;
  final int index;
  final ValueChanged<int> onTap;
  final bool extended;
  final VoidCallback onToggle;
  final Widget Function(bool extended)? header;
  final Widget Function(bool extended)? footer;

  static const double _collapsed = 76;
  static const double _expanded = 232;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.slow),
      curve: Motion.emphasized,
      width: extended ? _expanded : _collapsed,
      color: p.surface,
      child: SafeArea(
        right: false,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            maxWidth: _expanded,
            child: SizedBox(
              width: _expanded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: Space.s3),
                  if (header != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                      child: header!(extended),
                    ),
                  const SizedBox(height: Space.s3),
                  for (var i = 0; i < destinations.length; i++)
                    _RailItem(
                      d: destinations[i],
                      selected: i == index,
                      extended: extended,
                      onTap: () => onTap(i),
                    ),
                  const Spacer(),
                  if (footer != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                      child: footer!(extended),
                    ),
                  _RailItem(
                    d: AppDestination(
                      icon: extended
                          ? Icons.chevron_left_rounded
                          : Icons.chevron_right_rounded,
                      label: 'Collapse',
                    ),
                    selected: false,
                    extended: extended,
                    onTap: onToggle,
                    semanticLabel: extended
                        ? 'Collapse navigation'
                        : 'Expand navigation',
                  ),
                  const SizedBox(height: Space.s3),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.d,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.semanticLabel,
  });
  final AppDestination d;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = selected ? p.accentFg : p.textSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.s3, vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel ?? d.label,
        excludeSemantics: true,
        child: Material(
          color: selected ? p.accentSoft : Colors.transparent,
          borderRadius: Radii.rMd,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: Space.minTouch + 4,
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          selected ? (d.selectedIcon ?? d.icon) : d.icon,
                          size: 24,
                          color: color,
                        ),
                        if (d.badge > 0)
                          Positioned(top: 8, right: 8, child: _Badge(d.badge)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AnimatedOpacity(
                      opacity: extended ? 1 : 0,
                      duration: Motion.of(context, Motion.base),
                      child: Text(
                        d.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: context.type.label.copyWith(
                          color: color,
                          fontSize: context.type.body.fontSize,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: p.danger, borderRadius: Radii.rFull),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: context.type.caption.copyWith(
          fontSize: 10,
          color: p.onDanger,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
