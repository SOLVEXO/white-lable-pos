import 'package:solvexo_pos/utils/money.dart';

/// Cart pricing, mirroring the server's `pos-money.util.ts` step for step (integer minor units of the store
/// currency, half away from zero). The server is authoritative and recomputes everything — it rejects a total
/// that differs from this one by more than a minor unit (TOTAL_MISMATCH) — so this exists only to SHOW the
/// cashier the number the server will charge, never to decide it.
class PosTotals {
  final int exponent;
  final List<double> lineTotals;
  final double subtotal;
  final double discount;
  final double tax;
  final double total;

  /// The discount asked for was more than the subtotal (the server rejects it; the app blocks the Charge button).
  final bool discountExceedsSubtotal;

  const PosTotals._({
    required this.exponent,
    required this.lineTotals,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.discountExceedsSubtotal,
  });

  /// [lines]: (unit price, qty). [percentDiscount]: [discountInput] is a % of the subtotal, else a flat amount.
  /// [taxRate] is the store's rate from POS settings (0.08 = 8%) — not something the cashier types.
  static PosTotals compute(
    List<({double price, int qty})> lines, {
    required int exponent,
    required bool percentDiscount,
    required double discountInput,
    required double taxRate,
  }) {
    final lineM = lines.map((l) => Money.toMinor(l.price * l.qty, exponent)).toList();
    final subtotalM = lineM.fold<int>(0, (a, b) => a + b);

    var discountM = 0;
    if (discountInput > 0) {
      discountM = percentDiscount
          ? _roundHalfUp(subtotalM * discountInput / 100)
          : Money.toMinor(discountInput, exponent);
    }
    final exceeds = discountM > subtotalM || (percentDiscount && discountInput > 100);
    if (exceeds) discountM = subtotalM; // display only; the Charge button is blocked while this is true

    final taxableM = subtotalM - discountM;
    final taxM = _roundHalfUp(taxableM * taxRate);
    return PosTotals._(
      exponent: exponent,
      lineTotals: lineM.map((m) => Money.fromMinor(m, exponent)).toList(),
      subtotal: Money.fromMinor(subtotalM, exponent),
      discount: Money.fromMinor(discountM, exponent),
      tax: Money.fromMinor(taxM, exponent),
      total: Money.fromMinor(taxableM + taxM, exponent),
      discountExceedsSubtotal: exceeds,
    );
  }

  static int _roundHalfUp(double x) {
    final r = double.parse(x.abs().toStringAsPrecision(15)).roundToDouble();
    return (x < 0 ? -r : r).toInt();
  }
}

/// One tender line being entered at the till. For cash [amount] is what the customer HANDS OVER.
class PosPaymentEntry {
  final String method; // cash | card | other
  final double amount;
  const PosPaymentEntry(this.method, this.amount);
}

/// Whether the entered tenders settle [total] — the same rules the server enforces (cash may exceed what's
/// left after card/other and the overage is change; card/other can never exceed the total). UX feedback only.
class PosPaymentCheck {
  final bool covered;
  final double shortBy;
  final double change;
  final bool nonCashExceedsTotal;
  final double paid;

  const PosPaymentCheck._({required this.covered, required this.shortBy, required this.change, required this.nonCashExceedsTotal, required this.paid});

  static PosPaymentCheck evaluate(double total, List<PosPaymentEntry> entries, {required int exponent}) {
    final totalM = Money.toMinor(total, exponent);
    var nonCashM = 0;
    var cashM = 0;
    for (final e in entries) {
      final m = Money.toMinor(e.amount, exponent);
      if (e.method == 'cash') {
        cashM += m;
      } else {
        nonCashM += m;
      }
    }
    final exceeds = nonCashM > totalM;
    final cashDueM = totalM - nonCashM;
    final shortM = exceeds ? 0 : (cashM < cashDueM ? cashDueM - cashM : 0);
    final changeM = (!exceeds && cashM > cashDueM) ? cashM - cashDueM : 0;
    return PosPaymentCheck._(
      covered: !exceeds && shortM == 0 && (totalM == 0 || nonCashM + cashM > 0),
      shortBy: Money.fromMinor(shortM, exponent),
      change: Money.fromMinor(changeM, exponent),
      nonCashExceedsTotal: exceeds,
      paid: Money.fromMinor(nonCashM + cashM, exponent),
    );
  }
}
