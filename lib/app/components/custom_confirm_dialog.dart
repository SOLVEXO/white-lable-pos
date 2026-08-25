import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:solvexo_pos/utils/dimens.dart';
import 'package:flutter/material.dart';

/// The app's standard confirm/cancel dialog: a `CustomText` title, either a
/// plain `message` or a custom `content` widget (e.g. a form field), a plain
/// `TextButton` cancel action, and a colored pill confirm action — matching
/// the destructive-action pattern already used across the app (see
/// EditProductDangerZone's delete-product dialog).
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
  final Color? confirmColor;
  final VoidCallback? onConfirm;

  const CustomConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.confirmLabel = 'Confirm',
    this.cancelLabel = 'Cancel',
    this.confirmColor,
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
    VoidCallback? onConfirm,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => CustomConfirmDialog(
        title: title,
        message: message,
        content: contentBuilder?.call(ctx),
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        confirmColor: confirmColor,
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
    return AlertDialog(
      backgroundColor: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppDimen.dialogRadius)),
      title: CustomText(
        text: title,
        fontSize: AppFontSize.small,
        fontWeight: FontWeight.bold,
        color: AppColors.black,
      ),
      content: content ??
          CustomText(
            text: message!,
            fontSize: AppFontSize.verySmall,
            color: AppColors.grey,
          ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: CustomText(text: cancelLabel, fontSize: AppFontSize.verySmall, color: AppColors.grey),
        ),
        GestureDetector(
          onTap: onConfirm,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: confirmColor ?? AppColors.primaryColor,
              borderRadius: BorderRadius.circular(AppDimen.borderRadius),
            ),
            child: CustomText(
              text: confirmLabel,
              fontSize: AppFontSize.verySmall,
              fontWeight: FontWeight.w600,
              color: AppColors.white,
            ),
          ),
        ),
      ],
    );
  }
}
