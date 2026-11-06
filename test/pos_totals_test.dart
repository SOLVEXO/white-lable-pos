// The app's displayed total must equal the server's. These cases are copied from the backend's
// pos-money.util.spec.ts / pos.money.integration.spec.ts (same inputs → same outputs), per currency exponent.

import 'package:flutter_test/flutter_test.dart';
import 'package:solvexo_pos/utils/money.dart';
import 'package:solvexo_pos/utils/pos_totals.dart';

PosTotals t(List<(double, int)> lines, {required int exp, bool pct = false, double disc = 0, double tax = 0}) =>
    PosTotals.compute([for (final l in lines) (price: l.$1, qty: l.$2, taxable: true)], exponent: exp, percentDiscount: pct, discountInput: disc, taxRate: tax);

void main() {
  refundTests();
  group('Money', () {
    test('rounds half away from zero without float noise', () {
      expect(Money.round(1.005, 2), 1.01);
      expect(Money.round(2.675, 2), 2.68);
      expect(Money.round(0.1 + 0.2, 2), 0.3);
      expect(Money.round(-1.005, 2), -1.01);
      expect(Money.round(100.5, 0), 101);
      expect(Money.round(1.2345, 3), 1.235);
    });
    test('formats with the currency\'s own decimals and symbol (never a fixed 2, never a hardcoded \$)', () {
      expect(Money.format(1234.5, currency: 'USD', exponent: 2), '\$1,234.50');
      expect(Money.format(1234.5, currency: 'JPY', exponent: 0), contains('1,235'));
      expect(Money.format(1234.5, currency: 'JPY', exponent: 0), isNot(contains('.')));
      expect(Money.format(1.2345, currency: 'KWD', exponent: 3), endsWith('1.235'));
      expect(Money.format(-5, currency: 'USD', exponent: 2), '-\$5.00');
    });
    test('configure() switches the app-wide default', () {
      Money.configure(currency: 'JPY', exponent: 0);
      expect(Money.exponent, 0);
      expect(Money.format(999), isNot(contains('.')));
      Money.configure(currency: 'USD', exponent: 2);
    });
    test('exponent fallback table matches the server for common currencies', () {
      expect(Money.exponentFor('JPY'), 0);
      expect(Money.exponentFor('KWD'), 3);
      expect(Money.exponentFor('PKR'), 2);
      expect(Money.exponentFor('usd'), 2);
    });
  });

  group('PosTotals — identical to the server', () {
    test('USD: 3×19.99 + 0.335, 10% off, 8.25% tax', () {
      final r = t([(19.99, 3), (0.335, 1)], exp: 2, pct: true, disc: 10, tax: 0.0825);
      expect(r.lineTotals, [59.97, 0.34]);
      expect([r.subtotal, r.discount, r.tax, r.total], [60.31, 6.03, 4.48, 58.76]);
    });
    test('USD: the Phase-5B integration case (59.97, 10%, 8.25% → 58.42)', () {
      final r = t([(19.99, 3)], exp: 2, pct: true, disc: 10, tax: 0.0825);
      expect([r.subtotal, r.discount, r.tax, r.total], [59.97, 6.0, 4.45, 58.42]);
    });
    test('JPY: whole yen only', () {
      final r = t([(333, 3), (99, 1)], exp: 0, pct: true, disc: 15, tax: 0.1);
      expect([r.subtotal, r.discount, r.tax, r.total], [1098, 165, 93, 1026]);
    });
    test('KWD: three decimals', () {
      final r = t([(1.255, 3)], exp: 3, disc: 0.5, tax: 0.05);
      expect([r.subtotal, r.discount, r.tax, r.total], [3.765, 0.5, 0.163, 3.428]);
    });
    test('PKR flat discount, no tax', () {
      final r = t([(1499.5, 2)], exp: 2, disc: 99.99);
      expect([r.subtotal, r.discount, r.tax, r.total], [2999, 99.99, 0, 2899.01]);
    });
    test('a discount over the subtotal is flagged (the Charge button is blocked) and displayed clamped', () {
      final r = t([(10, 1)], exp: 2, disc: 10.01);
      expect(r.discountExceedsSubtotal, isTrue);
      expect(r.total, 0);
      expect(t([(10, 1)], exp: 2, pct: true, disc: 100.5).discountExceedsSubtotal, isTrue);
      expect(t([(10, 1)], exp: 2, pct: true, disc: 100, tax: 0.2).discountExceedsSubtotal, isFalse);
    });
    test('empty cart is zero', () {
      expect(t([], exp: 2, tax: 0.1).total, 0);
    });
  });

  group('PosPaymentCheck — same rules the server enforces', () {
    PosPaymentCheck check(double total, List<(String, double)> e) =>
        PosPaymentCheck.evaluate(total, [for (final x in e) PosPaymentEntry(x.$1, x.$2)], exponent: 2);

    test('exact cash', () => expect(check(25, [('cash', 25)]).covered, isTrue));
    test('cash over → change', () {
      final r = check(25, [('cash', 40)]);
      expect(r.covered, isTrue);
      expect(r.change, 15);
    });
    test('cash short', () {
      final r = check(25, [('cash', 20)]);
      expect(r.covered, isFalse);
      expect(r.shortBy, 5);
    });
    test('card + cash split', () {
      final r = check(100, [('card', 60), ('cash', 40)]);
      expect(r.covered, isTrue);
      expect(r.change, 0);
    });
    test('cash overage after a card portion is change', () {
      final r = check(100, [('card', 60), ('cash', 50)]);
      expect(r.covered, isTrue);
      expect(r.change, 10);
    });
    test('card/other can never exceed the total', () {
      final r = check(50, [('card', 60)]);
      expect(r.nonCashExceedsTotal, isTrue);
      expect(r.covered, isFalse);
      expect(check(50, [('card', 30), ('other', 30)]).covered, isFalse);
    });
    test('short split reports the shortfall', () {
      final r = check(100, [('card', 60), ('cash', 30)]);
      expect(r.covered, isFalse);
      expect(r.shortBy, 10);
    });
    test('no payment entered is not covered (unless the total is zero)', () {
      expect(check(10, []).covered, isFalse);
    });
    test('JPY rounding', () {
      final r = PosPaymentCheck.evaluate(1000, [const PosPaymentEntry('card', 600.4), const PosPaymentEntry('cash', 400)], exponent: 0);
      expect(r.covered, isTrue);
    });
  });
}

void refundTests() {
  group('posPartialRefundAmount — same as the server', () {
    double r({required int qty, double already = 0, bool completes = false, int exp = 2, double subtotal = 30, double total = 29.16, double price = 10}) =>
        posPartialRefundAmount(subtotal: subtotal, total: total, alreadyRefunded: already, lines: [(price: price, qty: qty)], completesSale: completes, exponent: exp);
    test('one of three units returns a third of what was paid (discount + tax pro-rated)', () => expect(r(qty: 1), 9.72));
    test('the last refund is the exact remainder', () => expect(r(qty: 1, already: 19.44, completes: true), 9.72));
    test('never more than is left', () => expect(r(qty: 3, already: 25), 4.16));
    test('JPY stays whole yen', () => expect(r(qty: 1, subtotal: 1500, total: 1650, price: 500, exp: 0), 550));
    test('zero subtotal refunds nothing', () => expect(r(qty: 1, subtotal: 0, total: 0, price: 0), 0));
  });
}
