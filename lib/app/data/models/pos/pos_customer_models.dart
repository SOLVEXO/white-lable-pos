import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

/// G3.3 customers, store credit and loyalty. Money is integer MINOR units (`...Minor`) next to the response's own currency and exponent
/// ([InvCur]): a response that does not state both shows no money. Every identity field except the name is optional.
int? _int(dynamic v) => v is num ? v.toInt() : null;
String? _str(dynamic v) {
  final s = v is String ? v.trim() : null;
  return s == null || s.isEmpty ? null : s;
}

class PosCustomer {
  const PosCustomer({
    required this.id,
    required this.kind,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.ntn,
    this.cnic,
    this.registrationType,
    this.group,
    this.notes,
    this.marketingConsent = false,
    this.linkedUserId,
    this.creditBalanceMinor,
    this.loyaltyPoints = 0,
    this.loyaltyTier,
    this.existing = false,
  });

  final String id, name;

  /// `pos` (made at a till) or `user` (a storefront buyer of this store)
  final String kind;
  final String? phone, email, address, ntn, cnic, registrationType, group, notes, linkedUserId, loyaltyTier;
  final bool marketingConsent;

  /// null when the store's credit ledger is off
  final int? creditBalanceMinor;
  final int loyaltyPoints;

  /// create only: the same phone number already belonged to this customer, so nothing new was made
  final bool existing;

  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
  String get subtitle => [if (phone != null) phone!, if (email != null) email!].join(' · ');

  factory PosCustomer.fromJson(Map<String, dynamic> j) => PosCustomer(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    kind: j['kind'] as String? ?? 'pos',
    name: j['name'] as String? ?? '',
    phone: _str(j['phone']),
    email: _str(j['email']),
    address: _str(j['address']),
    ntn: _str(j['ntn']),
    cnic: _str(j['cnic']),
    registrationType: _str(j['registrationType']),
    group: _str(j['group']),
    notes: _str(j['notes']),
    marketingConsent: j['marketingConsent'] == true,
    linkedUserId: _str(j['linkedUserId']),
    creditBalanceMinor: _int(j['creditBalanceMinor']),
    loyaltyPoints: _int(j['loyaltyPoints']) ?? 0,
    loyaltyTier: _str(j['loyaltyTier']),
    existing: j['existing'] == true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'ntn': ntn,
    'cnic': cnic,
    'registrationType': registrationType,
    'group': group,
    'notes': notes,
    'marketingConsent': marketingConsent,
    'linkedUserId': linkedUserId,
    'creditBalanceMinor': creditBalanceMinor,
    'loyaltyPoints': loyaltyPoints,
    'loyaltyTier': loyaltyTier,
  };

  PosCustomer withBalances({int? creditBalanceMinor, int? loyaltyPoints}) => PosCustomer(
    id: id,
    kind: kind,
    name: name,
    phone: phone,
    email: email,
    address: address,
    ntn: ntn,
    cnic: cnic,
    registrationType: registrationType,
    group: group,
    notes: notes,
    marketingConsent: marketingConsent,
    linkedUserId: linkedUserId,
    loyaltyTier: loyaltyTier,
    creditBalanceMinor: creditBalanceMinor ?? this.creditBalanceMinor,
    loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
  );
}

/// A page of customers with the currency the balances are stated in. [asOf] is set when the page came from the offline cache.
class PosCustomerPage {
  const PosCustomerPage({required this.items, this.cur, this.asOf});
  final List<PosCustomer> items;
  final InvCur? cur;
  final DateTime? asOf;
}

class LoyaltyRules {
  const LoyaltyRules({this.enabled = false, this.earnSpendMinor, this.redeemMinorPerPoint});
  final bool enabled;
  final int? earnSpendMinor, redeemMinorPerPoint;

  /// Points can be spent at the till for this store.
  bool get canRedeem => enabled && (redeemMinorPerPoint ?? 0) > 0;

  factory LoyaltyRules.fromJson(dynamic j) =>
      j is Map ? LoyaltyRules(enabled: j['enabled'] == true, earnSpendMinor: _int(j['earnSpendMinor']), redeemMinorPerPoint: _int(j['redeemMinorPerPoint'])) : const LoyaltyRules();
}

