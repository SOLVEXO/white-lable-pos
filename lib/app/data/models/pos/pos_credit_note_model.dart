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
  final String? sellerStrn;
  final String? sellerAddress;

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
    this.sellerStrn,
    this.sellerAddress,
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
      sellerStrn: seller['strn'] as String?,
      sellerAddress: seller['address'] as String?,
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

  factory PosSaleDocuments.fromJson(Map<String, dynamic> j) => PosSaleDocuments(
        saleNumber: j['saleNumber'] as String? ?? '',
        status: j['status'] as String? ?? '',
        invoiceJson: (j['invoice'] as Map?)?.cast<String, dynamic>(),
        creditNotes: (j['creditNotes'] as List? ?? const []).map((e) => PosCreditNote.fromJson((e as Map).cast<String, dynamic>())).toList(),
      );
}
