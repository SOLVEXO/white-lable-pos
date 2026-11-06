/// The server's return proration, ported (integer minor units; pos-documents.util.ts). Used ONLY to show the cashier what a return will
/// credit before they confirm — the server decides and answers with the real credit note.
int divRound(int a, int b) => b <= 0 ? 0 : (2 * a + b) ~/ (2 * b);

/// The part of [totalMinor] that belongs to the first [n] of [soldQty] units (cumulative, half-up).
int cumulativeShare(int totalMinor, int soldQty, int n) {
  if (soldQty <= 0 || n <= 0) return 0;
  if (n >= soldQty) return totalMinor;
  return divRound(totalMinor * n, soldQty);
}

/// What a sale line carries: its value excluding tax and its tax (stored by the server at sale time).
class LineAmounts {
  final int netMinor;
  final int taxMinor;
  const LineAmounts(this.netMinor, this.taxMinor);
  int get totalMinor => netMinor + taxMinor;
}

/// The credit for returning [qty] more units of a line sold in [soldQty] units of which [returnedQty] already came back.
LineAmounts returnCredit(LineAmounts line, int soldQty, int returnedQty, int qty) {
  int part(int v) => cumulativeShare(v, soldQty, returnedQty + qty) - cumulativeShare(v, soldQty, returnedQty);
  return LineAmounts(part(line.netMinor), part(line.taxMinor));
}
