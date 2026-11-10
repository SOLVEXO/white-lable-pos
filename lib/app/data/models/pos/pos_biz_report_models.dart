import 'package:solvexo_pos/app/data/models/pos/pos_inventory_models.dart';

/// G4.0 / G4.1 read models: the business pulse, the eight reports and the store time zone. Every report response states its currency + exponent,
/// the store's time zone and the period (store days, `YYYY-MM-DD`); money stays integer MINOR units and is shown through [InvCur] only.

int _int(dynamic v) => v is num ? v.toInt() : 0;
int? _intN(dynamic v) => v is num ? v.toInt() : null;
double? _dbl(dynamic v) => v is num ? v.toDouble() : null;
String? _str(dynamic v) {
  if (v == null) return null;
  final s = '$v';
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e is Map) e.cast<String, dynamic>(),
      ]
    : const [];
Map<String, dynamic> _map(dynamic v) => v is Map ? v.cast<String, dynamic>() : const {};

/// `YYYY-MM-DD` of a calendar date (no time zone: a store day is a label, not an instant).
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// The calendar date of a `YYYY-MM-DD` key (midnight, local — used only for date arithmetic and labels).
DateTime? parseDayKey(String? k) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(k ?? '');
  return m == null ? null : DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

/// What every report response carries.
class ReportHead {
  const ReportHead({this.cur, this.timeZone, required this.from, required this.to, this.days = 1});
  final InvCur? cur;
  final String? timeZone;
  final String from, to;
  final int days;

  factory ReportHead.fromJson(Map<String, dynamic> j) {
    final p = _map(j['period']);
    return ReportHead(cur: InvCur.fromJson(j), timeZone: _str(j['timeZone']), from: '${p['from'] ?? ''}', to: '${p['to'] ?? ''}', days: _intN(p['days']) ?? 1);
  }

  String money(int minor) => cur == null ? '—' : cur!.format(minor);
}

/// The query of a report: store days (inclusive) plus the optional comparison and filters the server supports.
class ReportQuery {
  const ReportQuery({required this.from, required this.to, this.compare = false, this.registerId, this.employeeId, this.locationId});
  final String from, to;
  final bool compare;
  final String? registerId, employeeId, locationId;

  Map<String, dynamic> toQuery() => {
    'from': from,
    'to': to,
    if (compare) 'compare': 'previous',
    if (registerId != null) 'registerId': registerId,
    if (employeeId != null) 'employeeId': employeeId,
    if (locationId != null) 'locationId': locationId,
  };
}

/// One of the eight reports (the screen, the export and the repository share this list).
enum ReportKind {
  sales('sales', 'Sales'),
  profit('profit', 'Profit'),
  products('products', 'Products'),
  categories('categories', 'Categories'),
  tax('tax', 'Tax'),
  payments('payments', 'Payment mix'),
  cashiers('cashiers', 'Cashiers'),
  hourly('hourly', 'Hourly');

  const ReportKind(this.path, this.label);
  final String path, label;

  static ReportKind? byPath(String? p) => ReportKind.values.where((k) => k.path == p).firstOrNull;
}

sealed class BizReport {
  const BizReport(this.head);
  final ReportHead head;
  ReportKind get kind;
}

// ── 1 · sales ─────────────────────────────────────────────────────────────────
class SalesTotals {
  const SalesTotals({
    this.transactions = 0,
    this.grossSalesMinor = 0,
    this.taxMinor = 0,
    this.discountMinor = 0,
    this.returns = 0,
    this.returnsMinor = 0,
    this.returnsNetMinor = 0,
    this.averageBasketMinor = 0,
    this.netSalesMinor = 0,
    this.netSalesInclTaxMinor = 0,
  });
  final int transactions, grossSalesMinor, taxMinor, discountMinor, returns, returnsMinor, returnsNetMinor, averageBasketMinor, netSalesMinor, netSalesInclTaxMinor;

