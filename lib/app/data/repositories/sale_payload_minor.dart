import 'package:solvexo_pos/utils/money.dart';

/// G1b: adds the integer minor-unit twins to a `POST /pos/sales` payload, NEXT TO the decimals (which are never removed or changed,
/// so an older server and an older replay path see exactly what they always did). The server recomputes every figure itself and uses
/// these only as a cross-check (a decimal/minor disagreement is rejected, never silently fixed).
///
/// Twins: `clientTotalMinor`, `amountTenderedMinor`, `discountValueMinor` (only when `discountType == 'amount'`; a percentage is not
/// money), `items[].unitPriceMinor` (from `items[].unitPrice`), `payments[].amountMinor`. Conversion is [Money.toMinor] with the
/// store's exponent — the ISO-4217 exponent the whole app uses, never a display setting.
Map<String, dynamic> withMinorTwins(Map<String, dynamic> payload, {int? exp}) {
  final e = exp ?? Money.exponent;
  int? m(Object? v) => v is num ? Money.toMinor(v, e) : null;

  final out = Map<String, dynamic>.from(payload);
  void twin(String key) {
    final v = m(payload[key]);
    if (v != null) out['${key}Minor'] = v;
  }

  twin('clientTotal');
  twin('amountTendered');
  if (payload['discountType'] == 'amount') twin('discountValue');

  final items = payload['items'];
  if (items is List) {
    out['items'] = [
      for (final i in items)
        if (i is Map)
          _twinned(i.cast<String, dynamic>(), 'unitPrice', e)
        else
          i,
    ];
  }
  final payments = payload['payments'];
  if (payments is List) {
    out['payments'] = [
      for (final p in payments)
        if (p is Map) _twinned(p.cast<String, dynamic>(), 'amount', e) else p,
    ];
  }
  return out;
}

Map<String, dynamic> _twinned(Map<String, dynamic> line, String key, int exp) {
  final copy = Map<String, dynamic>.from(line);
  final v = line[key];
  if (v is num) copy['${key}Minor'] = Money.toMinor(v, exp);
  return copy;
}
