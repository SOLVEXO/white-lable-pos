import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_cash_models.dart';

/// The last cash configuration the server sent (category lists, approval limits and, above all, the store's currency + exponent), so a cash in / out
/// can still be typed and queued while the till is offline. Not sensitive (no names, no amounts of anyone's), so plain preferences.
class CashConfigCache {
  CashConfigCache({Future<SharedPreferences> Function()? prefs}) : _prefs = prefs ?? SharedPreferences.getInstance;
  static final CashConfigCache instance = CashConfigCache();
  final Future<SharedPreferences> Function() _prefs;

  String _key(String storeId) => 'pos_cash_config_$storeId';

  Future<void> save(String storeId, CashConfig c) async {
    try {
      await (await _prefs()).setString(_key(storeId), jsonEncode(c.toJson()));
    } catch (_) {}
  }

  Future<CashConfig?> load(String storeId) async {
    try {
      final raw = (await _prefs()).getString(_key(storeId));
      if (raw == null) return null;
      return CashConfig.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}
