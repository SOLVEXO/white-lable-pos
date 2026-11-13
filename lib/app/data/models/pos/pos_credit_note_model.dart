/// One line of a fiscal block, printed and shown exactly as the server sent it (G6.1 — the app never chooses a tax-authority label).
class FiscalLine {
  const FiscalLine(this.label, this.value);
  final String label;
  final String value;
  Map<String, dynamic> toJson() => {'label': label, 'value': value};
  static FiscalLine? fromJson(dynamic j) => j is Map && j['value'] != null ? FiscalLine('${j['label'] ?? ''}', '${j['value']}') : null;
  @override
  bool operator ==(Object other) => other is FiscalLine && other.label == label && other.value == value;
  @override
  int get hashCode => Object.hash(label, value);
}

/// A document's fiscal block — the server-driven contract (docs/pos-blueprint/FISCAL_CONTRACT.md, G6.1). Statuses:
/// `not_required` (also the live `not_enabled`) → nothing; `pending` → not fiscalised yet, the server retries; `confirmed` → the server's lines + QR;
/// `failed` → not fiscalised and not retried automatically (the owner can retry); `rejected` → refused by the authority (final).
/// Unknown statuses are treated as not required (nothing printed) so a newer server never breaks an older app.
class PosFiscalInfo {
  const PosFiscalInfo({this.status = 'not_enabled', this.number, this.qrPayload, this.testMode = false, this.displayLines = const [], this.message, this.willRetry = false, this.logoUrl});
  final String status;
  final String? number;
  final String? qrPayload;
  final bool testMode;
  final List<FiscalLine> displayLines;
  final String? message;
  final bool willRetry;
  final String? logoUrl;

  static const knownStatuses = {'pending', 'confirmed', 'failed', 'rejected'};
  /// the store fiscalises this document (anything but not_required / not_enabled / unknown)
  bool get required => knownStatuses.contains(status);
  bool get confirmed => status == 'confirmed' && (number != null || displayLines.isNotEmpty);
  bool get pending => status == 'pending';
  bool get failed => status == 'failed';
  bool get rejected => status == 'rejected';
  bool get needsAttention => failed || rejected;

  static PosFiscalInfo? fromJson(dynamic j) => j is Map
      ? PosFiscalInfo(
          status: (j['status'] as String?) ?? 'not_enabled',
          number: j['externalInvoiceNumber'] as String?,
          qrPayload: j['qrPayload'] as String?,
          testMode: j['testMode'] == true,
          displayLines: [for (final l in (j['displayLines'] as List? ?? const [])) ?FiscalLine.fromJson(l)],
          message: j['message'] as String?,
          willRetry: j['willRetry'] == true,
          logoUrl: j['logoUrl'] as String?,
        )
      : null;
}

/// A credit note: the document every return and void produces (own per-store number, linked to the original invoice and lines).
/// Money is in minor units of [currency] ([exponent] decimals) — exactly as the server stored it.
class PosCreditNoteLine {
  final String name;
  final String sku;
  final String? hsCode;
  final int qty;
  final int netMinor;
  final int taxMinor;
  final int totalMinor;
  final bool restock;
  final String? restockReason;
  const PosCreditNoteLine({required this.name, required this.sku, this.hsCode, required this.qty, required this.netMinor, required this.taxMinor, required this.totalMinor, this.restock = true, this.restockReason});

  factory PosCreditNoteLine.fromJson(Map<String, dynamic> j) => PosCreditNoteLine(
        name: j['name'] as String? ?? '',
        sku: j['sku'] as String? ?? '',
        hsCode: j['hsCode'] as String?,
        qty: (j['qty'] as num?)?.toInt() ?? 0,
        netMinor: (j['netMinor'] as num?)?.toInt() ?? 0,
        taxMinor: (j['taxMinor'] as num?)?.toInt() ?? 0,
        totalMinor: (j['totalMinor'] as num?)?.toInt() ?? 0,
        restock: j['restock'] as bool? ?? true,
        restockReason: j['restockReason'] as String?,
      );
}

class PosCreditNote {
  final String id;
  final String number;
  final String? invoiceNumber;
  final String kind; // return | void
  final String scope; // partial | full
  final String? reasonCode;
  final String? reason;
  final List<PosCreditNoteLine> lines;
  final int netMinor;
  final int taxMinor;
  final int totalMinor;
  final String currency;
  final int exponent;
  final List<({String method, int amountMinor})> tenders;
  final DateTime? createdAt;
  final String? approvedBy;
  final List<String> approvalReasons;
  final String? sellerName;
  final String? sellerNtn;
  /// G6.1: the seller's tax identifiers as the server labels them; absent → NTN / STRN
  final List<FiscalLine> sellerTaxIds;
  List<FiscalLine> get sellerTaxLines => sellerTaxIds.isNotEmpty
      ? sellerTaxIds
      : [if ((sellerNtn ?? '').isNotEmpty) FiscalLine('NTN', sellerNtn!), if ((sellerStrn ?? '').isNotEmpty) FiscalLine('STRN', sellerStrn!)];
  final String? sellerStrn;
  final String? sellerAddress;
  /// Set only on a note made by the one-off backfill of pre-G2.5 refunds / voids (series `CN-B…`): when it was backfilled and which refund / void it stands for.
  final DateTime? backfilledAt;
  final String? backfilledFrom;

