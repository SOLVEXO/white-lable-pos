/// Shared currency-symbol/amount formatting for the app's multi-currency
/// (PKR/USD) fields. `currency == null` (e.g. mixed-currency seller
/// analytics, or legacy rows predating the currency fields) renders as a
/// plain number with no symbol rather than guessing a currency.
class CurrencyFormatter {
  static String symbol(String? currency) {
    if (currency == 'PKR') return 'PKR ';
    if (currency == 'USD') return '\$';
    return '';
  }

  static String amount(double value, String? currency, {int decimals = 2}) {
    return '${symbol(currency)}${value.toStringAsFixed(decimals)}';
  }

  /// Compact "12.3K"-style formatting for stat tiles/KPI grids.
  static String compact(double value, String? currency) {
    final prefix = symbol(currency);
    if (value >= 1000) return '$prefix${(value / 1000).toStringAsFixed(1)}K';
    return '$prefix${value.toStringAsFixed(0)}';
  }
}