  factory SalesTotals.fromJson(Map<String, dynamic> j) => SalesTotals(
    transactions: _int(j['transactions']),
    grossSalesMinor: _int(j['grossSalesMinor']),
    taxMinor: _int(j['taxMinor']),
    discountMinor: _int(j['discountMinor']),
    returns: _int(j['returns']),
    returnsMinor: _int(j['returnsMinor']),
    returnsNetMinor: _int(j['returnsNetMinor']),
    averageBasketMinor: _int(j['averageBasketMinor']),
    netSalesMinor: _int(j['netSalesMinor']),
    netSalesInclTaxMinor: _int(j['netSalesInclTaxMinor']),
  );
}

class DayPoint {
  const DayPoint(this.day, this.transactions, this.totalMinor);
  final String day;
  final int transactions, totalMinor;
}

class SalesReport extends BizReport {
  const SalesReport(super.head, {required this.totals, this.previous, this.previousFrom, this.previousTo, this.byDay = const [], this.previousByDay = const []});
  final SalesTotals totals;
  final SalesTotals? previous;
  final String? previousFrom, previousTo;
  final List<DayPoint> byDay;

  /// the previous period's days (sent with `compare=previous`) — the dashed line
  final List<DayPoint> previousByDay;
  @override
  ReportKind get kind => ReportKind.sales;

  factory SalesReport.fromJson(Map<String, dynamic> j) {
    final prev = j['previous'] is Map ? _map(j['previous']) : null;
    return SalesReport(
      ReportHead.fromJson(j),
      totals: SalesTotals.fromJson(_map(j['totals'])),
      previous: prev == null ? null : SalesTotals.fromJson(_map(prev['totals'])),
      previousFrom: prev == null ? null : _str(_map(prev['period'])['from']),
      previousTo: prev == null ? null : _str(_map(prev['period'])['to']),
      byDay: [for (final d in _maps(j['byDay'])) DayPoint('${d['day'] ?? ''}', _int(d['transactions']), _int(d['totalMinor']))],
      previousByDay: prev == null ? const [] : [for (final d in _maps(prev['byDay'])) DayPoint('${d['day'] ?? ''}', _int(d['transactions']), _int(d['totalMinor']))],
    );
  }
}

// ── 2 · profit ────────────────────────────────────────────────────────────────
class ProfitTotals {
  const ProfitTotals({
    this.netSalesMinor = 0,
    this.costOfGoodsSoldMinor = 0,
    this.grossMarginMinor = 0,
    this.marginPercent,
    this.costCoveragePercent,
    this.costUnknownNetMinor = 0,
    this.expensesMinor = 0,
    this.expensesByCategoryMinor = const {},
    this.afterExpensesMinor = 0,
    this.supplierPaymentsMinor = 0,
    this.supplierPaymentsNote,
  });
  final int netSalesMinor, costOfGoodsSoldMinor, grossMarginMinor, costUnknownNetMinor, expensesMinor, afterExpensesMinor, supplierPaymentsMinor;
  final double? marginPercent, costCoveragePercent;
  final Map<String, int> expensesByCategoryMinor;
  final String? supplierPaymentsNote;

  /// some of the net sales have no known cost, so the margin covers only part of them
  bool get partialCoverage => costCoveragePercent != null && costCoveragePercent! < 100;

  factory ProfitTotals.fromJson(Map<String, dynamic> j) => ProfitTotals(
    netSalesMinor: _int(j['netSalesMinor']),
    costOfGoodsSoldMinor: _int(j['costOfGoodsSoldMinor']),
    grossMarginMinor: _int(j['grossMarginMinor']),
    marginPercent: _dbl(j['marginPercent']),
    costCoveragePercent: _dbl(j['costCoveragePercent']),
    costUnknownNetMinor: _int(j['costUnknownNetMinor']),
    expensesMinor: _int(j['expensesMinor']),
    expensesByCategoryMinor: {for (final e in _map(j['expensesByCategoryMinor']).entries) e.key: _int(e.value)},
    afterExpensesMinor: _int(j['afterExpensesMinor']),
    supplierPaymentsMinor: _int(j['supplierPaymentsMinor']),
    supplierPaymentsNote: _str(j['supplierPaymentsNote']),
  );
}

class ProfitReport extends BizReport {
  const ProfitReport(super.head, {required this.totals, this.previous, this.grossMarginLabel, this.afterExpensesLabel});
  final ProfitTotals totals;
  final ProfitTotals? previous;
  final String? grossMarginLabel, afterExpensesLabel;
  @override
  ReportKind get kind => ReportKind.profit;

