import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_supply_models.dart';

/// The last successful purchase-order list, kept on the till so it can still be READ without internet ("Last synced <time> - read only").
/// Stored exactly as the server answered (a cashier's copy has no costs, a manager's has them) and sealed at rest like the customer
/// directory. It is only ever shown; nothing is changed from it.
class SupplyOrdersCache {
  SupplyOrdersCache({Future<SharedPreferences> Function()? prefs, DateTime Function()? clock, SealedText? sealed})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      _clock = clock ?? DateTime.now,
      _sealed = sealed ?? SealedText();

  static final SupplyOrdersCache instance = SupplyOrdersCache();
  static const _key = 'pos_supply_orders_cache';

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final SealedText _sealed;

  /// Remembers [list] (its raw response) for [storeId].
  Future<void> save(String storeId, PoList list) async {
    final raw = list.raw;
    if (raw == null) return;
    try {
      final blob = jsonEncode({'storeId': storeId, 'at': _clock().toUtc().toIso8601String(), 'data': raw});
      await (await _prefs()).setString(_key, await _sealed.seal(blob));
    } catch (_) {
      /* best effort */
    }
  }

  /// The remembered list of [storeId] marked with the time it was received, or null (nothing remembered, another store, unreadable).
  Future<PoList?> load(String storeId) async {
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null) return null;
      final open = await _sealed.open(raw);
      if (open.unreadable) return null;
      final j = jsonDecode(open.text!) as Map<String, dynamic>;
      if (j['storeId'] != storeId) return null;
      final at = DateTime.tryParse('${j['at'] ?? ''}')?.toLocal();
      if (at == null || j['data'] is! Map) return null;
      return PoList.fromJson((j['data'] as Map).cast<String, dynamic>()).withAsOf(at);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }
}
