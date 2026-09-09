// Unit tests for the register-close cash reconciliation math surfaced in the
// Phase 1 close-shift dialog (PosSettingsController.showCloseShiftDialog) —
// PosSessionCashFlow.hasVariance/isShortfall, which drive whether the
// cashier sees "matches exactly" (green), "short" (red), or "over" (orange).

import 'package:solvexo_pos/app/data/models/pos/pos_report_model.dart';
import 'package:flutter_test/flutter_test.dart';

PosSessionCashFlow _flow({
  double openingCash = 100.0,
  double cashSales = 0.0,
  double cashIn = 0.0,
  double cashOut = 0.0,
  double? closingCash,
}) {
  final expectedCash = openingCash + cashSales + cashIn - cashOut;
  final cashDifference = closingCash != null ? closingCash - expectedCash : null;
  return PosSessionCashFlow(
    openingCash: openingCash,
    cashSales: cashSales,
    cashIn: cashIn,
    cashOut: cashOut,
    expectedCash: expectedCash,
    closingCash: closingCash,
    cashDifference: cashDifference,
  );
}

void main() {
  group('expected cash', () {
    test('is opening + cash sales + cash in - cash out', () {
      final flow = _flow(openingCash: 100, cashSales: 250, cashIn: 20, cashOut: 15);
      expect(flow.expectedCash, 355.0);
    });
  });

  group('hasVariance / isShortfall', () {
    test('counted cash exactly matches expected -> no variance', () {
      final flow = _flow(openingCash: 100, cashSales: 250, closingCash: 350);
      expect(flow.cashDifference, 0.0);
      expect(flow.hasVariance, isFalse);
      expect(flow.isShortfall, isFalse);
    });

    test('counted cash below expected -> variance, shortfall (red)', () {
      final flow = _flow(openingCash: 100, cashSales: 250, closingCash: 340);
      expect(flow.cashDifference, -10.0);
      expect(flow.hasVariance, isTrue);
      expect(flow.isShortfall, isTrue);
    });

    test('counted cash above expected -> variance, not a shortfall (over, orange)', () {
      final flow = _flow(openingCash: 100, cashSales: 250, closingCash: 365);
      expect(flow.cashDifference, 15.0);
      expect(flow.hasVariance, isTrue);
      expect(flow.isShortfall, isFalse);
    });

    test('cash-in/cash-out adjustments shift the expected amount before comparing', () {
      // Till top-up of 50, then 20 paid out for a supplier delivery.
      final flow = _flow(openingCash: 100, cashSales: 200, cashIn: 50, cashOut: 20, closingCash: 330);
      expect(flow.expectedCash, 330.0);
      expect(flow.cashDifference, 0.0);
      expect(flow.hasVariance, isFalse);
    });

    test('sub-cent rounding noise does not register as a variance', () {
      final flow = _flow(openingCash: 100, cashSales: 0, closingCash: 100.005);
      expect(flow.hasVariance, isFalse, reason: 'hasVariance uses a 0.009 tolerance for float noise');
    });

    test('no closing cash yet (still open) -> no variance reported', () {
      final flow = _flow(openingCash: 100, cashSales: 50);
      expect(flow.closingCash, isNull);
      expect(flow.cashDifference, isNull);
      expect(flow.hasVariance, isFalse);
      expect(flow.isShortfall, isFalse);
    });
  });
}
