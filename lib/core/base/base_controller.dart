import 'package:solvexo_pos/core/base/base_state.dart';
import 'package:solvexo_pos/core/theme/base_colors.dart';
import 'package:solvexo_pos/core/theme/base_spacing.dart';
import 'package:solvexo_pos/app/network/dio_exception_handler.dart';
import 'package:solvexo_pos/shared_prefrences/app_prefrences.dart';
import 'package:solvexo_pos/utils/toast_util.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Shared behaviour for every redesigned screen's controller — feedback
/// (toasts/snackbars/dialogs/bottom sheets), a generic [BaseViewState] for
/// [BaseView] to render against, API-error handling that funnels into the
/// existing [DioExceptionHandler], and simple pagination bookkeeping.
///
/// Existing controllers keep working unchanged: this is purely additive
/// (e.g. `MyOrdersController extends BaseController` already worked before
/// this rewrite and still does — none of its overridden members changed
/// shape, only grew new ones alongside).
abstract class BaseController extends GetxController {
  // ── Generic view state ─────────────────────────────────────────────────
  final Rx<BaseViewState> viewState = BaseViewState.idle.obs;
  final RxBool isLoading = false.obs;
  final RxString errorMessage = ''.obs;

  bool get isBusy => isLoading.value;

  // ── Pagination ──────────────────────────────────────────────────────────
  final RxInt currentPage = 1.obs;
  final RxBool hasMorePages = true.obs;
  final RxBool isLoadingMore = false.obs;

  void resetPagination() {
    currentPage.value = 1;
    hasMorePages.value = true;
    isLoadingMore.value = false;
  }

  // ── Loading ─────────────────────────────────────────────────────────────
  void showLoading() {
    isLoading.value = true;
    viewState.value = BaseViewState.loading;
  }

  void hideLoading() {
    isLoading.value = false;
    if (viewState.value == BaseViewState.loading) viewState.value = BaseViewState.idle;
  }

  // ── Toasts / snackbars ────────────────────────────────────────────────────
  void showToast(String message) => ToastUtil.showToast(message);

  void showSuccess(String message) => ToastUtil.showToast(message, bgColor: BaseColors.success);

  void showError(String message) => ToastUtil.showToast(message, bgColor: BaseColors.danger);

  void showWarning(String message) => ToastUtil.showToast(message, bgColor: BaseColors.warning);

  void showSnackbar(String title, String message, {Color? backgroundColor}) {
    Get.snackbar(
      title,
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: backgroundColor ?? BaseColors.onSurfaceLight,
      colorText: Colors.white,
      margin: const EdgeInsets.all(12),
      borderRadius: BaseRadius.md,
    );
  }

  // ── Dialogs / bottom sheets ────────────────────────────────────────────────
  Future<T?> showAppDialog<T>(Widget dialog, {bool barrierDismissible = true}) =>
      Get.dialog<T>(dialog, barrierDismissible: barrierDismissible);

  Future<T?> showAppBottomSheet<T>(Widget sheet, {bool isScrollControlled = true}) => Get.bottomSheet<T>(
        sheet,
        isScrollControlled: isScrollControlled,
        backgroundColor: Colors.transparent,
      );

  void dismissKeyboard() {
    final context = Get.context;
    if (context != null) FocusScope.of(context).unfocus();
  }

  // ── Navigation ──────────────────────────────────────────────────────────
  void navigate(String route, {dynamic arguments}) => Get.toNamed(route, arguments: arguments);
  void navigateAndReplace(String route, {dynamic arguments}) => Get.offNamed(route, arguments: arguments);
  void goBack<T>([T? result]) => Get.back<T>(result: result);

  // ── API error handling ──────────────────────────────────────────────────
  void handleApiError(Object error, {String fallbackMessage = 'Something went wrong. Please try again.'}) {
    viewState.value = BaseViewState.error;
    if (error is DioException) {
      errorMessage.value = fallbackMessage;
      DioExceptionHandler.handleDioException(error);
    } else {
      errorMessage.value = fallbackMessage;
      showError(fallbackMessage);
    }
  }

  // ── Logging ─────────────────────────────────────────────────────────────
  void logger(String message, {String tag = 'APP'}) => debugPrint('🪵 [$tag] $message');

  // ── Common validations ────────────────────────────────────────────────────
  String? validateRequired(String? value, {String field = 'This field'}) =>
      (value == null || value.trim().isEmpty) ? '$field is required' : null;

  String? validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
    return regex.hasMatch(value.trim()) ? null : 'Enter a valid email address';
  }

  String? validatePassword(String? value, {int minLength = 6}) {
    if (value == null || value.isEmpty) return 'Password is required';
    return value.length < minLength ? 'Password must be at least $minLength characters' : null;
  }

  // ── Legacy compatibility ───────────────────────────────────────────────
  // Pre-existing members kept as-is so any controller already relying on
  // them (directly or via `super.onInit()`) keeps behaving identically.
  String? userId;
  final RxBool loginUser = false.obs;

  Future<bool> isUserLogin() async {
    userId = await AppPreferences.getUserId();
    loginUser.value = userId != null && userId!.isNotEmpty;
    return loginUser.value;
  }

  @override
  void onInit() {
    super.onInit();
    isUserLogin();
  }
}
