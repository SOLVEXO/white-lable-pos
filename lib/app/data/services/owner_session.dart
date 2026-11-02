/// The store OWNER's own session, held only in memory and only briefly.
///
/// After a device is registered the app keeps just the device token. Anything that changes the store's configuration
/// (employees, locations, registers/shifts, settings, plan purchase, stock adjustments, the devices list) is an
/// owner-facing route the backend does NOT open to a device token — the owner has to re-authenticate with their password,
/// which yields this short-lived JWT. It is never written to disk and is dropped on expiry, lock, sign-out and revocation.
class OwnerSession {
  OwnerSession._();

  static const Duration ttl = Duration(minutes: 10);

  static DateTime Function() clock = DateTime.now;
  static String? _token;
  static DateTime? _expiresAt;

  static bool get isActive => _token != null && _expiresAt != null && clock().isBefore(_expiresAt!);

  /// The owner JWT, or null when there is no (unexpired) owner session.
  static String? get token => isActive ? _token : null;

  static void start(String token) {
    _token = token;
    _expiresAt = clock().add(ttl);
  }

  /// Sliding window: using an owner screen keeps it open; walking away lets it lapse.
  static void touch() {
    if (isActive) _expiresAt = clock().add(ttl);
  }

  static void end() {
    _token = null;
    _expiresAt = null;
  }
}

/// Which backend routes only the owner's own session may call (a device token is refused there). Mirrors the backend's
/// split: everything under `/pos` that is NOT operational, plus the other modules' management routes the app uses.
class OwnerRoutes {
  OwnerRoutes._();

  static bool requiresOwner(String method, String path) {
    final m = method.toUpperCase();
    var p = path;
    final q = p.indexOf('?');
    if (q >= 0) p = p.substring(0, q);
    final i = p.indexOf('/api/');
    if (i >= 0) p = p.substring(i + 4); // '/pos/…'
    if (p.endsWith('/') && p.length > 1) p = p.substring(0, p.length - 1);

    if (p == '/pos/devices/me' || p == '/pos/devices/me/sign-out') return false; // the device talking about itself
    if (p.startsWith('/pos/devices')) return true;
    if (p.startsWith('/seller/account-deletion')) return true; // deleting the owner's account
    if (p.startsWith('/pos/employees')) return true;
    if (p.startsWith('/pos/locations')) return true;
    if (p.startsWith('/pos/registers/') && m != 'GET') return true;
    if (p.startsWith('/pos/shifts/') && m != 'GET') return true;
    if (p.startsWith('/pos/settings/') && m != 'GET') return true;
    if (RegExp(r'^/pos/sessions/[^/]+/force-close$').hasMatch(p)) return true;
    if (p.startsWith('/inventory/') || p.startsWith('/activity-log/') || p.startsWith('/store/') || p.startsWith('/products/')) return true;
    return false;
  }
}
