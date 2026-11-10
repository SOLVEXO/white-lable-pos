import 'dart:async';

import 'package:get/get.dart';
import 'package:solvexo_pos/app/modules/pos_home/controllers/pos_home_controller.dart';
import 'package:solvexo_pos/core/design/design.dart';

/// "Swipe to remove — Undo" for the cart. UI-side only: it removes the line with the controller's own
/// [PosHomeController.removeFromCart] and, on Undo, puts the very same [CartItem] (product, variant, price, quantity)
/// back at its old position through the public `cartItems` list. If the same product was added again in the meantime
/// the quantity is merged into that line instead.
///
/// The Undo is dropped (never restored into a different sale) when:
///  * [window] (4 s) passes,
///  * a line that was still in the cart disappears — the cart was cleared, a sale was charged or held, or a held sale
///    was resumed (which clears the cart first),
///  * a Charge finishes ([PosHomeController.lastOutcome] changes), or
///  * [invalidate] is called (the sale screen calls it before opening held sales / starting a charge or hold).
class CartRemovalUndo {
  CartRemovalUndo._(this._c, this.window, this._toast) {
    _cartWorker = ever<List<CartItem>>(_c.cartItems, (_) => _onCartChanged());
    _outcomeWorker = ever<SaleOutcome?>(_c.lastOutcome, (_) => invalidate());
  }

  /// One undo helper per controller.
  static final Expando<CartRemovalUndo> _instances = Expando<CartRemovalUndo>();
  static CartRemovalUndo of(
    PosHomeController c, {
    Duration window = const Duration(seconds: 4),
    bool showToast = true,
  }) => _instances[c] ??= CartRemovalUndo._(c, window, showToast);

  final PosHomeController _c;
  final Duration window;
  final bool _toast;
  late final Worker _cartWorker;
  late final Worker _outcomeWorker;

  CartItem? _item;
  int _index = 0;
  Set<String> _keysAfter = const {};
  Timer? _timer;
  bool _toastShown = false;

  bool get canUndo => _item != null;

  /// Removes [item] from the cart and offers Undo for [window].
  void remove(CartItem item) {
    final index = _c.cartItems.indexOf(item);
    if (index < 0) return;
    invalidate();
    _c.removeFromCart(item);
    _item = item;
    _index = index;
    _keysAfter = {for (final i in _c.cartItems) i.cartKey};
    _timer = Timer(window, invalidate);
    if (_toast) {
      _toastShown = true;
      AppToast.show(
        'Removed ${item.displayName}',
        actionLabel: 'Undo',
        onAction: undo,
        duration: window,
        position: ToastPosition.bottom,
      );
    }
  }

  /// Puts the removed line back. Returns false when there is nothing (valid) to undo.
  bool undo() {
    final item = _item;
    if (item == null) return false;
    final existing = _c.cartItems.firstWhereOrNull(
      (i) => i.cartKey == item.cartKey,
    );
    if (existing != null) {
      existing.quantity.value +=
          item.quantity.value; // the item was re-added meanwhile: merge
      _c.cartItems.refresh();
    } else {
      _c.cartItems.insert(_index.clamp(0, _c.cartItems.length), item);
    }
    invalidate(dismissToast: false);
    return true;
  }

  /// Forgets the pending Undo (and closes its toast if it is the one showing).
  void invalidate({bool dismissToast = true}) {
    _timer?.cancel();
    _timer = null;
    _item = null;
    _keysAfter = const {};
    if (_toastShown) {
      _toastShown = false;
      if (dismissToast) {
        AppToast.dismiss();
      }
    }
  }

  void _onCartChanged() {
    if (_item == null) return;
    final now = {for (final i in _c.cartItems) i.cartKey};
    if (!now.containsAll(_keysAfter)) {
      invalidate(); // a remaining line vanished: cleared / charged / held / resumed
    }
  }

  void dispose() {
    invalidate();
    _cartWorker.dispose();
    _outcomeWorker.dispose();
  }
}
