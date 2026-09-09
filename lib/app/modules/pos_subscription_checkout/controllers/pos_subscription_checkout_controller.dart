import 'package:flutter/foundation.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum PosSubscriptionCheckoutUiState { webview, confirming, error }

/// Drives one hosted Stripe Checkout page through an in-app WebView —
/// mirrors the buyer app's `GatewayPaymentController`/`_openWebView`/
/// `_confirm` structure. A `NavigationDelegate` intercepts the success/
/// cancel return URLs (never actually loading them); on success it
/// bounded-polls `getStatus` until the purchase is confirmed active.
class PosSubscriptionCheckoutController extends GetxController {
  PosSubscriptionCheckoutController({PosSubscriptionRepository? repository})
      : _repo = repository ?? PosSubscriptionRepository();

  final PosSubscriptionRepository _repo;

  late final String _storeId;
  late final String _successUrl;
  late final String _cancelUrl;
  bool _resolved = false;

  final Rx<PosSubscriptionCheckoutUiState> uiState = PosSubscriptionCheckoutUiState.webview.obs;
  final RxString errorMessage = ''.obs;
  WebViewController? webViewController;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    final url = args['url'] as String? ?? '';
    _storeId = args['storeId'] as String? ?? '';
    _successUrl = args['successUrl'] as String? ?? '';
    _cancelUrl = args['cancelUrl'] as String? ?? '';
    _openWebView(url);
  }

  void _openWebView(String url) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url.startsWith(_successUrl)) {
              _onReturned();
              return NavigationDecision.prevent;
            }
            if (request.url.startsWith(_cancelUrl)) {
              _onCancelled();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    webViewController = controller;
  }

  void _onCancelled() {
    if (_resolved) return;
    _resolved = true;
    Get.back();
  }

  Future<void> _onReturned() async {
    if (_resolved) return;
    _resolved = true;
    await _confirm();
  }

  Future<void> _confirm() async {
    uiState.value = PosSubscriptionCheckoutUiState.confirming;

    // The purchase can report a transitional status briefly right after
    // redirect (webhook hasn't landed yet) — same bounded-poll shape as the
    // buyer app's GatewayPaymentController._confirm.
    for (var attempt = 0; attempt < 10; attempt++) {
      final status = await _repo.getStatus(_storeId);
      if (status.status.isEntitled) {
        Get.offAllNamed(Routes.posPinLogin);
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }

    uiState.value = PosSubscriptionCheckoutUiState.error;
    errorMessage.value = "We couldn't confirm your purchase yet. Please check back shortly.";
  }

  void retryConfirm() {
    _resolved = false;
    _onReturned();
  }

  // ── Test seams ────────────────────────────────────────────────────────────
  // The navigation-delegate closure that would normally invoke these lives
  // inside a real WebViewController, which needs platform channels no test
  // environment provides — same limitation the buyer app's
  // GatewayPaymentControllerTest also stops short of (it never fires
  // onNavigationRequest either). These let a test simulate that callback
  // firing without standing up a real WebView.
  @visibleForTesting
  void debugSimulateSuccessReturn() => _onReturned();

  @visibleForTesting
  void debugSimulateCancelReturn() => _onCancelled();

  /// Sets the args-derived state onInit would normally set, without going
  /// through `_openWebView` — constructing a real `WebViewController`
  /// requires platform channels no test environment provides.
  @visibleForTesting
  void debugSeed({required String storeId, required String successUrl, required String cancelUrl}) {
    _storeId = storeId;
    _successUrl = successUrl;
    _cancelUrl = cancelUrl;
  }
}
