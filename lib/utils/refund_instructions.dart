import 'package:solvexo_pos/utils/money.dart';

/// One slice of a refund, per tender.
class PosRefundSplit {
  final String method; // cash | card | other
  final double amount;
  const PosRefundSplit(this.method, this.amount);
}

/// How a refund of [amount] is returned across the sale's tenders — the SAME rule as the server
/// (`pos-money.util.ts#allocateRefund`): **card / other first (in the order they were taken), cash last**, each
/// capped at what that tender actually took (cash change is not refundable). Because the cash slice is what the
/// server deducts from the drawer, what the cashier is told to hand over here is exactly what the shift report
/// expects to be missing. Display only — the server computes and records the real split.
List<PosRefundSplit> posAllocateRefund({
  required List<({String method, double amount})> tenders,
  required double alreadyRefunded,
  required double amount,
  required int exponent,
}) {
  final ordered = [...tenders.where((t) => t.method != 'cash'), ...tenders.where((t) => t.method == 'cash')];
  List<int> absorbed(int refundedM) {
    var left = refundedM;
    return ordered.map((t) {
      final take = Money.toMinor(t.amount, exponent).clamp(0, left < 0 ? 0 : left);
      left -= take;
      return take;
    }).toList();
  }

  final before = absorbed(Money.toMinor(alreadyRefunded, exponent));
  final after = absorbed(Money.toMinor(alreadyRefunded, exponent) + Money.toMinor(amount, exponent));
  final byMethod = <String, int>{};
  for (var i = 0; i < ordered.length; i++) {
    final d = after[i] - before[i];
    if (d > 0) byMethod[ordered[i].method] = (byMethod[ordered[i].method] ?? 0) + d;
  }
  return [for (final e in byMethod.entries) PosRefundSplit(e.key, Money.fromMinor(e.value, exponent))];
}

/// What the cashier must DO for each slice, in plain words.
List<String> posRefundInstructions(List<PosRefundSplit> splits, {String? currency, int? exponent}) {
  String m(double v) => Money.format(v, currency: currency, exponent: exponent);
  // card / other first (they are done on the machine / by transfer), cash last (it comes out of the drawer)
  final ordered = [...splits.where((s) => s.method != 'cash'), ...splits.where((s) => s.method == 'cash')];
  return [
    for (final s in ordered)
      switch (s.method) {
        'cash' => 'Give ${m(s.amount)} in cash from the drawer',
        'card' => 'Refund ${m(s.amount)} on the card machine',
        _ => 'Return ${m(s.amount)} by bank transfer / the original method',
      },
  ];
}