class CustomerConfig {
  const CustomerConfig({this.cur, this.storeCreditTenderEnabled = false, this.loyalty = const LoyaltyRules()});
  final InvCur? cur;
  final bool storeCreditTenderEnabled;
  final LoyaltyRules loyalty;

  factory CustomerConfig.fromJson(Map<String, dynamic> j) =>
      CustomerConfig(cur: InvCur.fromJson(j), storeCreditTenderEnabled: j['storeCreditTenderEnabled'] == true, loyalty: LoyaltyRules.fromJson(j['loyalty']));
}

class CustomerSaleRef {
  const CustomerSaleRef({required this.id, required this.number, required this.totalMinor, required this.status, this.at});
  final String id, number, status;
  final int totalMinor;
  final DateTime? at;

  factory CustomerSaleRef.fromJson(Map<String, dynamic> j) => CustomerSaleRef(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    number: '${j['number'] ?? ''}',
    totalMinor: _int(j['totalMinor']) ?? 0,
    status: j['status'] as String? ?? '',
    at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
  );
}

class CustomerProfile {
  const CustomerProfile({
    required this.customer,
    this.cur,
    this.creditBalanceMinor,
    this.loyaltyPoints = 0,
    this.loyaltyTier,
    this.loyalty = const LoyaltyRules(),
    this.orderCount = 0,
    this.lastVisitAt,
    this.lifetimeSpendMinor,
    this.recentSales = const [],
    this.asOf,
  });
  final PosCustomer customer;
  final InvCur? cur;
  final int? creditBalanceMinor, lifetimeSpendMinor;
  final int loyaltyPoints, orderCount;
  final String? loyaltyTier;
  final LoyaltyRules loyalty;
  final DateTime? lastVisitAt;
  final List<CustomerSaleRef> recentSales;

  /// set when this came from the offline cache
  final DateTime? asOf;

  CustomerProfile withAsOf(DateTime t) => CustomerProfile(
    customer: customer,
    cur: cur,
    creditBalanceMinor: creditBalanceMinor,
    lifetimeSpendMinor: lifetimeSpendMinor,
    loyaltyPoints: loyaltyPoints,
    orderCount: orderCount,
    loyaltyTier: loyaltyTier,
    loyalty: loyalty,
    lastVisitAt: lastVisitAt,
    recentSales: recentSales,
    asOf: t,
  );

  factory CustomerProfile.fromJson(Map<String, dynamic> j) => CustomerProfile(
    customer: PosCustomer.fromJson((j['customer'] as Map? ?? const {}).cast<String, dynamic>()),
    cur: InvCur.fromJson(j),
    creditBalanceMinor: _int(j['creditBalanceMinor']),
    loyaltyPoints: _int(j['loyaltyPoints']) ?? 0,
    loyaltyTier: _str(j['loyaltyTier']),
    loyalty: LoyaltyRules.fromJson(j['loyalty']),
    orderCount: _int(j['orderCount']) ?? 0,
    lastVisitAt: DateTime.tryParse('${j['lastVisitAt'] ?? ''}')?.toLocal(),
    lifetimeSpendMinor: _int(j['lifetimeSpendMinor']),
    recentSales: [
      for (final s in (j['recentSales'] as List? ?? const []))
        if (s is Map) CustomerSaleRef.fromJson(s.cast<String, dynamic>()),
    ],
    asOf: DateTime.tryParse('${j['asOf'] ?? ''}')?.toLocal(),
  );

  Map<String, dynamic> toJson() => {
    'currency': cur?.code,
    'currencyExponent': cur?.exponent,
    'customer': customer.toJson(),
    'creditBalanceMinor': creditBalanceMinor,
    'loyaltyPoints': loyaltyPoints,
    'loyaltyTier': loyaltyTier,
    'loyalty': {'enabled': loyalty.enabled, 'earnSpendMinor': loyalty.earnSpendMinor, 'redeemMinorPerPoint': loyalty.redeemMinorPerPoint},
    'orderCount': orderCount,
    'lastVisitAt': lastVisitAt?.toUtc().toIso8601String(),
    'lifetimeSpendMinor': lifetimeSpendMinor,
    'recentSales': [
      for (final s in recentSales) {'id': s.id, 'number': s.number, 'totalMinor': s.totalMinor, 'status': s.status, 'at': s.at?.toUtc().toIso8601String()},
    ],
    'asOf': asOf?.toUtc().toIso8601String(),
  };
}

