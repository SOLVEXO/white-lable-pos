import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';
import 'app_button.dart';

/// Dialog helpers with a fade + soft scale entrance.
abstract final class AppDialog {
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    final themes = InheritedTheme.capture(
      from: context,
      to: Navigator.of(context, rootNavigator: true).context,
    );
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierLabel: 'Dismiss',
      barrierColor: context.palette.scrim,
      transitionDuration: Motion.of(context, Motion.slow),
      pageBuilder: (ctx, _, __) =>
          themes.wrap(SafeArea(child: Center(child: builder(ctx)))),
      transitionBuilder: (ctx, anim, _, child) {
        final c = CurvedAnimation(
          parent: anim,
          curve: Motion.emphasized,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(c),
            child: child,
          ),
        );
      },
    );
  }

  /// Confirm / cancel. Resolves `true` on confirm, `false` on cancel or dismiss.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool destructive = false,
  }) async {
    final r = await show<bool>(
      context,
      builder: (ctx) => AppDialogCard(
        title: title,
        message: message,
        actions: [
          AppButton(
            label: cancelLabel,
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          AppButton(
            label: confirmLabel,
            variant: destructive
                ? AppButtonVariant.danger
                : AppButtonVariant.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    return r ?? false;
  }
}

/// Dialog body: title, message / custom [content], and stacked-in-a-row actions.
class AppDialogCard extends StatelessWidget {
  const AppDialogCard({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const [],
  });
  final String title;
  final String? message;
  final Widget? content;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: title,
      child: Material(
        color: p.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rXl,
          side: BorderSide(color: p.border),
        ),
        elevation: 0,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(Space.s6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: context.type.title.copyWith(color: p.textPrimary),
                ),
                if (message != null) ...[
                  const SizedBox(height: Space.s2),
                  Text(
                    message!,
                    style: context.type.body.copyWith(color: p.textSecondary),
                  ),
                ],
                if (content != null) ...[
                  const SizedBox(height: Space.s4),
                  content!,
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: Space.s6),
                  context.isPhone && actions.length > 1
                      ? Column(
                          children: [
                            for (final a in actions.reversed)
                              Padding(
                                padding: const EdgeInsets.only(top: Space.s2),
                                child: a,
                              ),
                          ],
                        )
                      : Row(
                          children: [
                            for (var i = 0; i < actions.length; i++) ...[
                              if (i > 0) const SizedBox(width: Space.s3),
                              Expanded(child: actions[i]),
                            ],
                          ],
                        ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