  /// G4.9: printed at least once (its original is out) — the next print is a reprint
  final bool printed;

  /// G5.5: the fiscal block (null when the server did not send one)
  final PosFiscalInfo? fiscal;

  const PosCreditNote({
    required this.id,
    required this.number,
    this.invoiceNumber,
    required this.kind,
    required this.scope,
    this.reasonCode,
    this.reason,
    this.lines = const [],
    required this.netMinor,
    required this.taxMinor,
    required this.totalMinor,
    required this.currency,
    required this.exponent,
    this.tenders = const [],
    this.createdAt,
    this.approvedBy,
    this.approvalReasons = const [],
    this.sellerName,
    this.sellerNtn,
    this.sellerTaxIds = const [],
    this.sellerStrn,
    this.sellerAddress,
    this.backfilledAt,
    this.backfilledFrom,
    this.printed = false,
    this.fiscal,
  });

  factory PosCreditNote.fromJson(Map<String, dynamic> j) {
    final seller = (j['seller'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PosCreditNote(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      number: j['number'] as String? ?? '',
      invoiceNumber: j['invoiceNumber'] as String?,
      kind: j['kind'] as String? ?? 'return',
      scope: j['scope'] as String? ?? 'partial',
      reasonCode: j['reasonCode'] as String?,
      reason: j['reason'] as String?,
      lines: (j['lines'] as List? ?? const []).map((e) => PosCreditNoteLine.fromJson((e as Map).cast<String, dynamic>())).toList(),
      netMinor: (j['netMinor'] as num?)?.toInt() ?? 0,
      taxMinor: (j['taxMinor'] as num?)?.toInt() ?? 0,
      totalMinor: (j['totalMinor'] as num?)?.toInt() ?? 0,
      currency: (j['currency'] as String?)?.toUpperCase() ?? 'USD',
      exponent: (j['currencyExponent'] as num?)?.toInt() ?? 2,
      tenders: [for (final t in (j['tenders'] as List? ?? const [])) (method: (t as Map)['method'] as String? ?? 'other', amountMinor: (t['amountMinor'] as num?)?.toInt() ?? 0)],
      createdAt: j['createdAt'] != null ? DateTime.tryParse(j['createdAt'].toString()) : null,
      approvedBy: j['approvedBy'] as String?,
      approvalReasons: [for (final r in (j['approvalReasons'] as List? ?? const [])) r.toString()],
      sellerName: seller['legalName'] as String?,
      sellerNtn: seller['ntn'] as String?,
      sellerTaxIds: [for (final t in (seller['taxIds'] as List? ?? const [])) ?FiscalLine.fromJson(t)],
      sellerStrn: seller['strn'] as String?,
      sellerAddress: seller['address'] as String?,
      backfilledAt: (j['backfill'] is Map && (j['backfill'] as Map)['backfilledAt'] != null) ? DateTime.tryParse((j['backfill'] as Map)['backfilledAt'].toString()) : null,
      backfilledFrom: (j['backfill'] is Map) ? '${(j['backfill'] as Map)['originalType']} ${(j['backfill'] as Map)['originalId']}' : null,
      printed: j['printed'] == true,
      fiscal: PosFiscalInfo.fromJson(j['fiscal']),
    );
  }
}

/// What `GET pos/sales/:id/documents` returns: the invoice header plus every credit note.
class PosSaleDocuments {
  final String saleNumber;
  final String status;
  final Map<String, dynamic>? invoiceJson;
  final List<PosCreditNote> creditNotes;
  const PosSaleDocuments({required this.saleNumber, required this.status, this.invoiceJson, this.creditNotes = const []});

  /// G4.9: the tax invoice has been printed at least once (its original is out)
  bool get invoicePrinted => invoiceJson?['printed'] == true;

  /// G5.5: the invoice's fiscal block (the latest attempt)
  PosFiscalInfo? get invoiceFiscal => PosFiscalInfo.fromJson(invoiceJson?['fiscal']);

  factory PosSaleDocuments.fromJson(Map<String, dynamic> j) => PosSaleDocuments(
        saleNumber: j['saleNumber'] as String? ?? '',
        status: j['status'] as String? ?? '',
        invoiceJson: (j['invoice'] as Map?)?.cast<String, dynamic>(),
        creditNotes: (j['creditNotes'] as List? ?? const []).map((e) => PosCreditNote.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );
}
