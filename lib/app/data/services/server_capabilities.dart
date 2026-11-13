import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/network/api_constaints.dart';

/// What one probe of `GET /api/pos/capabilities` told us (G6.2).
enum CapabilityProbeKind {
  /// the route answered with its feature list → a backend with release #2 (features as listed)
  found,

  /// the backend is older: the route does not exist there (NestJS's own "Cannot GET …" 404), or it answered without a `features` field
  older,

  /// nothing can be concluded (offline, timeout, 5xx, 401 / 403, a proxy's page, any other shape) → the last decision stands
  inconclusive,
}

class CapabilityProbe {
  const CapabilityProbe(this.kind, [this.features = const {}]);
  const CapabilityProbe.inconclusive() : kind = CapabilityProbeKind.inconclusive, features = const {};
  final CapabilityProbeKind kind;
  final Set<String> features;

  /// Pure: classifies the probe's HTTP answer. Only THIS route's answer is ever used — an ordinary 404 of a product, sale, customer or document
  /// elsewhere never reaches here. A 404 counts as "route missing" only when it is the framework's own unknown-route answer (no `code` of ours,
  /// message `Cannot GET /api/pos/capabilities`).
  static CapabilityProbe classify(int? status, dynamic body) {
    if (status == 200 && body is Map && body['data'] is Map) {
      final f = (body['data'] as Map)['features'];
      if (f is List) return CapabilityProbe(CapabilityProbeKind.found, {for (final x in f) '$x'});
      return const CapabilityProbe(CapabilityProbeKind.older); // the field is absent
    }
    if (status == 404 && body is Map && body['code'] == null && '${body['message'] ?? ''}'.startsWith('Cannot GET')) {
      return const CapabilityProbe(CapabilityProbeKind.older);
    }
    return const CapabilityProbe.inconclusive();
  }
}

/// G6.1 / G6.2 — which till features the connected backend supports, from ONE explicit probe (`GET /api/pos/capabilities`), never from an
/// ordinary 404. The production API may still be the G5.1 backend (c889af0), which has no such route: release #2's features are then hidden.
///  * re-checked on every app start, when the home screen opens (after login / device setup) and on a store switch — so the features appear on
///    their own once release #2 is live (no reinstall, no clearing data);
///  * the last answer is cached per API base URL for offline starts; a network error, 5xx or any inconclusive answer never changes it;
///  * nothing known yet (fresh install, offline) → features shown as before (their screens degrade on their own).
class ServerCapabilities {
  static const prefsKey = 'pos_server_capabilities_v1';

  /// true = release #2 (see [features]); false = older backend; null = not known yet
  static final RxnBool releaseTwo = RxnBool();
  static final RxSet<String> features = <String>{}.obs;
  static DateTime? checkedAt;

  /// How the probe is made (tests replace it); default = the real HTTP probe.
  static Future<CapabilityProbe> Function() probe = _httpProbe;
  static Future<SharedPreferences> Function() prefs = SharedPreferences.getInstance;
  static String Function() apiBase = () => ApiConstants.baseUrl;

  static bool get olderServer => releaseTwo.value == false;

  /// A release-#2 feature is shown unless the backend is known to be older, or (newer) its list does not name it.
  static bool has(String feature) => releaseTwo.value == null || (releaseTwo.value == true && features.contains(feature));

  static Future<CapabilityProbe>? _inFlight;

  /// The cached answer for this API (call once at start, before the first screen).
  static Future<void> loadCached() async {
    try {
      final raw = (await prefs()).getString(prefsKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map || j['api'] != apiBase()) return; // another backend (e.g. a dev build pointed elsewhere): not ours
      _apply(j['older'] == true ? false : true, {for (final f in (j['features'] as List? ?? const [])) '$f'}, DateTime.tryParse('${j['at']}'));
    } catch (e) {
      debugPrint('server capabilities cache: $e');
    }
  }

  /// Probes the backend (one request; concurrent calls share it). Found / older → applied and cached; inconclusive → nothing changes.
  static Future<CapabilityProbe> refresh() {
    return _inFlight ??= () async {
      try {
        final r = await probe().catchError((_) => const CapabilityProbe.inconclusive());
        if (r.kind == CapabilityProbeKind.inconclusive) return r;
        final now = DateTime.now();
        _apply(r.kind == CapabilityProbeKind.found, r.features, now);
        try {
          await (await prefs()).setString(prefsKey, jsonEncode({'api': apiBase(), 'older': r.kind == CapabilityProbeKind.older, 'features': r.features.toList(), 'at': now.toIso8601String()}));
        } catch (_) {/* the in-memory answer still holds */}
        return r;
      } finally {
        _inFlight = null;
      }
    }();
  }

  static void _apply(bool newer, Set<String> f, DateTime? at) {
    features
      ..clear()
      ..addAll(newer ? f : const <String>{});
    releaseTwo.value = newer;
    checkedAt = at;
  }

  @visibleForTesting
  static void resetForTest() {
    releaseTwo.value = null;
    features.clear();
    checkedAt = null;
    _inFlight = null;
    probe = _httpProbe;
    prefs = SharedPreferences.getInstance;
    apiBase = () => ApiConstants.baseUrl;
  }

  static Future<CapabilityProbe> _httpProbe() => PosRepository().probeCapabilities();
}
