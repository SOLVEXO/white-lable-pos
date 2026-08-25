import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:solvexo_pos/utils/app_font_size.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';

class CustomAlertDialogUtil {
  final String label;
  final VoidCallback? onPressed;
  final bool isDefault;
  final bool isDestructive;
  final Color? color;

  CustomAlertDialogUtil({
    required this.label,
    this.onPressed,
    this.isDefault = false,
    this.isDestructive = false,
    this.color,
  });
}

Future<void> showCustomDialog({
  required String title,
  required String content,
  List<CustomAlertDialogUtil>? options,
  VoidCallback? onRightButtonTap,
  VoidCallback? onLeftButtonTap,
  String rightButtonName = 'Delete',
  String leftButtonName = 'Cancel',
  bool isDestructive = true,
  bool requireDeleteConfirmation = false,
}) async {
  final context = Get.context;
  if (context == null) return;

  final TextEditingController textController = TextEditingController();
  bool isValid = !requireDeleteConfirmation;

  await showCupertinoDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return CupertinoAlertDialog(
            title: CustomText(
              text: title,
              fontWeight: FontWeight.w500,
              fontSize: AppFontSize.medium,
              textAlign: TextAlign.center,
            ),
            content: Column(
              children: [
                const SizedBox(height: 8),
                CustomText(
                  text: content,
                  fontSize: AppFontSize.small2,
                  textAlign: TextAlign.center,
                ),
                if (requireDeleteConfirmation) ...[
                  const SizedBox(height: 12),
                  CupertinoTextField(
                    controller: textController,
                    placeholder: 'Type "DELETE"',
                    onChanged: (val) {
                      setState(() {
                        isValid = val.trim().toUpperCase() == 'DELETE';
                      });
                    },
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                    style: TextStyle(fontSize: AppFontSize.small2),
                    placeholderStyle: TextStyle(
                      color: AppColors.grey,
                      fontSize: AppFontSize.small2,
                    ),
                    decoration: null,
                  ),
                ],
              ],
            ),
            actions: options?.isNotEmpty == true
                ? options!
                      .map(
                        (option) => CupertinoDialogAction(
                          isDefaultAction: option.isDefault,
                          isDestructiveAction: option.isDestructive,
                          onPressed: () {
                            Get.back();
                            option.onPressed?.call();
                          },
                          child: CustomText(
                            text: option.label,
                            fontSize: AppFontSize.small,
                            color:
                                option.color ??
                                (option.isDestructive
                                    ? AppColors.red
                                    : AppColors.lightBlue),
                          ),
                        ),
                      )
                      .toList()
                : [
                    CupertinoDialogAction(
                      onPressed: () {
                        Get.back(result: 'cancel');
                        onLeftButtonTap?.call();
                      },
                      child: CustomText(
                        text: leftButtonName,
                        fontSize: AppFontSize.small,
                        color: AppColors.grey,
                      ),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: isDestructive,
                      onPressed: isValid
                          ? () {
                              Get.back(result: 'confirm');
                              onRightButtonTap?.call();
                            }
                          : null,
                      child: CustomText(
                        text: rightButtonName,
                        fontSize: AppFontSize.small,
                        color: AppColors.accentColor,
                      ),
                    ),
                  ],
          );
        },
      );
    },
  );
}
