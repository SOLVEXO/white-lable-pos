import 'package:solvexo_pos/app/data/models/pos/pos_credit_note_model.dart';

/// G6.1 — what a print (thermal receipt, tax invoice, credit note, PDF) shows for a document's fiscal block. Everything printed comes from the
/// server's contract (FISCAL_CONTRACT.md); the app adds only two generic fallbacks:
///  * a block with no display lines → the number alone (no label) once confirmed, or [pendingText] while pending / failed;
///  * an offline receipt of a store that fiscalises → [pendingText] (the reprint after sync shows the server's confirmed block).
/// Rejected, not-required and unknown statuses print nothing unless the server sent lines for them.
class FiscalPrint {
  const FiscalPrint({this.lines = const [], this.qr, this.logoUrl});
  static const empty = FiscalPrint();
  static const pendingText = 'Fiscal pending';

  /// printed in order; an empty label prints the value alone
  final List<FiscalLine> lines;
  final String? qr;
  final String? logoUrl;
  bool get isEmpty => lines.isEmpty && qr == null;

  static FiscalPrint of(PosFiscalInfo? f, {bool offlinePending = false}) {
    if (f == null || !f.required) return offlinePending ? const FiscalPrint(lines: [FiscalLine('', pendingText)]) : empty;
    if (f.displayLines.isNotEmpty) return FiscalPrint(lines: f.displayLines, qr: f.confirmed ? f.qrPayload : null, logoUrl: f.confirmed ? f.logoUrl : null);
    if (f.confirmed) return FiscalPrint(lines: [if (f.number != null) FiscalLine('', f.number!)], qr: f.qrPayload, logoUrl: f.logoUrl);
    if (f.pending || f.failed) return const FiscalPrint(lines: [FiscalLine('', pendingText)]);
    return empty; // rejected without lines
  }

  /// One text line per entry for a single-line layout (PDF): `label value`, or the value alone.
  List<String> get textLines => [for (final l in lines) l.label.isEmpty ? l.value : '${l.label} ${l.value}'];
}
