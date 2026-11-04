// Quick-amount chips are display suggestions only: exact amount + a few round-ups, scaled to the currency's decimals.
import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/app/modules/pos_home/utils/cash_suggestions.dart';

void main() {
  test('USD: exact first, then round-ups, ascending and distinct', () {
    expect(CashSuggestions.forTotal(7.30, exponent: 2), [
      7.30,
      8.0,
      10.0,
      20.0,
    ]);
    expect(CashSuggestions.forTotal(24.50, exponent: 2), [
      24.50,
      25.0,
      30.0,
      40.0,
    ]);
    expect(
      CashSuggestions.forTotal(20.0, exponent: 2),
      [20.0, 50.0, 100.0, 200.0],
      reason: 'an exact multiple is never repeated',
    );
  });

  test(
    'a currency with no decimals starts at 10 and never suggests fractions',
    () {
      final s = CashSuggestions.forTotal(730, exponent: 0);
      expect(s.first, 730);
      expect(s.every((v) => v == v.roundToDouble()), isTrue);
      expect(s, [730, 740, 750, 800]);
    },
  );

  test('three-decimal currencies keep their own precision', () {
    final s = CashSuggestions.forTotal(1.250, exponent: 3);
    expect(s.first, 1.25);
    expect(s.skip(1).every((v) => v > 1.25), isTrue);
  });

  test('no float noise: 0.1 + 0.2 style totals stay exact in minor units', () {
    expect(CashSuggestions.forTotal(0.30, exponent: 2).first, 0.30);
    expect(CashSuggestions.forTotal(19.99, exponent: 2).skip(1).first, 20.0);
  });

  test('zero / negative / NaN totals give nothing to suggest', () {
    expect(CashSuggestions.forTotal(0, exponent: 2), isEmpty);
    expect(CashSuggestions.forTotal(-5, exponent: 2), isEmpty);
    expect(CashSuggestions.forTotal(double.nan, exponent: 2), isEmpty);
  });

  test(
    'every suggestion is at least the total (never suggests an under-payment)',
    () {
      for (final t in [0.01, 0.99, 3.5, 99.99, 1234.56, 100000.0]) {
        final s = CashSuggestions.forTotal(t, exponent: 2);
        expect(s.every((v) => v >= t), isTrue, reason: '$t -> $s');
      }
    },
  );
}
