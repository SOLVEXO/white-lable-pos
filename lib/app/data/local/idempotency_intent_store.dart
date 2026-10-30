import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// One idempotency key per *user intent* — not per HTTP attempt.
///
/// A key is minted the first time an intent (one checkout, one refund, one
/// cash-in …) is submitted and then handed back unchanged on every retry of
/// that same intent — a second tap after a timeout, an automatic retry, or a
/// re-submit after the app was killed mid-request — until the intent reaches
/// a final result ([release]). The backend dedupes on the key (the
/// `Idempotency-Key` header for every mutating POS route, plus the
/// `idempotencyKey` body field on sales), so a retry can never double-charge
/// or double-restore stock.
///
/// An intent is identified by a [fingerprint] of what the user is asking for
/// (action + target + parameters). Changing the parameters (different refund
/// quantity, an edited cart) is a different intent and gets a fresh key.
///
/// Entries expire after [ttl]: a key left behind by a request whose result
/// was never seen must not be reused days later by an unrelated, identical
/// action (the backend would answer it with the old result).
class IdempotencyIntentStore {
  IdempotencyIntentStore({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
    String Function()? keyGenerator,
  })  : _prefs = prefs ?? SharedPreferences.getInstance,
        _clock = clock ?? DateTime.now,
        _newKey = keyGenerator ?? _randomKey;

  static final IdempotencyIntentStore instance = IdempotencyIntentStore();

  static const String _prefsKey = 'pos_idempotency_intents';
  static const Duration ttl = Duration(minutes: 15);
  static const int _maxEntries = 50;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final String Function() _newKey;

  /// Stable, order-independent identity of an intent: `action` plus a
  /// canonical (recursively key-sorted) JSON of its [params].
  static String fingerprint(String action, [Object? params]) =>
      '$action:${jsonEncode(_canonical(params))}';

  static Object? _canonical(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return {for (final k in keys) k: _canonical(v[k])};
    }
    if (v is Iterable) return v.map(_canonical).toList();
    return v;
  }

  static String _randomKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(12, (_) => r.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'pos-${DateTime.now().microsecondsSinceEpoch}-$hex';
  }

  /// The key for this intent: the one already issued (and not yet released or
  /// expired) if there is one, otherwise a new key that is persisted before
  /// being returned — so it survives the app being killed mid-request.
  Future<String> keyFor(String fingerprint) async {
    try {
      final prefs = await _prefs();
      final entries = _load(prefs);
      final existing = entries[fingerprint];
      if (existing != null) return existing['key'] as String;

      final key = _newKey();
      entries[fingerprint] = {'key': key, 'at': _clock().millisecondsSinceEpoch};
      await _save(prefs, entries);
      return key;
    } catch (_) {
      // Storage unavailable: still send a key (idempotent within this process)
      // rather than block the sale — only cross-restart reuse is lost.
      return _newKey();
    }
  }

  /// Marks the intent as having a final result (success, or a definite
  /// rejection) — the next identical action is a new intent with a new key.
  Future<void> release(String fingerprint) async {
    try {
      final prefs = await _prefs();
      final entries = _load(prefs);
      if (entries.remove(fingerprint) != null) await _save(prefs, entries);
    } catch (_) {
      // best effort — a leftover entry just expires after [ttl]
    }
  }

  Map<String, Map<String, dynamic>> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_prefsKey);
    final out = <String, Map<String, dynamic>>{};
    if (raw == null) return out;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final cutoff = _clock().subtract(ttl).millisecondsSinceEpoch;
      decoded.forEach((k, v) {
        final m = (v as Map).cast<String, dynamic>();
        if ((m['at'] as int) >= cutoff) out[k] = m;
      });
    } catch (_) {
      // corrupt blob — start clean rather than block checkout
    }
    return out;
  }

  Future<void> _save(SharedPreferences prefs, Map<String, Map<String, dynamic>> entries) async {
    if (entries.length > _maxEntries) {
      final sorted = entries.entries.toList()
        ..sort((a, b) => (a.value['at'] as int).compareTo(b.value['at'] as int));
      for (final e in sorted.take(entries.length - _maxEntries)) {
        entries.remove(e.key);
      }
    }
    await prefs.setString(_prefsKey, jsonEncode(entries));
  }
}
