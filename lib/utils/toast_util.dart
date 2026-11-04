import 'package:flutter/material.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// Thin adapter over [AppToast] (design system). Kept so existing call sites
/// compile unchanged. The legacy visual params (`imagePath`, `bgColor`,
/// `textColor`) are accepted and ignored — pass [type] to pick the tone.
class ToastUtil {
  static void showToast(
    String message, {
    String? imagePath,
    Color? bgColor,
    Color? textColor,
    ToastType type = ToastType.info,
    Duration duration = const Duration(seconds: 2),
  }) {
    AppToast.show(message, type: type, duration: duration, position: ToastPosition.bottom);
  }
}