class CreditEntry {
  const CreditEntry({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.balanceAfterMinor,
    this.at,
    this.note,
    this.saleId,
    this.orderId,
    this.creditNoteNumber,
    this.expiresAt,
  });
  final String id, type;
  final int amountMinor, balanceAfterMinor;
  final DateTime? at, expiresAt;
  final String? note, saleId, orderId, creditNoteNumber;

  factory CreditEntry.fromJson(Map<String, dynamic> j) => CreditEntry(
    id: '${j['id'] ?? j['_id'] ?? ''}',
    type: j['type'] as String? ?? '',
    amountMinor: _int(j['amountMinor']) ?? 0,
    balanceAfterMinor: _int(j['balanceAfterMinor']) ?? 0,
    at: DateTime.tryParse('${j['at'] ?? ''}')?.toLocal(),
    expiresAt: DateTime.tryParse('${j['expiresAt'] ?? ''}')?.toLocal(),
    note: _str(j['note']),
    saleId: _str(j['saleId']),
    orderId: _str(j['orderId']),
    creditNoteNumber: _str(j['creditNoteNumber']),
  );
}

class CreditLedgerPage {
  const CreditLedgerPage({required this.enabled, required this.items, this.cur, this.hasMore = false});
  final bool enabled, hasMore;
  final InvCur? cur;
  final List<CreditEntry> items;
}

/// A credit entry type in plain words.
String creditTypeLabel(String type) => switch (type) {
  'adjust_credit' => 'Credit added by a manager',
  'adjust_debit' => 'Credit removed by a manager',
  'spend' => 'Spent on a sale',
  'spend_reversal' => 'Credit returned (sale reversed)',
  'refund_credit' => 'Refund to store credit',
  'redeem' => 'Spent online',
  'restore' => 'Credit restored',
  'expire' => 'Expired',
  '' => 'Credit',
  final t => '${t[0].toUpperCase()}${t.substring(1).replaceAll('_', ' ')}',
};

/// "gold" → "Gold"
String loyaltyTierLabel(String? tier) => tier == null || tier.isEmpty ? '' : '${tier[0].toUpperCase()}${tier.substring(1)}';

/// Server error codes of the customer / credit / loyalty endpoints in plain English (the server enforces; this only explains).
String customerErrorMessage(String? code, {String? fallback}) => switch (code) {
  'NAME_REQUIRED' => 'Enter the customer\'s name.',
  'PHONE_INVALID' => 'Enter the phone number with digits only (5 to 18, an optional + first).',
  'EMAIL_INVALID' => 'That e-mail address does not look right.',
  'NTN_INVALID' => 'The NTN may contain letters, digits and dashes only.',
  'CNIC_INVALID' => 'The CNIC may contain letters, digits and dashes only.',
  'REGISTRATION_TYPE_INVALID' => 'Pick registered or unregistered.',
  'PHONE_IN_USE' => 'Another customer already uses that phone number.',
  'POS_ACTION_FORBIDDEN' => 'Only a manager or the owner can do this.',
  'POS_OWNER_REQUIRED' => 'This amount is above the manager limit. The store owner must make this change.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  'NOTE_REQUIRED' => 'Add a short note explaining the change.',
  'AMOUNT_INVALID' => 'Enter a whole amount that is not zero.',
  'STORE_CREDIT_NOT_ENABLED' => 'Store credit is not switched on for this store.',
  'STORE_CREDIT_ONLINE_ONLY' => 'Store credit needs an internet connection.',
  'STORE_CREDIT_INSUFFICIENT' => 'The customer does not have enough store credit for this.',
  'CUSTOMER_REQUIRED' => 'Choose the customer first.',
  'CUSTOMER_REQUIRED_FOR_CREDIT' => 'Refunding to store credit needs a customer on the sale.',
  'LOYALTY_ONLINE_ONLY' => 'Points can only be redeemed with an internet connection.',
  'LOYALTY_NOT_ENABLED' => 'Points cannot be redeemed at the till for this store.',
  'LOYALTY_WITH_DISCOUNT' => 'Points cannot be combined with a coupon or a discount on the same sale.',
  'LOYALTY_EXCEEDS_SALE' => 'Those points are worth more than the sale. Use fewer points.',
  'LOYALTY_INSUFFICIENT_POINTS' => 'The customer does not have that many points.',
  _ => fallback ?? 'Something went wrong. Please try again.',
};
