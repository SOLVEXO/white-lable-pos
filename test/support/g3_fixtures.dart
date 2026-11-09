import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:cryptography/cryptography.dart';
import 'package:solvexo_pos/app/data/local/queue_cipher.dart';

/// A customer cache with a fixed key (no secure storage needed in tests).
CustomerCache testCustomerCache() => CustomerCache(
  sealed: SealedText(cipher: AesGcmQueueCipher(fixedKey: SecretKey(List.filled(32, 5)))),
);

const usd = InvCur('USD', 2);

PosCustomer customer({
  String id = 'c1',
  String name = 'Dev Customer',
  String? phone = '03001112222',
  String? email,
  int? credit = 2000,
  int points = 40,
  String? tier = 'silver',
  bool existing = false,
}) => PosCustomer(id: id, kind: 'pos', name: name, phone: phone, email: email, creditBalanceMinor: credit, loyaltyPoints: points, loyaltyTier: tier, existing: existing);

PosCustomerPage customerPage(List<PosCustomer> items, {InvCur? cur = usd}) => PosCustomerPage(items: items, cur: cur);

CustomerProfile profile({String id = 'c1', int? lifetime, int credit = 2000, int points = 40, InvCur? cur = usd, bool loyaltyOn = true}) => CustomerProfile(
  customer: customer(id: id),
  cur: cur,
  creditBalanceMinor: credit,
  lifetimeSpendMinor: lifetime,
  loyaltyPoints: points,
  loyaltyTier: 'silver',
  loyalty: LoyaltyRules(enabled: loyaltyOn, earnSpendMinor: 1000, redeemMinorPerPoint: 50),
  orderCount: 3,
  lastVisitAt: DateTime(2026, 11, 1, 10),
  recentSales: [CustomerSaleRef(id: 's1', number: 'S-0001', totalMinor: 1200, status: 'completed', at: DateTime(2026, 11, 1, 10))],
);

CreditEntry creditEntry({String id = 'e1', int amount = 2000, int balance = 2000, String type = 'adjust_credit'}) =>
    CreditEntry(id: id, type: type, amountMinor: amount, balanceAfterMinor: balance, at: DateTime(2026, 11, 1, 10), note: 'welcome credit');
