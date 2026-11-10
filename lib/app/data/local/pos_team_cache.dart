import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_team_models.dart';

/// What the till remembers of the team screens so they still make sense offline: "me" (clocked in / on a break since when, my next shifts) and the
/// roster weeks last seen (READ ONLY, shown with "Last synced <time>"). Names and shift times are staff data, so the blob is sealed at rest like the
/// customer directory.
class TeamCache {
  TeamCache({Future<SharedPreferences> Function()? prefs, DateTime Function()? clock, SealedText? sealed})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      _clock = clock ?? DateTime.now,
      _sealed = sealed ?? SealedText();

  static final TeamCache instance = TeamCache();
  static const _key = 'pos_team_cache';
  static const maxWeeks = 8;

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

  Future<void> saveMe(String storeId, TeamMe me) async {
    final j = await _read(storeId);
    j['me'] = {...me.toJson(), 'at': _clock().toUtc().toIso8601String()};
    await _write(storeId, j);
  }

  /// The remembered "me" of [employeeId] (another person's is never shown), marked with the time it was received.
  Future<TeamMe?> loadMe(String storeId, String employeeId) async {
    final m = (await _read(storeId))['me'];
    if (m is! Map) return null;
    final me = TeamMe.fromJson(m.cast<String, dynamic>());
    if (me.employeeId != employeeId) return null;
    return me.withAsOf(DateTime.tryParse('${m['at'] ?? ''}')?.toLocal() ?? _clock());
  }

  Future<void> saveRoster(String storeId, String weekKey, List<RosterShift> shifts) async {
    final j = await _read(storeId);
    final weeks = Map<String, dynamic>.from((j['weeks'] as Map?) ?? const {});
    weeks.remove(weekKey);
    weeks[weekKey] = {
      'at': _clock().toUtc().toIso8601String(),
      'shifts': [for (final s in shifts) s.toJson()],
    };
    while (weeks.length > maxWeeks) {
      weeks.remove(weeks.keys.first);
    }
    j['weeks'] = weeks;
    await _write(storeId, j);
  }

  Future<({List<RosterShift> shifts, DateTime asOf})?> loadRoster(String storeId, String weekKey) async {
    final w = ((await _read(storeId))['weeks'] as Map?)?[weekKey];
    if (w is! Map) return null;
    return (
      shifts: [
        for (final s in (w['shifts'] as List? ?? const []))
          if (s is Map) RosterShift.fromJson(s.cast<String, dynamic>()),
      ],
      asOf: DateTime.tryParse('${w['at'] ?? ''}')?.toLocal() ?? _clock(),
    );
  }

  Future<void> clear() async {
    try {
      await (await _prefs()).remove(_key);
    } catch (_) {}
  }
}
