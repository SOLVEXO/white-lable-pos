import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_product_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_settings_model.dart';

/// One line of the in-progress cart, with enough of the product to rebuild it with no network.
class CartLineSnapshot {
  final Map<String, dynamic> product;
  final String? variantId;
  final int qty;
  /// G2.4 custom item only: its tax category ('standard' | 'exempt') and the cashier's note.
  final String? taxCategory;
  final String? note;

  /// G4.5: the options chosen for the line (`ChosenModifier.toJson()` maps)
  final List<Map<String, dynamic>> modifiers;
  const CartLineSnapshot({required this.product, this.variantId, required this.qty, this.taxCategory, this.note, this.modifiers = const []});

  Map<String, dynamic> toJson() => {'product': product, 'variantId': variantId, 'qty': qty, if (taxCategory != null) 'taxCategory': taxCategory, if (note != null) 'note': note, if (modifiers.isNotEmpty) 'modifiers': modifiers};
  factory CartLineSnapshot.fromJson(Map<String, dynamic> j) => CartLineSnapshot(
      product: (j['product'] as Map).cast<String, dynamic>(),
      variantId: j['variantId'] as String?,
      qty: (j['qty'] as num?)?.toInt() ?? 1,
      taxCategory: j['taxCategory'] as String?,
      note: j['note'] as String?,
      modifiers: [for (final m in (j['modifiers'] as List? ?? const [])) if (m is Map) m.cast<String, dynamic>()]);
}

class SplitLineSnapshot {
  final String method;
  final String amount;
  final String reference;
  const SplitLineSnapshot({required this.method, required this.amount, required this.reference});
  Map<String, dynamic> toJson() => {'method': method, 'amount': amount, 'reference': reference};
  factory SplitLineSnapshot.fromJson(Map<String, dynamic> j) =>
      SplitLineSnapshot(method: j['method'] as String? ?? 'cash', amount: j['amount'] as String? ?? '', reference: j['reference'] as String? ?? '');
}

/// The cashier's cart as it stood — items, discount, customer, note, payment entry — plus the checkout intent that
/// may already be in flight: [pendingKey] (the idempotency key of the sale being charged) and [pendingAt] (when the
/// cashier tapped Charge). After a crash/kill/restart the cart comes back and charging it again REUSES that key and
/// time, so the server answers with the sale it already recorded instead of creating a second one.
class CartSnapshot {
  final String storeId;
  final String sessionId;
  final List<CartLineSnapshot> lines;
  final String discountText;
  final bool percentDiscount;
  final String customerName;
  final String? customerId;
  final String note;
  final String payment;
  final String tendered;
  final String paymentReference;
  final bool split;
  final List<SplitLineSnapshot> splitLines;
  final String? pendingKey;
  final DateTime? pendingAt;
  final DateTime savedAt;

  /// G2.4: the applied coupon (code + how it discounts), null when none. Re-checked by the server when the sale is charged.
  final Map<String, dynamic>? coupon;

  const CartSnapshot({
    required this.storeId,
    required this.sessionId,
    required this.lines,
    this.discountText = '0',
    this.percentDiscount = false,
    this.customerName = '',
    this.customerId,
    this.note = '',
    this.payment = 'cash',
    this.tendered = '',
    this.paymentReference = '',
    this.split = false,
    this.splitLines = const [],
    this.pendingKey,
    this.pendingAt,
    required this.savedAt,
    this.coupon,
  });

  bool get isEmpty => lines.isEmpty;

  Map<String, dynamic> toJson() => {
        'storeId': storeId,
        'sessionId': sessionId,
        'lines': lines.map((l) => l.toJson()).toList(),
        'discountText': discountText,
        'percentDiscount': percentDiscount,
        'customerName': customerName,
        'customerId': customerId,
        'note': note,
        'payment': payment,
        'tendered': tendered,
        'paymentReference': paymentReference,
        'split': split,
        'splitLines': splitLines.map((l) => l.toJson()).toList(),
        'pendingKey': pendingKey,
        'pendingAt': pendingAt?.toIso8601String(),
        'savedAt': savedAt.toIso8601String(),
        if (coupon != null) 'coupon': coupon,
      };

  factory CartSnapshot.fromJson(Map<String, dynamic> j) => CartSnapshot(
        storeId: j['storeId'] as String? ?? '',
        sessionId: j['sessionId'] as String? ?? '',
        lines: (j['lines'] as List? ?? []).map((e) => CartLineSnapshot.fromJson((e as Map).cast<String, dynamic>())).toList(),
        discountText: j['discountText'] as String? ?? '0',
        percentDiscount: j['percentDiscount'] as bool? ?? false,
        customerName: j['customerName'] as String? ?? '',
        customerId: j['customerId'] as String?,
        note: j['note'] as String? ?? '',
        payment: j['payment'] as String? ?? 'cash',
        tendered: j['tendered'] as String? ?? '',
        paymentReference: j['paymentReference'] as String? ?? '',
        split: j['split'] as bool? ?? false,
        splitLines: (j['splitLines'] as List? ?? []).map((e) => SplitLineSnapshot.fromJson((e as Map).cast<String, dynamic>())).toList(),
        pendingKey: j['pendingKey'] as String?,
        pendingAt: j['pendingAt'] != null ? DateTime.tryParse(j['pendingAt'] as String) : null,
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ?? DateTime.now(),
        coupon: j['coupon'] is Map ? (j['coupon'] as Map).cast<String, dynamic>() : null,
      );
}

