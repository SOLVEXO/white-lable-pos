import 'package:solvexo_pos/utils/money.dart';

/// Reads a money amount from an API JSON map. G1b: the server adds `<name>Minor` (an integer in the currency's smallest unit)
/// next to the decimal `<name>`. When the minor twin is present it is the exact value and wins; otherwise (legacy rows, an older
/// server) the decimal is read exactly as before. Always returns major units as a `double`, so no caller changes.
abstract final class MoneyJson {
  /// The minor twin as an int, or null when absent / not an integral number.
  static int? minorOf(Map<dynamic, dynamic>? json, String key) {
    final v = json?['${key}Minor'];
    if (v is int) return v;
    if (v is num && v.isFinite && v == v.truncateToDouble()) return v.toInt();
    return null;
  }

  /// Major units of [key]: from `${key}Minor` when present, else the decimal, else null.
  static double? readNullable(
    Map<dynamic, dynamic>? json,
    String key, {
    int? exp,
  }) {
    final minor = minorOf(json, key);
    if (minor != null) return Money.fromMinor(minor, exp);
    return (json?[key] as num?)?.toDouble();
  }

  /// Like [readNullable] but defaults to 0 (the behaviour every model had before).
  static double read(Map<dynamic, dynamic>? json, String key, {int? exp}) =>
      readNullable(json, key, exp: exp) ?? 0;
}
