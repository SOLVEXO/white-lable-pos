import 'dart:collection';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_customer_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';

/// The last first-expiry-first-out answer per item, so the till can still SUGGEST a lot when it is offline ("as of <time>"). In memory
/// first, plus a small persisted JSON (capped, oldest answers dropped first). The suggestion is a hint only: the server allocates
/// the lots for real when the sale reaches it, and an offline sale is never blocked by it.
class LotPreviewCache {
  LotPreviewCache({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now;

  static final LotPreviewCache instance = LotPreviewCache();
  static const _key = 'pos_lot_preview_cache';
  static const maxEntries = 200;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final LinkedHashMap<String, LotPreview> _byVariant = LinkedHashMap();
  bool _loaded = false;

  int get length => _byVariant.length;

  /// Reads the persisted copy once (a corrupt blob is ignored).
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null) return;
      for (final e in (jsonDecode(raw) as List)) {
        final p = LotPreview.fromJson((e as Map).cast<String, dynamic>());
        _byVariant.putIfAbsent(p.variantId, () => p);
      }
    } catch (_) {
      /* best effort */
    }
  }

  LotPreview? get(String variantId) => _byVariant[variantId];

  /// Remembers [p] as the latest answer for its item (marked with the time it was received).
  Future<void> put(LotPreview p) async {
    _byVariant.remove(
      p.variantId,
    ); // re-insert: the newest answer is the last one
    _byVariant[p.variantId] = p.asOf == null ? p.withAsOf(_clock()) : p;
    while (_byVariant.length > maxEntries) {
      _byVariant.remove(_byVariant.keys.first);
    }
    try {
      await (await _prefs()).setString(
        _key,
        jsonEncode([for (final v in _byVariant.values) v.toJson()]),
      );
    } catch (_) {}
  }
}

/// Customers as last seen, so search and a profile still open without internet (marked "as of <time>"). Names, phones, e-mails and tax
/// ids are personal data: the blob is sealed at rest like the saved cart. Creating a customer is NOT possible offline.
class CustomerCache {
  CustomerCache({
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? clock,
    SealedText? sealed,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _clock = clock ?? DateTime.now,
       _sealed = sealed ?? SealedText();

  static final CustomerCache instance = CustomerCache();
  static const _key = 'pos_customer_cache';
  static const maxSearches = 10, maxProfiles = 50, maxRows = 40;

  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _clock;
  final SealedText _sealed;

  Future<Map<String, dynamic>> _read(String storeId) async {
    try {
      final raw = (await _prefs()).getString(_key);
      if (raw == null) return {};
      final open = await _sealed.open(raw);
      if (open.unreadable) return {};
      final j = jsonDecode(open.text!) as Map<String, dynamic>;
      return j['storeId'] == storeId ? j : {};
    } catch (_) {
      return {};
    }
  }

  Future<void> _write(String storeId, Map<String, dynamic> j) async {
    try {
      j['storeId'] = storeId;
      await (await _prefs()).setString(_key, await _sealed.seal(jsonEncode(j)));
    } catch (_) {}
  }

  Future<void> saveSearch(
    String storeId,
    String q,
    PosCustomerPage page,
  ) async {
    final j = await _read(storeId);
    final searches = LinkedHashMap<String, dynamic>.from(
      (j['searches'] as Map?) ?? const {},
    );
    final key = q.trim().toLowerCase();
    searches.remove(key);
    searches[key] = {
      'at': _clock().toUtc().toIso8601String(),
      'currency': page.cur?.code,
      'currencyExponent': page.cur?.exponent,
      'items': [for (final c in page.items.take(maxRows)) c.toJson()],
    };
    while (searches.length > maxSearches) {
      searches.remove(searches.keys.first);
    }
    j['searches'] = searches;
    await _write(storeId, j);
  }

  /// The remembered answer to [q], or — when that exact search was never made — the customers of any remembered search that match it.
  Future<PosCustomerPage?> loadSearch(String storeId, String q) async {
    final j = await _read(storeId);
    final searches =
        (j['searches'] as Map?)?.cast<String, dynamic>() ?? const {};
    final key = q.trim().toLowerCase();
    Map<String, dynamic>? hit = (searches[key] as Map?)
        ?.cast<String, dynamic>();
    final at = DateTime.tryParse('${hit?['at'] ?? ''}')?.toLocal();
    PosCustomerPage page(Map<String, dynamic> s, List<PosCustomer> items) =>
        PosCustomerPage(
          items: items,
          cur: InvCur.fromJson(s),
          asOf: DateTime.tryParse('${s['at'] ?? ''}')?.toLocal(),
        );
    List<PosCustomer> parse(Map<String, dynamic> s) => [
      for (final c in (s['items'] as List? ?? const []))
        if (c is Map) PosCustomer.fromJson(c.cast<String, dynamic>()),
    ];
    if (hit != null && at != null) return page(hit, parse(hit));
    // typed something new while offline: filter what is remembered by the typed text
    if (key.isEmpty) return null;
    final seen = <String>{};
    final matches = <PosCustomer>[];
    Map<String, dynamic>? newest;
    for (final s in searches.values.map(
      (e) => (e as Map).cast<String, dynamic>(),
    )) {
      newest = s;
      for (final c in parse(s)) {
        if (seen.add(c.id) &&
            '${c.name} ${c.phone ?? ''} ${c.email ?? ''}'
                .toLowerCase()
                .contains(key))
          matches.add(c);
      }
    }
    return newest == null ? null : page(newest, matches);
  }

  Future<void> saveProfile(String storeId, CustomerProfile p) async {
    final j = await _read(storeId);
    final profiles = LinkedHashMap<String, dynamic>.from(
      (j['profiles'] as Map?) ?? const {},
    );
    profiles.remove(p.customer.id);
    profiles[p.customer.id] = p.withAsOf(_clock()).toJson();
    while (profiles.length > maxProfiles) {
      profiles.remove(profiles.keys.first);
    }
    j['profiles'] = profiles;
    await _write(storeId, j);
  }

  Future<CustomerProfile?> loadProfile(String storeId, String id) async {
    final j = await _read(storeId);
    final m = ((j['profiles'] as Map?) ?? const {})[id];
    return m is Map
        ? CustomerProfile.fromJson(m.cast<String, dynamic>())
        : null;
  }

  Future<void> clear() async {
    try {
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }
}
