import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/palette.dart';
import '../tokens/tokens.dart';
import 'app_button.dart';

/// Empty / error placeholder with optional action (e.g. "Retry").
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.tone,
  });
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Icon tint; defaults to the accent. Use danger for error states.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = tone ?? p.accentFg;
    // Scrolls (rather than overflows) when dropped into a short container.
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: box.hasBoundedHeight ? box.maxHeight : 0,
            minWidth: box.maxWidth,
          ),
          child: Center(child: _body(context, p, c)),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AppPalette p, Color c) {
    return Padding(
      padding: const EdgeInsets.all(Space.s8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.of(context, Motion.slower),
          curve: Motion.emphasized,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * 12),
              child: child,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: c),
              ),
              const SizedBox(height: Space.s5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.type.title.copyWith(color: p.textPrimary),
              ),
              if (message != null) ...[
                const SizedBox(height: Space.s2),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.type.body.copyWith(color: p.textSecondary),
                ),
              ],
              if (actionLabel != null) ...[
                const SizedBox(height: Space.s6),
                AppButton(
                  label: actionLabel!,
                  onPressed: onAction,
                  expand: false,
                  variant: AppButtonVariant.secondary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
