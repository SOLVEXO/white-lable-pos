import 'package:solvexo_pos/app/data/repositories/auth_repository.dart';
import 'package:solvexo_pos/app/data/services/social_auth_service.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';

/// Entry point for the standalone POS app. Two fully-integrated ways in —
/// email/password and Google Sign-In — both hitting the same backend the
/// main Solvexo app uses, both always as role 'seller' (this app is
/// seller-only; see AuthRepository's doc comment for why that's forced
/// locally on every login regardless of what the server echoes back).
///
/// Either path then routes to [Routes.sellerStores], which sends a seller
/// with no store yet into [Routes.sellerOnboarding] to create one.
class PosLoginController extends GetxController {
  PosLoginController({AuthRepository? authRepository})
      : _authRepository = authRepository ?? AuthRepository();

  final AuthRepository _authRepository;
  final SocialAuthService _socialAuth = SocialAuthService();

  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  final RxBool obscurePassword = true.obs;
  final RxBool isEmailLoading = false.obs;
  final RxBool isGoogleLoading = false.obs;
  // True while checking for an already-saved session on launch — the view
  // shows a bare loading state instead of the form during this, so a
  // returning seller never sees a flash of the login screen.
  final RxBool isCheckingSession = true.obs;

  bool get isBusy => isEmailLoading.value || isGoogleLoading.value;

  @override
  void onInit() {
    super.onInit();
    _restoreSession();
  }

  /// The token IS saved correctly on every login (AuthRepository._persistAuth)
  /// — what was missing is this: `AppPages.initialRoute` always points at
  /// this screen regardless of whether a session already exists, so a
  /// returning seller looked "logged out" on every cold start even though
  /// nothing was ever lost. seller_stores/PosAccessMiddleware already
  /// self-heal if this token turns out to be expired (DioService's 401
  /// handling clears it and routes back here), so it's safe to just try.
  Future<void> _restoreSession() async {
    final token = await AppPreferences.getAccessTokenAsync();
    if (token != null && token.isNotEmpty) {
      Get.offAllNamed(Routes.sellerStores);
      return;
    }
    isCheckingSession.value = false;
  }

  void toggleObscurePassword() => obscurePassword.value = !obscurePassword.value;

  Future<void> loginWithEmail() async {
    if (isBusy) return;

    final email = emailController.text.trim();
    final password = passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ToastUtil.showToast('Please enter your email and password');
      return;
    }

    isEmailLoading.value = true;
    try {
      final auth = await _authRepository.login(email: email, password: password);
      if (auth == null) {
        // AuthRepository already surfaced its own error toast.
        return;
      }
      Get.offAllNamed(Routes.sellerStores);
    } finally {
      isEmailLoading.value = false;
    }
  }

  Future<void> continueWithGoogle() async {
    if (isBusy) return;
    isGoogleLoading.value = true;
    try {
      final dto = await _socialAuth.signInWithGoogle();
      if (dto == null) {
        // User cancelled — no error to show.
        return;
      }

      final auth = await _authRepository.socialLogin(dto);
      if (auth == null) {
        ToastUtil.showToast('Google sign in failed. Please try again.');
        return;
      }

      Get.offAllNamed(Routes.sellerStores);
    } catch (e) {
      debugPrint('❌ Google sign in error: $e');
      ToastUtil.showToast('Google sign in failed. Please try again.');
    } finally {
      isGoogleLoading.value = false;
    }
  }

  @override
  void onClose() {
    emailController.dispose();
    passwordController.dispose();
    super.onClose();
  }
}
