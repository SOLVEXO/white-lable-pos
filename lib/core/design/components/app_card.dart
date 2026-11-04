import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'press_scale.dart';

/// Surface container: surface fill, hairline border, soft shadow. Pass [onTap]
/// to make it a pressable card.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Space.s4),
    this.onTap,
    this.color,
    this.raised = false,
    this.radius = Radii.rLg,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool raised;
  final BorderRadius radius;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (raised ? p.surfaceRaised : p.surface),
        borderRadius: radius,
        border: Border.all(color: p.border),
        boxShadow: raised ? context.raisedShadow : context.softShadow,
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: radius,
                onTap: onTap,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
    final wrapped = onTap == null
        ? decorated
        : PressScale(scale: 0.985, child: decorated);
    return semanticLabel == null
        ? wrapped
        : Semantics(label: semanticLabel, container: true, child: wrapped);
  }
}
