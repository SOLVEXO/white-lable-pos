import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';

/// Runs the splash animation and the session check IN PARALLEL and navigates the
/// moment both are done — no fixed delay. The animation is 1.0 s (200 ms under
/// reduced motion); the session check is a handful of cached preference reads, so
/// in practice the animation is the longer of the two.
class SplashScreenController extends GetxController
    with GetSingleTickerProviderStateMixin {
  /// 0 → 1 over the splash timeline; the view derives every motion from it.
  late final AnimationController animation;

  static const Duration fullDuration = Duration(milliseconds: 1000);
  static const Duration reducedDuration = Duration(milliseconds: 200);

  bool _animationDone = false;
  String? _target;
  bool _navigated = false;

  @override
  void onInit() {
    super.onInit();
    animation = AnimationController(vsync: this, duration: fullDuration);
    // Session check starts immediately, alongside the animation.
    _resolveRoute().then((route) {
      _target = route;
      _tryNavigate();
    });
  }

  /// Called by the view once its first frame is up (it knows about reduced motion).
  void start({required bool reducedMotion}) {
    animation.duration = reducedMotion ? reducedDuration : fullDuration;
    animation.forward().whenComplete(() {
      _animationDone = true;
      _tryNavigate();
    });
  }

  void _tryNavigate() {
    if (_navigated || !_animationDone || _target == null) return;
    _navigated = true;
    Get.offAllNamed(_target!);
  }

  /// The routing decision — branch for branch what the splash always did.
  Future<String> _resolveRoute() async {
    final hasSeenOnboarding = await AppPreferences.getHasSeenOnboarding();
    if (!hasSeenOnboarding) {
      return Routes.onboarding;
    }

    // Returning device — a valid seller session skips straight past login;
    // otherwise land on the normal POS login screen.
    final token = await AppPreferences.getAccessTokenAsync();
    if (token != null && token.isNotEmpty) {
      // A registered terminal goes straight to the staff PIN screen (or its running shift); the owner's management
      // area is behind the owner gate.
      if (AppPreferences.cachedDeviceMode) {
        return AppPreferences.cachedHasPosSession
            ? Routes.posHome
            : Routes.posPinLogin;
      }
      return Routes.sellerHome;
    }
    return Routes.posLogin;
  }

  @override
  void onClose() {
    animation.dispose();
    super.onClose();
  }
}
