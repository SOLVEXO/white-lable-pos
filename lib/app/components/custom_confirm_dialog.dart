import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// The app's standard confirm/cancel dialog, drawn on the design system
/// ([AppDialogCard] + [AppButton]): a title, either a plain `message` or a
/// custom `content` widget (e.g. a form field), a secondary cancel action and
/// a primary confirm action — the danger variant when [destructive] is set
/// (or, for older callers, when any [confirmColor] is passed: every existing
/// caller passes a red one for a destructive action).
///
/// Pops the dialog immediately on confirm, then invokes [onConfirm] — use
/// this for any action whose result is reported via a toast/snackbar rather
/// than an in-dialog loading state.
class CustomConfirmDialog extends StatelessWidget {
  final String title;
  final String? message;
  final Widget? content;
  final String confirmLabel;
  final String cancelLabel;

  /// Legacy: any non-null value means "destructive" (danger button). Prefer [destructive].
  final Color? confirmColor;
  final bool destructive;
  final VoidCallback? onConfirm;

  const CustomConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor,
    this.destructive = false,
    this.onConfirm,
  }) : assert(message != null || content != null, 'Provide either message or content');

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    String? message,
    WidgetBuilder? contentBuilder,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    Color? confirmColor,
    bool destructive = false,
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
  }) {
    return AppDialog.show<T>(
      context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => CustomConfirmDialog(
        title: title,
        message: message,
        content: contentBuilder?.call(ctx),
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmColor: confirmColor,
        destructive: destructive,
        onConfirm: onConfirm == null
            ? null
            : () {
                Navigator.pop(ctx);
                onConfirm();
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final danger = destructive || confirmColor != null;
    // Lift above the keyboard when the content holds a text field (AlertDialog did this for us before).
    return AnimatedPadding(
      duration: Motion.of(context, Motion.base),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        child: AppDialogCard(
          title: title,
          message: content == null ? message : null,
          content: content,
          actions: [
            AppButton(
              label: cancelLabel,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.pop(context),
            ),
            AppButton(
              label: confirmLabel,
              variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary,
              onPressed: onConfirm,
            ),
          ],
        ),
      ),
    );
  }
}
