import 'package:intl/intl.dart';

/// App-wide money formatting and rounding, driven by the STORE's currency and its ISO-4217 minor-unit
/// exponent (JPY 0, USD/PKR 2, KWD 3) — never a hard-coded `$` or `toStringAsFixed(2)`.
///
/// The backend is authoritative: `GET /pos/settings/:storeId` returns the store's `currency` and
/// `currencyExponent`, and every sale/refund/session carries its own snapshot. [configure] is called when
/// settings load (and from the persisted copy at boot); [format] then renders with that currency, while a
/// historical record can pass its own `currency`/`exponent` explicitly.
///
/// Amounts stay `double` in memory (the API is JSON numbers in major units) but every step that matters is
/// done in integer minor units via [toMinor]/[fromMinor], rounded half away from zero — the same rule as the
/// server (`pos-money.util.ts`), so the app and server agree on every cent.
class Money {
  Money._();

  static String currency = 'USD';
  static int exponent = 2;

  static void configure({String? currency, int? exponent}) {
    if (currency != null && currency.trim().isNotEmpty) Money.currency = currency.trim().toUpperCase();
    if (exponent != null) {
      Money.exponent = exponent;
    } else if (currency != null && currency.trim().isNotEmpty) {
      Money.exponent = exponentFor(currency);
    }
  }

  /// Fallback ONLY for before the server has told us (first launch offline). The server's value always wins.
  static int exponentFor(String code) {
    const zero = {'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF', 'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF'};
    const three = {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'};
    final c = code.toUpperCase();
    if (zero.contains(c)) return 0;
    if (three.contains(c)) return 3;
    return 2;
  }

  // ── Rounding (integer minor units, half away from zero) ──────────────────────────────────────

  static int toMinor(num v, [int? exp]) {
    final e = exp ?? exponent;
    final f = _pow10(e);
    final scaled = double.parse((v.abs() * f).toStringAsPrecision(15));
    final r = scaled.roundToDouble(); // Dart's round() is half away from zero
    return (v < 0 ? -r : r).toInt();
  }

  static double fromMinor(int m, [int? exp]) {
    final e = exp ?? exponent;
    return double.parse((m / _pow10(e)).toStringAsFixed(e));
  }

  static double round(num v, [int? exp]) => fromMinor(toMinor(v, exp), exp);

  static double _pow10(int e) {
    var f = 1.0;
    for (var i = 0; i < e; i++) {
      f *= 10;
    }
    return f;
  }

  // ── Formatting ───────────────────────────────────────────────────────────────────────────────

  /// `$1,234.50`, `¥1,234`, `KWD 1,234.500` — symbol and decimals from the currency, grouping from `en_US`.
  static String format(num v, {String? currency, int? exponent}) {
    final code = (currency ?? Money.currency).toUpperCase();
    final exp = exponent ?? (currency == null ? Money.exponent : exponentFor(code));
    final rounded = round(v, exp);
    return NumberFormat.currency(locale: 'en_US', name: code, decimalDigits: exp).format(rounded);
  }

  /// Like [format] but always shows the sign: `+$2.16`, `-$5.00`.
  static String signed(num v, {String? currency, int? exponent}) =>
      '${v < 0 ? '-' : '+'}${format(v.abs(), currency: currency, exponent: exponent)}';

  /// Just the symbol (`$`, `¥`, `PKR`) — for input prefixes/hints.
  static String symbol([String? currency]) =>
      NumberFormat.currency(locale: 'en_US', name: (currency ?? Money.currency).toUpperCase()).currencySymbol;

  /// Plain decimal text for editing, with the currency's own decimals (`12.50`, `1250`, `1.250`).
  static String plain(num v, {int? exponent}) => round(v, exponent).toStringAsFixed(exponent ?? Money.exponent);
}