  factory ProfitReport.fromJson(Map<String, dynamic> j) {
    final prev = j['previous'] is Map ? _map(j['previous']) : null;
    final labels = _map(j['labels']);
    return ProfitReport(
      ReportHead.fromJson(j),
      totals: ProfitTotals.fromJson(_map(j['totals'])),
      previous: prev == null ? null : ProfitTotals.fromJson(_map(prev['totals'])),
      grossMarginLabel: _str(labels['grossMargin']),
      afterExpensesLabel: _str(labels['afterExpenses']),
    );
  }
}

// ── 3 · products / 4 · categories ─────────────────────────────────────────────
class ProductRow {
  const ProductRow({
    this.variantId,
    this.productId,
    required this.name,
    this.sku,
    this.qtySold = 0,
    this.qtyReturned = 0,
    this.netSalesMinor = 0,
    this.costMinor = 0,
    this.grossMarginMinor = 0,
    this.marginPercent,
    this.costCoveragePercent,
  });
  final String? variantId, productId, sku;
  final String name;
  final num qtySold, qtyReturned;
  final int netSalesMinor, costMinor, grossMarginMinor;
  final double? marginPercent, costCoveragePercent;

  factory ProductRow.fromJson(Map<String, dynamic> j) => ProductRow(
    variantId: _str(j['variantId']),
    productId: _str(j['productId']),
    name: _str(j['name']) ?? 'Item',
    sku: _str(j['sku']),
    qtySold: j['qtySold'] is num ? j['qtySold'] as num : 0,
    qtyReturned: j['qtyReturned'] is num ? j['qtyReturned'] as num : 0,
    netSalesMinor: _int(j['netSalesMinor']),
    costMinor: _int(j['costMinor']),
    grossMarginMinor: _int(j['grossMarginMinor']),
    marginPercent: _dbl(j['marginPercent']),
    costCoveragePercent: _dbl(j['costCoveragePercent']),
  );
}

class ProductsReport extends BizReport {
  const ProductsReport(super.head, {this.products = const [], this.count = 0});
  final List<ProductRow> products;
  final int count;
  @override
  ReportKind get kind => ReportKind.products;
  factory ProductsReport.fromJson(Map<String, dynamic> j) => ProductsReport(ReportHead.fromJson(j), products: [for (final p in _maps(j['products'])) ProductRow.fromJson(p)], count: _int(j['count']));
}

class CategoryRow {
  const CategoryRow({this.categoryId, required this.name, this.qty = 0, this.netSalesMinor = 0, this.costMinor = 0, this.grossMarginMinor = 0, this.marginPercent});
  final String? categoryId;
  final String name;
  final num qty;
  final int netSalesMinor, costMinor, grossMarginMinor;
  final double? marginPercent;
  factory CategoryRow.fromJson(Map<String, dynamic> j) => CategoryRow(
    categoryId: _str(j['categoryId']),
    name: _str(j['name']) ?? 'Category',
    qty: j['qty'] is num ? j['qty'] as num : 0,
    netSalesMinor: _int(j['netSalesMinor']),
    costMinor: _int(j['costMinor']),
    grossMarginMinor: _int(j['grossMarginMinor']),
    marginPercent: _dbl(j['marginPercent']),
  );
}

class CategoriesReport extends BizReport {
  const CategoriesReport(super.head, {this.categories = const []});
  final List<CategoryRow> categories;
  @override
  ReportKind get kind => ReportKind.categories;
  factory CategoriesReport.fromJson(Map<String, dynamic> j) => CategoriesReport(ReportHead.fromJson(j), categories: [for (final c in _maps(j['categories'])) CategoryRow.fromJson(c)]);
}

