import 'package:solvexo_pos/app/data/models/pos/pos_plan_model.dart';
import 'package:solvexo_pos/app/data/repositories/pos_subscription_repository.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';
import 'package:solvexo_pos/app/routes/app_pages.dart';
import 'package:get/get.dart';

enum PosSubscriptionPaywallUiState { loading, empty, ready, processing, error }

/// Shown in place of the POS terminal for a store with no active plan
/// purchase (`none`) or a lapsed one (`expired`) — lets the seller pick one
/// of the admin-authored plans and pay once via Stripe Checkout. There's no
/// billing-portal path: a fixed-term one-time purchase has nothing to
/// manage between purchases, just a new one to make.
class PosSubscriptionPaywallController extends GetxController {
  PosSubscriptionPaywallController({PosSubscriptionRepository? repository})
      : _repo = repository ?? PosSubscriptionRepository();

  final PosSubscriptionRepository _repo;

  late final String storeId;
  late final String storeName;
  late final bool isExpired;
  late final String? expiresAt;

  final Rx<PosSubscriptionPaywallUiState> uiState = PosSubscriptionPaywallUiState.loading.obs;
  final RxList<PosPlanModel> plans = <PosPlanModel>[].obs;
  final Rx<PosPlanModel?> selectedPlan = Rx(null);
  final RxString errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments as Map<String, dynamic>? ?? {};
    storeId = args['storeId'] as String? ?? '';
    storeName = args['storeName'] as String? ?? 'this store';
    isExpired = args['isExpired'] as bool? ?? false;
    expiresAt = args['expiresAt'] as String?;
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    uiState.value = PosSubscriptionPaywallUiState.loading;
    if (storeId.isEmpty) {
      uiState.value = PosSubscriptionPaywallUiState.error;
      errorMessage.value = 'No store selected.';
      return;
    }
    final result = await _repo.getPlans();
    plans.assignAll(result);
    uiState.value = plans.isEmpty ? PosSubscriptionPaywallUiState.empty : PosSubscriptionPaywallUiState.ready;
  }

  Future<void> retryLoad() => _loadPlans();

  void selectPlan(PosPlanModel plan) => selectedPlan.value = plan;

  /// Starts a Stripe Checkout session for the selected plan — a fresh
  /// one-time purchase, whether this store never had one (`none`) or its
  /// last one expired.
  Future<void> confirm() async {
    final plan = selectedPlan.value;
    if (storeId.isEmpty || plan == null) return;
    uiState.value = PosSubscriptionPaywallUiState.processing;

    final successUrl = '${ApiConstants.baseUrl}/pos-subscription-return/success';
    final cancelUrl = '${ApiConstants.baseUrl}/pos-subscription-return/cancel';

    final url = await _repo.createCheckoutSession(
      storeId,
      planId: plan.id,
      successUrl: successUrl,
      cancelUrl: cancelUrl,
    );

    if (url == null) {
      uiState.value = PosSubscriptionPaywallUiState.ready;
      errorMessage.value = 'Could not start checkout. Please try again.';
      return;
    }

    uiState.value = PosSubscriptionPaywallUiState.ready;
    await Get.toNamed(
      Routes.posSubscriptionCheckout,
      arguments: {
        'url': url,
        'storeId': storeId,
        'successUrl': successUrl,
        'cancelUrl': cancelUrl,
      },
    );
  }
}