/// Persists the in-progress cart (SharedPreferences) so a crash/kill/restart never loses it.
class CartSnapshotStore {
  CartSnapshotStore({Future<SharedPreferences> Function()? prefs, DateTime Function()? clock, SealedText? sealed})
      : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now,
        _sealed = sealed ?? SealedText();

  static final CartSnapshotStore instance = CartSnapshotStore();
  static const _key = 'pos_cart_snapshot';

  /// A cart left this long ago is not resurrected (a different day's shift).
  static const maxAge = Duration(hours: 24);

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final SealedText _sealed; // the cart holds the customer and lines of a sale in progress: encrypted at rest

  Future<void> save(CartSnapshot snapshot) async {
    try {
      final p = await _prefs();
      if (snapshot.isEmpty && snapshot.pendingKey == null) {
        await p.remove(_key);
      } else {
        await p.setString(_key, await _sealed.seal(jsonEncode(snapshot.toJson())));
      }
    } catch (_) {/* persistence is best-effort; never block selling */}
  }

  /// The saved cart, only if it belongs to this store AND this register session and is recent.
  Future<CartSnapshot?> load({required String storeId, required String sessionId}) async {
    try {
      final p = await _prefs();
      final raw = p.getString(_key);
      if (raw == null) return null;
      final read = await _sealed.open(raw);
      if (read.unreadable) {
        await p.remove(_key); // key lost / damaged / tampered: drop it, start with an empty cart
        return null;
      }
      final snap = CartSnapshot.fromJson(jsonDecode(read.text!) as Map<String, dynamic>);
      if (read.legacyPlain) await p.setString(_key, await _sealed.seal(read.text!)); // migrate plaintext from an older build
      if (snap.storeId != storeId || snap.sessionId != sessionId) return null;
      if (_clock().difference(snap.savedAt) > maxAge) return null;
      return snap;
    } catch (_) {
      return null; // corrupt blob — start with an empty cart rather than crash
    }
  }

  Future<void> clear() async {
    try {
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }
}

/// The product catalog as last loaded, for selling when the server can't be reached. Carries a timestamp so the
/// screen can say how old the prices are.
class CatalogCacheStore {
  CatalogCacheStore({Future<SharedPreferences> Function()? prefs, DateTime Function()? clock})
      : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now;

  static final CatalogCacheStore instance = CatalogCacheStore();
  static const _key = 'pos_catalog_cache';
  static const maxProducts = 1000;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;

  Future<void> save(String storeId, List<PosProductModel> products) async {
    try {
      final capped = products.length > maxProducts ? products.sublist(0, maxProducts) : products;
      await (await _prefs()).setString(_key, jsonEncode({'storeId': storeId, 'savedAt': _clock().toIso8601String(), 'products': capped.map((p) => p.toJson()).toList()}));
    } catch (_) {}
  }

  Future<({List<PosProductModel> products, DateTime savedAt})?> load(String storeId) async {
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['storeId'] != storeId) return null;
      final products = (j['products'] as List).map((e) => PosProductModel.fromJson((e as Map).cast<String, dynamic>())).toList();
      return (products: products, savedAt: DateTime.parse(j['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }
}

/// POS settings as last loaded (tax rate, settingsVersion, receipt text) so pricing and receipts work offline.
class SettingsCacheStore {
  SettingsCacheStore({Future<SharedPreferences> Function()? prefs, DateTime Function()? clock, SealedText? sealed})
      : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now,
        _sealed = sealed ?? SealedText();

  static final SettingsCacheStore instance = SettingsCacheStore();
  static const _key = 'pos_settings_cache';

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final SealedText _sealed; // business name, tax id, receipt header/footer: encrypted at rest

  Future<void> save(PosSettingsModel settings) async {
    try {
      await (await _prefs()).setString(_key, await _sealed.seal(jsonEncode({'savedAt': _clock().toIso8601String(), 'settings': settings.toCacheJson()})));
    } catch (_) {}
  }

  Future<({PosSettingsModel settings, DateTime savedAt})?> load(String storeId) async {
    try {
      final p = await _prefs();
      final raw = p.getString(_key);
      if (raw == null) return null;
      final read = await _sealed.open(raw);
      if (read.unreadable) {
        await p.remove(_key); // key lost / damaged / tampered: the cache is rebuilt from the server
        return null;
      }
      if (read.legacyPlain) await p.setString(_key, await _sealed.seal(read.text!)); // migrate plaintext from an older build
      final j = jsonDecode(read.text!) as Map<String, dynamic>;
      final s = PosSettingsModel.fromJson((j['settings'] as Map).cast<String, dynamic>());
      if (s.storeId != storeId) return null;
      return (settings: s, savedAt: DateTime.parse(j['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }
}