// ── 5 · tax ───────────────────────────────────────────────────────────────────
class TaxRow {
  const TaxRow({required this.taxCategory, this.hsCode, this.salesNetMinor = 0, this.salesTaxMinor = 0, this.returnsNetMinor = 0, this.returnsTaxMinor = 0, this.netMinor = 0, this.taxMinor = 0});
  final String taxCategory;
  final String? hsCode;
  final int salesNetMinor, salesTaxMinor, returnsNetMinor, returnsTaxMinor, netMinor, taxMinor;
  factory TaxRow.fromJson(Map<String, dynamic> j) => TaxRow(
    taxCategory: _str(j['taxCategory']) ?? 'standard',
    hsCode: _str(j['hsCode']),
    salesNetMinor: _int(j['salesNetMinor']),
    salesTaxMinor: _int(j['salesTaxMinor']),
    returnsNetMinor: _int(j['returnsNetMinor']),
    returnsTaxMinor: _int(j['returnsTaxMinor']),
    netMinor: _int(j['netMinor']),
    taxMinor: _int(j['taxMinor']),
  );
}

class TaxTotals {
  const TaxTotals({this.salesTaxMinor = 0, this.returnsTaxMinor = 0, this.netTaxMinor = 0, this.invoices = 0, this.creditNotes = 0, this.invoiceTaxMinor = 0, this.creditNoteTaxMinor = 0});
  final int salesTaxMinor, returnsTaxMinor, netTaxMinor, invoices, creditNotes, invoiceTaxMinor, creditNoteTaxMinor;
  factory TaxTotals.fromJson(Map<String, dynamic> j) => TaxTotals(
    salesTaxMinor: _int(j['salesTaxMinor']),
    returnsTaxMinor: _int(j['returnsTaxMinor']),
    netTaxMinor: _int(j['netTaxMinor']),
    invoices: _int(j['invoices']),
    creditNotes: _int(j['creditNotes']),
    invoiceTaxMinor: _int(j['invoiceTaxMinor']),
    creditNoteTaxMinor: _int(j['creditNoteTaxMinor']),
  );
}

class TaxReport extends BizReport {
  const TaxReport(super.head, {this.rows = const [], this.totals = const TaxTotals()});
  final List<TaxRow> rows;
  final TaxTotals totals;
  @override
  ReportKind get kind => ReportKind.tax;
  factory TaxReport.fromJson(Map<String, dynamic> j) => TaxReport(ReportHead.fromJson(j), rows: [for (final r in _maps(j['rows'])) TaxRow.fromJson(r)], totals: TaxTotals.fromJson(_map(j['totals'])));
}

String taxCategoryLabel(String c) => switch (c) {
  'standard' => 'Standard rate',
  'zero' || 'zero_rated' => 'Zero rated',
  'exempt' => 'Exempt',
  'reduced' => 'Reduced rate',
  _ => c.isEmpty ? 'Standard rate' : '${c[0].toUpperCase()}${c.substring(1).replaceAll('_', ' ')}',
};

// ── 6 · payment mix ───────────────────────────────────────────────────────────
class PaymentRow {
  const PaymentRow({required this.method, this.payments = 0, this.paidMinor = 0, this.refundedMinor = 0, this.netMinor = 0, this.sharePercent = 0});
  final String method;
  final int payments, paidMinor, refundedMinor, netMinor;
  final double sharePercent;
  factory PaymentRow.fromJson(Map<String, dynamic> j) => PaymentRow(
    method: _str(j['method']) ?? 'other',
    payments: _int(j['payments']),
    paidMinor: _int(j['paidMinor']),
    refundedMinor: _int(j['refundedMinor']),
    netMinor: _int(j['netMinor']),
    sharePercent: _dbl(j['sharePercent']) ?? 0,
  );
}

String paymentMethodLabel(String m) => switch (m) {
  'cash' => 'Cash',
  'card' => 'Card',
  'raast' || 'raast_qr' => 'Raast QR',
  'store_credit' => 'Store credit',
  'split' => 'Split',
  'bank' || 'bank_transfer' => 'Bank transfer',
  'wallet' => 'Wallet',
  _ => m.isEmpty ? 'Other' : '${m[0].toUpperCase()}${m.substring(1).replaceAll('_', ' ')}',
};

class PaymentsReport extends BizReport {
  const PaymentsReport(super.head, {this.methods = const [], this.netMinor = 0});
  final List<PaymentRow> methods;
  final int netMinor;
  @override
  ReportKind get kind => ReportKind.payments;
  factory PaymentsReport.fromJson(Map<String, dynamic> j) =>
      PaymentsReport(ReportHead.fromJson(j), methods: [for (final m in _maps(j['methods'])) PaymentRow.fromJson(m)], netMinor: _int(j['netMinor']));
}

