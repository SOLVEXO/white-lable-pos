import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solvexo_pos/app/data/local/sealed_text.dart';

/// The QR payment this till is waiting for, kept so the wait SURVIVES the app being killed or the till locking: on reopen the
/// pending payment is looked up on the server and resumed (never a second charge for the same checkout).
///
/// Only identifiers and the amount are stored (no customer data, no QR payload — that is fetched again from the server), sealed
/// like the other local stores. At most one pending payment per till. Entries older than [maxAge] are dropped: the server's own
/// expiry (default 3 minutes) is far shorter; anything left is leftover.
class PendingQrStore {
  PendingQrStore({Future<SharedPreferences> Function()? prefs, SealedText? sealed, DateTime Function()? clock})
      : _prefs = prefs ?? SharedPreferences.getInstance,
        _sealed = sealed ?? SealedText(),
        _clock = clock ?? DateTime.now;

  static final PendingQrStore instance = PendingQrStore();
  static const String _key = 'pos_pending_qr';
  static const Duration maxAge = Duration(hours: 2);

  final Future<SharedPreferences> Function() _prefs;
  final SealedText _sealed;
  final DateTime Function() _clock;

  Future<void> save(PendingQr q) async {
    final p = await _prefs();
    await p.setString(_key, await _sealed.seal(jsonEncode(q.toJson(_clock()))));
  }

  Future<PendingQr?> read() async {
    try {
      final p = await _prefs();
      final raw = p.getString(_key);
      if (raw == null) return null;
      final opened = await _sealed.open(raw);
      if (opened.text == null) {
        await clear();
        return null;
      }
      final j = jsonDecode(opened.text!) as Map<String, dynamic>;
      final at = DateTime.tryParse('${j['savedAt']}');
      if (at == null || _clock().difference(at) > maxAge) {
        await clear();
        return null;
      }
      return PendingQr.fromJson(j);
    } catch (e) {
      debugPrint('PendingQrStore.read: $e');
      return null;
    }
  }

  Future<void> clear() async => (await _prefs()).remove(_key);
}

class PendingQr {
  const PendingQr({required this.intentId, required this.createKey, required this.saleAttemptKey, required this.amountMinor, required this.qrIndex});

  /// The server's id of the payment — empty while the create request has not been answered yet.
  final String intentId;

  /// The idempotency key of the create request: asking again with it returns the SAME payment, so a kill between "request sent"
  /// and "answer received" can never produce a second QR for the same attempt.
  final String createKey;
  final String saleAttemptKey;
  final int amountMinor;

  /// Which QR line of the checkout this is (0 for the usual single QR payment).
  final int qrIndex;

  Map<String, dynamic> toJson(DateTime now) => {'intentId': intentId, 'createKey': createKey, 'saleAttemptKey': saleAttemptKey, 'amountMinor': amountMinor, 'qrIndex': qrIndex, 'savedAt': now.toIso8601String()};

  factory PendingQr.fromJson(Map<String, dynamic> j) => PendingQr(
        intentId: (j['intentId'] as String?) ?? '',
        createKey: j['createKey'] as String,
        saleAttemptKey: j['saleAttemptKey'] as String,
        amountMinor: (j['amountMinor'] as num).toInt(),
        qrIndex: (j['qrIndex'] as num? ?? 0).toInt(),
      );
}
