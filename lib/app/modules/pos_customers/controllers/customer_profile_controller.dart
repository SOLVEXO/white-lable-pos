import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_customers/controllers/customer_common.dart';

/// One customer: balances, loyalty, recent sales; managers also get lifetime spend and the store-credit ledger and may adjust it.
/// Offline, the last remembered profile is shown ("as of …") and nothing that changes data is offered.
class CustomerProfileController extends GetxController {
  CustomerProfileController({required this.customerId, PosRepository? repository, CustomerCache? cache, String? storeId})
    : _repo = repository ?? PosRepository(),
      _cache = cache ?? CustomerCache.instance,
      _storeIdOverride = storeId;
  final String customerId;
  final PosRepository _repo;
  final CustomerCache _cache;
  final String? _storeIdOverride;

  final Rxn<CustomerProfile> profile = Rxn<CustomerProfile>();
  final RxBool loading = true.obs;
  final RxnString error = RxnString();
  final RxBool canManageHint = false.obs;
  final RxList<CreditEntry> ledger = <CreditEntry>[].obs;
  final RxBool ledgerLoading = false.obs;
  final RxnString ledgerError = RxnString();
  String storeId = '';

  /// Manager / owner: by role, or because the server sent lifetime spend (it only does for them).
  bool get canManage => canManageHint.value || profile.value?.lifetimeSpendMinor != null;

  @override
  void onInit() {
    super.onInit();
    customerGuessCanManage().then((v) => canManageHint.value = v);
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = null;
    try {
      storeId = await customerStoreId(_storeIdOverride);
      final p = await _repo.getCustomerProfile(storeId, customerId);
      if (p != null) {
        profile.value = p;
        await _cache.saveProfile(storeId, p);
        if (canManage) await loadLedger();
      } else if (_repo.lastErrorCode == null) {
        final cached = await _cache.loadProfile(storeId, customerId);
        if (cached != null) {
          profile.value = cached;
        } else {
          error.value = 'No internet, and this customer is not remembered on this till.';
        }
      } else {
        error.value = customerErrorMessage(_repo.lastErrorCode, fallback: 'Could not load this customer. Try again.');
      }
    } finally {
      loading.value = false;
    }
  }

  Future<void> loadLedger() async {
    ledgerLoading.value = true;
    ledgerError.value = null;
    try {
      final l = await _repo.getCustomerCredit(storeId, customerId);
      if (l == null) {
        ledgerError.value = customerErrorMessage(_repo.lastErrorCode, fallback: 'Could not load the credit history.');
      } else {
        ledger.assignAll(l.items);
      }
    } finally {
      ledgerLoading.value = false;
    }
  }

  /// A customer edit succeeded: show the new details at once.
  void applyEdit(PosCustomer c) {
    final p = profile.value;
    if (p == null) return;
    profile.value = CustomerProfile(
      customer: c.withBalances(creditBalanceMinor: p.creditBalanceMinor, loyaltyPoints: p.loyaltyPoints),
      cur: p.cur, creditBalanceMinor: p.creditBalanceMinor, lifetimeSpendMinor: p.lifetimeSpendMinor, loyaltyPoints: p.loyaltyPoints, orderCount: p.orderCount,
      loyaltyTier: p.loyaltyTier, loyalty: p.loyalty, lastVisitAt: p.lastVisitAt, recentSales: p.recentSales,
    );
  }
}