// ── 7 · cashiers ──────────────────────────────────────────────────────────────
class CashierRow {
  const CashierRow({
    required this.employeeId,
    required this.name,
    this.role,
    this.transactions = 0,
    this.salesMinor = 0,
    this.netSalesMinor = 0,
    this.averageBasketMinor = 0,
    this.discountsMinor = 0,
    this.returnsProcessed = 0,
    this.returnsNetMinor = 0,
    this.voids = 0,
    this.voidsMinor = 0,
    this.workedMinutes = 0,
  });
  final String employeeId, name;
  final String? role;
  final int transactions, salesMinor, netSalesMinor, averageBasketMinor, discountsMinor, returnsProcessed, returnsNetMinor, voids, voidsMinor, workedMinutes;
  factory CashierRow.fromJson(Map<String, dynamic> j) => CashierRow(
    employeeId: '${j['employeeId'] ?? ''}',
    name: _str(j['name']) ?? 'Team member',
    role: _str(j['role']),
    transactions: _int(j['transactions']),
    salesMinor: _int(j['salesMinor']),
    netSalesMinor: _int(j['netSalesMinor']),
    averageBasketMinor: _int(j['averageBasketMinor']),
    discountsMinor: _int(j['discountsMinor']),
    returnsProcessed: _int(j['returnsProcessed']),
    returnsNetMinor: _int(j['returnsNetMinor']),
    voids: _int(j['voids']),
    voidsMinor: _int(j['voidsMinor']),
    workedMinutes: _int(j['workedMinutes']),
  );
}

class CashiersReport extends BizReport {
  const CashiersReport(super.head, {this.cashiers = const [], this.ownOnly = false});
  final List<CashierRow> cashiers;
  final bool ownOnly;
  @override
  ReportKind get kind => ReportKind.cashiers;
  factory CashiersReport.fromJson(Map<String, dynamic> j) =>
      CashiersReport(ReportHead.fromJson(j), cashiers: [for (final c in _maps(j['cashiers'])) CashierRow.fromJson(c)], ownOnly: j['ownOnly'] == true);
}

// ── 8 · hourly ────────────────────────────────────────────────────────────────
class HourPoint {
  const HourPoint(this.hour, this.transactions, this.totalMinor);
  final int hour, transactions, totalMinor;
}

class HourlyReport extends BizReport {
  const HourlyReport(super.head, {this.byHour = const [], this.heat = const [], this.busiestHour});
  final List<HourPoint> byHour;

  /// 7 rows (Monday … Sunday) × 24 hours of sales, minor units
  final List<List<int>> heat;
  final int? busiestHour;
  @override
  ReportKind get kind => ReportKind.hourly;

  bool get isEmpty => byHour.every((h) => h.transactions == 0);

  factory HourlyReport.fromJson(Map<String, dynamic> j) {
    final heat = List.generate(7, (_) => List<int>.filled(24, 0));
    for (final row in _maps(j['weekdayHourMinor'])) {
      final d = _int(row['isoWeekday']);
      final hours = row['hours'];
      if (d < 1 || d > 7 || hours is! List) continue;
      for (var h = 0; h < 24 && h < hours.length; h++) {
        heat[d - 1][h] = _int(hours[h]);
      }
    }
    return HourlyReport(
      ReportHead.fromJson(j),
      byHour: [for (final h in _maps(j['byHour'])) HourPoint(_int(h['hour']), _int(h['transactions']), _int(h['totalMinor']))],
      heat: heat,
      busiestHour: _intN(j['busiestHour']),
    );
  }
}

BizReport parseBizReport(ReportKind k, Map<String, dynamic> j) => switch (k) {
  ReportKind.sales => SalesReport.fromJson(j),
  ReportKind.profit => ProfitReport.fromJson(j),
  ReportKind.products => ProductsReport.fromJson(j),
  ReportKind.categories => CategoriesReport.fromJson(j),
  ReportKind.tax => TaxReport.fromJson(j),
  ReportKind.payments => PaymentsReport.fromJson(j),
  ReportKind.cashiers => CashiersReport.fromJson(j),
  ReportKind.hourly => HourlyReport.fromJson(j),
};

