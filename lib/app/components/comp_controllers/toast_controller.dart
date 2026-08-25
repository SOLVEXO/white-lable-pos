import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ToastControllerX extends GetxController
    with GetSingleTickerProviderStateMixin {
  late AnimationController animationController;
  late Animation<double> fade;
  late Animation<Offset> slide;

  @override
  void onInit() {
    super.onInit();

    animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    fade = CurvedAnimation(parent: animationController, curve: Curves.easeIn);

    slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: animationController, curve: Curves.easeOut),
        );

    animationController.forward();
  }

  @override
  void onClose() {
    animationController.dispose();
    super.onClose();
  }
}
