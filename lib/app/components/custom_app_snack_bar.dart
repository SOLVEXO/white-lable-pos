import 'package:flutter/material.dart';
import 'package:solvexo_pos/config/resources/app_sounds.dart';
import 'package:solvexo_pos/core/design/design.dart';
import 'package:solvexo_pos/utils/sound_util.dart';

/// Thin adapter over [AppToast] (design system). Same entry points as before
/// (`success` / `error` / `warning` / `show`) and the same sound cues; the
/// legacy colour/image parameters are accepted and ignored.
class CustomAppSnackbar {
  static void show({
    required String title,
    required String soundPath,
    required String message,
    String? imagePath,
    Color? textColor,
    Color? backgroundColor,
    Color? accentColor,
    String? actionLabel,
    VoidCallback? onAction,
    ToastType type = ToastType.info,
  }) {
    AppToast.show(message, type: type, title: title, actionLabel: actionLabel, onAction: onAction);
    SoundUtil.play(soundPath);
  }

  static void success(String message) => show(title: 'Success', message: message, type: ToastType.success, soundPath: AppSounds.iphoneSuccessSound);

  static void error(String message) => show(title: 'Error', message: message, type: ToastType.error, soundPath: AppSounds.errorSound);

  static void warning(String message) => show(title: 'Warning', message: message, type: ToastType.warning, soundPath: AppSounds.warningSound);
}