// ── business pulse ────────────────────────────────────────────────────────────
class PulseFigures {
  const PulseFigures({
    this.netSalesMinor = 0,
    this.transactions = 0,
    this.averageBasketMinor = 0,
    this.grossMarginMinor = 0,
    this.cashMinor = 0,
    this.cardMinor = 0,
    this.returnsMinor = 0,
    this.expensesMinor = 0,
  });
  final int netSalesMinor, transactions, averageBasketMinor, grossMarginMinor, cashMinor, cardMinor, returnsMinor, expensesMinor;
  factory PulseFigures.fromJson(Map<String, dynamic> j) => PulseFigures(
    netSalesMinor: _int(j['netSalesMinor']),
    transactions: _int(j['transactions']),
    averageBasketMinor: _int(j['averageBasketMinor']),
    grossMarginMinor: _int(j['grossMarginMinor']),
    cashMinor: _int(j['cashMinor']),
    cardMinor: _int(j['cardMinor']),
    returnsMinor: _int(j['returnsMinor']),
    expensesMinor: _int(j['expensesMinor']),
  );
}

class PulseTopProduct {
  const PulseTopProduct({this.variantId, required this.name, this.qty = 0, this.netSalesMinor = 0});
  final String? variantId;
  final String name;
  final num qty;
  final int netSalesMinor;
}

class BusinessPulse {
  const BusinessPulse({
    required this.head,
    required this.today,
    required this.lastWeek,
    this.comparedDay,
    this.asOf,
    this.change = const {},
    this.topProducts = const [],
    this.lowStockCount = 0,
    this.clockedInNow = 0,
  });
  final ReportHead head;
  final PulseFigures today, lastWeek;
  final String? comparedDay;
  final DateTime? asOf;

  /// per figure (`netSalesMinor`, `transactions` …) the change in percent against the same weekday last week; null = nothing to compare with
  final Map<String, double?> change;
  final List<PulseTopProduct> topProducts;
  final int lowStockCount, clockedInNow;

  factory BusinessPulse.fromJson(Map<String, dynamic> j) => BusinessPulse(
    head: ReportHead.fromJson(j),
    today: PulseFigures.fromJson(_map(j['today'])),
    lastWeek: PulseFigures.fromJson(_map(j['sameDayLastWeek'])),
    comparedDay: _str(_map(j['comparedWith'])['day']),
    asOf: DateTime.tryParse('${j['asOf'] ?? ''}')?.toLocal(),
    change: {for (final e in _map(j['changePercent']).entries) e.key: _dbl(e.value)},
    topProducts: [
      for (final p in _maps(j['topProducts']))
        PulseTopProduct(variantId: _str(p['variantId']), name: _str(p['name']) ?? 'Item', qty: p['qty'] is num ? p['qty'] as num : 0, netSalesMinor: _int(p['netSalesMinor'])),
    ],
    lowStockCount: _int(j['lowStockCount']),
    clockedInNow: _int(j['clockedInNow']),
  );
}

// ── store time zone ───────────────────────────────────────────────────────────
class StoreTimeZone {
  const StoreTimeZone({required this.timeZone, this.explicit = false, this.country, required this.today});
  final String timeZone;
  final bool explicit;
  final String? country;

  /// today's date in the store's zone, `YYYY-MM-DD` — the base of every default report period
  final String today;

  factory StoreTimeZone.fromJson(Map<String, dynamic> j) =>
      StoreTimeZone(timeZone: _str(j['timeZone']) ?? 'UTC', explicit: j['explicit'] == true, country: _str(j['country']), today: _str(j['today']) ?? dayKey(DateTime.now()));
}

/// A server refusal in words.
String reportErrorMessage(String? code, {String? fallback}) => switch (code) {
  'POS_ACTION_FORBIDDEN' => 'Your role is not allowed to see this.',
  'POS_PIN_REQUIRED' => 'Sign in with your PIN first.',
  'RANGE_INVALID' => 'The end of the period is before its start.',
  'RANGE_TOO_LONG' => 'A report covers at most 366 days. Choose a shorter period.',
  'INVALID_TIME_ZONE' => 'That is not a valid time zone. Choose one from the list (for example Asia/Karachi).',
  _ => fallback ?? 'Something went wrong. Please try again.',
};
