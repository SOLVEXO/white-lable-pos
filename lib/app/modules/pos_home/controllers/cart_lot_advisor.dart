import 'dart:async';

import 'package:solvexo_pos/app/data/local/pos_g3_caches.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_lot_models.dart';
import 'package:solvexo_pos/app/data/repositories/pos_repository.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';

/// G3.2: keeps each cart line's first-expiry-first-out suggestion up to date. Online it asks the server (debounced, the newest quantity
/// wins) and remembers the answer; offline it shows the last remembered answer for that item, marked "as of <time>". It never blocks a
/// sale, and when the server cannot be reached the line simply keeps what it has.
class CartLotAdvisor {
  CartLotAdvisor({
    required PosRepository repository,
    LotPreviewCache? cache,
    required bool Function() isOnline,
    required String Function() storeId,
    this.debounce = const Duration(milliseconds: 350),
    DateTime Function()? clock,
  }) : _repo = repository,
       _cache = cache ?? LotPreviewCache.instance,
       _isOnline = isOnline,
       _storeId = storeId,
       _clock = clock ?? DateTime.now;

  final PosRepository _repo;
  final LotPreviewCache _cache;
  final bool Function() _isOnline;
  final String Function() _storeId;
  final Duration debounce;
  final DateTime Function() _clock;
  final Map<String, Timer> _timers = {};
  final Map<String, DateTime> _lastFetch = {};

  /// "This item is not lot-tracked" is remembered this long before the server is asked again.
  static const untrackedFor = Duration(hours: 1);

  bool _untrackedKnown(LotPreview? p) =>
      p != null &&
      !p.trackLots &&
      p.asOf != null &&
      _clock().difference(p.asOf!) < untrackedFor;

  /// Call when a line is added or its quantity changed.
  void request(CartItem item) {
    final v = item.variant;
    if (item.isCustom || v == null || v.unlimitedStock) return;
    unawaited(_start(item, v.variantId));
  }

  Future<void> _start(CartItem item, String variantId) async {
    await _cache.load();
    final cached = _cache.get(variantId);
    if (_untrackedKnown(cached)) {
      item.lotPreview.value = null;
      return;
    }
    if (cached != null && cached.trackLots && item.lotPreview.value == null) {
      item.lotPreview.value = cached;
      item.lotPreviewLive.value = false;
    }
    if (!_isOnline()) return;
    // the first look is immediate; quick taps after it are folded into one trailing request with the newest quantity
    final key = item.cartKey;
    _timers[key]?.cancel();
    final wait = _lastFetch[key] == null
        ? Duration.zero
        : debounce - _clock().difference(_lastFetch[key]!);
    if (wait <= Duration.zero) {
      unawaited(_fetch(item, variantId));
    } else {
      _timers[key] = Timer(wait, () => unawaited(_fetch(item, variantId)));
    }
  }

  Future<void> _fetch(CartItem item, String variantId) async {
    _timers.remove(item.cartKey);
    _lastFetch[item.cartKey] = _clock();
    final qty = item.quantity.value;
    LotPreview? p;
    try {
      p = await _repo.getLotPreview(_storeId(), variantId, qty);
    } catch (_) {
      return; // a suggestion must never get in the way of selling
    }
    if (p == null) return; // not reachable / refused: keep showing what we have
    await _cache.put(p);
    if (item.quantity.value != qty)
      return; // a newer quantity has its own request
    if (!p.trackLots) {
      item.lotPreview.value = null;
      item.sellExpired.value = false;
      return;
    }
    item.lotPreview.value = p;
    item.lotPreviewLive.value = true;
    // expired units are only sold when the sellable ones do not cover the quantity: never keep the override once they do
    if (item.sellExpired.value && !p.needsExpiredOverride)
      item.sellExpired.value = false;
  }

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _lastFetch.clear();
  }
}
