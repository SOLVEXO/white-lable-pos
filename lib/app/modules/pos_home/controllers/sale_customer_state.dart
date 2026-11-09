import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/utils/money.dart';

/// G3.3: the customer attached to the sale in progress, with the facts the payment sheet needs: the credit balance and points, and the
/// store's rules (is store credit a tender, what a point is worth). The SERVER enforces every rule (balance, online-only, no points with a
/// coupon or discount); this only decides what the sheet offers, and does the display arithmetic.
///
/// Money here is in the currency the RESPONSES state. When that is not the sale's own currency, credit and points are simply not offered
/// (nothing is converted or guessed).
class SaleCustomerState {
  SaleCustomerState({required PosRepository repository, required String Function() storeId, required bool Function() isOnline}) : _repo = repository, _storeId = storeId, _isOnline = isOnline;
  final PosRepository _repo;
  final String Function() _storeId;
  final bool Function() _isOnline;

  final Rxn<PosCustomer> customer = Rxn<PosCustomer>();
  final Rxn<InvCur> cur = Rxn<InvCur>();
  final Rxn<CustomerConfig> config = Rxn<CustomerConfig>();
  final RxInt redeemPoints = 0.obs;
  int _ticket = 0;

  bool get attached => customer.value != null;

  /// Credit and points are stated in the sale's own currency and exponent.
  bool get sameCurrency {
    final c = cur.value ?? config.value?.cur;
    return c != null && c.code == Money.currency && c.exponent == Money.exponent;
  }

  int get creditBalanceMinor => customer.value?.creditBalanceMinor ?? 0;
  int get points => customer.value?.loyaltyPoints ?? 0;
  LoyaltyRules get rules => config.value?.loyalty ?? const LoyaltyRules();

  /// The store credit tender may be offered for this sale (it is still refused by the server when it should be).
  bool get storeCreditEnabled => attached && sameCurrency && (config.value?.storeCreditTenderEnabled ?? false) && customer.value?.creditBalanceMinor != null;

  /// Points can be spent at this till (the redeem row is shown at all).
  bool get pointsEnabled => attached && sameCurrency && rules.canRedeem && points > 0;

  double get creditBalance => Money.fromMinor(creditBalanceMinor);

  /// What [redeemPoints] is worth, in minor units (display only — the server prices the redemption).
  int get redeemValueMinor => redeemPoints.value * (rules.redeemMinorPerPoint ?? 0);

  /// Most points that can be spent: what the customer has, and whole points that fit in the sale's subtotal (the server refuses a redemption worth more than the sale).
  int maxPoints(int subtotalMinor) {
    final per = rules.redeemMinorPerPoint ?? 0;
    if (per <= 0) return 0;
    final fit = subtotalMinor ~/ per;
    return points < fit ? points : fit;
  }

  void attach(PosCustomer c, InvCur? currency) {
    customer.value = c;
    cur.value = currency;
    redeemPoints.value = 0;
    unawaited(refresh());
  }

  void detach() {
    _ticket++;
    customer.value = null;
    cur.value = null;
    redeemPoints.value = 0;
  }

  /// The freshest balances and the store's credit / loyalty rules. Offline (or on any failure) what is already known stays as it is.
  Future<void> refresh() async {
    final c = customer.value;
    if (c == null || !_isOnline()) return;
    final ticket = ++_ticket;
    final storeId = _storeId();
    CustomerProfile? p;
    CustomerConfig? cfg;
    try {
      p = await _repo.getCustomerProfile(storeId, c.id);
      cfg = await _repo.getCustomerConfig(storeId);
    } catch (_) {
      return; // these facts only decide what the payment sheet offers: never get in the way of the sale
    }
    if (ticket != _ticket || customer.value?.id != c.id) return; // another customer was chosen meanwhile
    if (p != null) {
      customer.value = p.customer.withBalances(creditBalanceMinor: p.creditBalanceMinor ?? c.creditBalanceMinor, loyaltyPoints: p.loyaltyPoints);
      cur.value = p.cur ?? cur.value;
    }
    if (cfg != null) config.value = cfg;
  }

  /// Keeps the chosen number of points within what the customer has and what fits (called when the cart or the customer changes).
  void clampRedeem(int subtotalMinor) {
    final max = pointsEnabled ? maxPoints(subtotalMinor) : 0;
    if (redeemPoints.value > max) redeemPoints.value = max;
  }
}
