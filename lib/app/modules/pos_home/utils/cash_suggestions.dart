import 'package:solvexo_pos/utils/money.dart';

/// Quick "cash received" chips: the exact amount, then the next few round amounts the customer is likely to hand
/// over. DISPLAY SUGGESTIONS ONLY — they fill the tendered field and nothing else; the amount due, the change and the
/// shortfall always come from the controller (`total`, `changeDue`, `paymentCheck.shortBy`).
///
/// Arithmetic is done in the currency's minor units (cents, fils, …) so there is no float noise, and the steps scale
/// with the currency's own decimals ([exponent]): a currency with no decimals (¥, ₩) starts at 10, others at 1.
abstract final class CashSuggestions {
  static const List<int> _steps = [
    1,
    5,
    10,
    20,
    50,
    100,
    200,
    500,
    1000,
    5000,
    10000,
  ];

  /// `[exact, …up to [rounded] round-ups]`, ascending, no duplicates. Empty when [total] is not positive.
  static List<double> forTotal(
    double total, {
    required int exponent,
    int rounded = 3,
  }) {
    if (!(total > 0)) return const [];
    final totalMinor = Money.toMinor(total, exponent);
    if (totalMinor <= 0) return const [];
    var unit = 1;
    for (var i = 0; i < exponent; i++) {
      unit *= 10;
    }
    final minStep = exponent == 0 ? 10 : 1;
    final out = <int>[totalMinor];
    for (final step in _steps) {
      if (step < minStep) continue;
      final stepMinor = step * unit;
      final up = ((totalMinor + stepMinor - 1) ~/ stepMinor) * stepMinor;
      if (up > totalMinor && !out.contains(up)) out.add(up);
      if (out.length > rounded) break;
    }
    return [for (final m in out) Money.fromMinor(m, exponent)];
  }
}
