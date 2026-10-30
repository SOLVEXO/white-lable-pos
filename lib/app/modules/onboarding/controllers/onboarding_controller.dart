import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/config/onboarding_content.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class OnboardingController extends GetxController {
  final PageController pageController = PageController();
  final RxInt currentPage = 0.obs;

  final List<OnboardingSlideContent> slides = onboardingSlides;

  int get slideCount => slides.length;
  bool get isLastPage => currentPage.value == slideCount - 1;

  void onPageChanged(int index) => currentPage.value = index;

  void next() {
    if (isLastPage) {
      finish();
      return;
    }
    pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void skip() => finish();

  Future<void> finish() async {
    await AppPreferences.setHasSeenOnboarding(true);
    Get.offAllNamed(Routes.posLogin);
  }

  @override
  void onClose() {
    pageController.dispose();
    super.onClose();
  }
}
