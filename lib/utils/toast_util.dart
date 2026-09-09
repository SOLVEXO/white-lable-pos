import 'package:solvexo_pos/app/components/comp_controllers/toast_controller.dart';
import 'package:solvexo_pos/app/components/custom_toast.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ToastUtil {
  static void showToast(
    String message, {
    String? imagePath,
    Color bgColor = AppColors.black2,
    Color textColor = AppColors.white,
    Duration duration = const Duration(seconds: 2),
  }) {
    final context = Get.overlayContext;
    if (context == null) return;

    final overlay = Overlay.of(context);

    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 80,
        left: 0,
        right: 0,
        child: Center(
          child: CustomToast(
            message: message,
            imagePath: imagePath,
            bgColor: bgColor,
            textColor: textColor,
          ),
        ),
      ),
    );

    overlay.insert(entry);

    Future.delayed(duration, () {
      entry.remove();
      Get.delete<ToastControllerX>(); // clean controller
    });
  }

  // static Future<void> showToast(String message) async {
  //   await Fluttertoast.showToast(
  //       msg: message,
  //       // toastLength: Toast.LENGTH_SHORT,
  //       // gravity: ToastGravity.CENTER,
  //       timeInSecForIosWeb: 1,
  //       // backgroundColor: A.red,
  //       // textColor: AppColors.white,
  //       fontSize: 14.0);
  // }
}
