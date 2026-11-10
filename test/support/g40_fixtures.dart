// G4.0 / G4.1 fixtures: server-shaped JSON of the pulse, the eight reports and the store time zone (PKR, exponent 2, Asia/Karachi by default).
import 'package:solvexo_pos/app/data/models/pos/pos_biz_report_models.dart';

Map<String, dynamic> head({String from = '2026-11-02', String to = '2026-11-08', int days = 7, String currency = 'PKR', int exponent = 2, String tz = 'Asia/Karachi'}) => {
  'currency': currency,
  'currencyExponent': exponent,
  'timeZone': tz,
  'period': {'from': from, 'to': to, 'days': days},
  'filters': <String, dynamic>{},
};

Map<String, dynamic> salesTotalsJson({int tx = 4, int net = 9000, int gross = 11000}) => {
  'transactions': tx,
  'grossSalesMinor': gross,
  'taxMinor': 1000,
  'discountMinor': 250,
  'returns': tx == 0 ? 0 : 1,
  'returnsMinor': tx == 0 ? 0 : 1100,
  'returnsNetMinor': 1000,
  'returnsTaxMinor': 100,
  'averageBasketMinor': tx == 0 ? 0 : gross ~/ tx,
  'netSalesMinor': net,
  'netSalesInclTaxMinor': gross - 1100,
};

Map<String, dynamic> salesJson({bool compare = false, bool empty = false, String from = '2026-11-02', String to = '2026-11-04'}) => {
  ...head(from: from, to: to, days: 3),
  'totals': empty ? salesTotalsJson(tx: 0, net: 0, gross: 0) : salesTotalsJson(),
  'previous': compare
      ? {
          'period': {'from': '2026-10-30', 'to': '2026-11-01'},
          'totals': salesTotalsJson(tx: 2, net: 6000, gross: 6600),
        }
      : null,
  'byDay': [
    {'day': from, 'transactions': empty ? 0 : 2, 'totalMinor': empty ? 0 : 5500},
    {'day': '2026-11-03', 'transactions': empty ? 0 : 2, 'totalMinor': empty ? 0 : 5500},
    {'day': to, 'transactions': 0, 'totalMinor': 0},
  ],
};

Map<String, dynamic> profitTotalsJson({double coverage = 88.9}) => {
  'netSalesMinor': 9000,
  'costOfGoodsSoldMinor': 3800,
  'grossMarginMinor': 4200,
  'marginPercent': 52.5,
  'costCoveragePercent': coverage,
  'costUnknownNetMinor': coverage >= 100 ? 0 : 1000,
  'expensesMinor': 500,
  'expensesByCategoryMinor': {'utilities': 500},
  'afterExpensesMinor': 3700,
  'supplierPaymentsMinor': 50000,
  'supplierPaymentsNote': 'Supplier payments are not expenses: the cost of the goods is already counted when they are sold (COGS).',
};

Map<String, dynamic> profitJson({double coverage = 88.9, bool compare = false}) => {
  ...head(),
  'labels': {'grossMargin': 'Gross margin (net sales − cost of goods sold at weighted-average cost)', 'afterExpenses': 'After expenses (gross margin − recorded expenses; supplier payments excluded)'},
  'totals': profitTotalsJson(coverage: coverage),
  'previous': compare
      ? {
          'period': {'from': '2026-10-26', 'to': '2026-11-01'},
          'totals': profitTotalsJson(coverage: 100),
        }
      : null,
};

Map<String, dynamic> productsJson({bool empty = false}) => {
  ...head(),
  'products': empty
      ? []
      : [
          {
            'variantId': 'v1',
            'productId': 'p1',
            'name': 'Green tea',
            'sku': 'TEA-1',
            'qtySold': 10,
            'qtyReturned': 1,
            'netSalesMinor': 9000,
            'costMinor': 3800,
            'grossMarginMinor': 4200,
            'marginPercent': 52.5,
            'costCoveragePercent': 88.9,
          },
          {
            'variantId': null,
            'productId': null,
            'name': 'Custom items',
            'sku': null,
            'qtySold': 2,
            'qtyReturned': 0,
            'netSalesMinor': 800,
            'costMinor': 0,
            'grossMarginMinor': 0,
            'marginPercent': null,
            'costCoveragePercent': 0,
          },
        ],
  'count': empty ? 0 : 2,
};

Map<String, dynamic> categoriesJson() => {
  ...head(),
  'categories': [
    {'categoryId': 'c1', 'name': 'Drinks', 'qty': 10, 'netSalesMinor': 9000, 'costMinor': 3800, 'grossMarginMinor': 4200, 'marginPercent': 52.5},
    {'categoryId': null, 'name': 'Custom items', 'qty': 2, 'netSalesMinor': 800, 'costMinor': 0, 'grossMarginMinor': 0, 'marginPercent': null},
  ],
};

Map<String, dynamic> taxJson() => {
  ...head(),
  'rows': [
    {'taxCategory': 'standard', 'hsCode': '0902.1000', 'salesNetMinor': 10000, 'salesTaxMinor': 1000, 'returnsNetMinor': 1000, 'returnsTaxMinor': 100, 'netMinor': 9000, 'taxMinor': 900},
    {'taxCategory': 'exempt', 'hsCode': null, 'salesNetMinor': 500, 'salesTaxMinor': 0, 'returnsNetMinor': 0, 'returnsTaxMinor': 0, 'netMinor': 500, 'taxMinor': 0},
  ],
  'totals': {'salesTaxMinor': 1000, 'returnsTaxMinor': 100, 'netTaxMinor': 900, 'invoices': 4, 'creditNotes': 1, 'invoiceTaxMinor': 1000, 'creditNoteTaxMinor': 100},
};

Map<String, dynamic> paymentsJson({bool empty = false}) => {
  ...head(),
  'methods': empty
      ? []
      : [
          {'method': 'cash', 'payments': 3, 'paidMinor': 8800, 'refundedMinor': 1100, 'netMinor': 7700, 'sharePercent': 77.8},
          {'method': 'card', 'payments': 1, 'paidMinor': 2200, 'refundedMinor': 0, 'netMinor': 2200, 'sharePercent': 22.2},
        ],
  'netMinor': empty ? 0 : 9900,
};

Map<String, dynamic> cashierJson(String id, String name, {int tx = 3, int net = 5000}) => {
  'employeeId': id,
  'name': name,
  'role': 'cashier',
  'lastLoginAt': null,
  'transactions': tx,
  'salesMinor': net + 500,
  'netSalesMinor': net,
  'averageBasketMinor': tx == 0 ? 0 : (net + 500) ~/ tx,
  'discountsMinor': 100,
  'returnsProcessed': 1,
  'returnsNetMinor': 1000,
  'voids': 0,
  'voidsMinor': 0,
  'workedMinutes': 480,
};

Map<String, dynamic> cashiersJson({bool ownOnly = false}) => {
  ...head(),
  'ownOnly': ownOnly,
  'cashiers': ownOnly ? [cashierJson('e1', 'Cal Cashier')] : [cashierJson('e1', 'Cal Cashier'), cashierJson('e2', 'Mia Manager', tx: 1, net: 4000)],
};

Map<String, dynamic> hourlyJson({bool empty = false}) {
  final byHour = [
    for (var h = 0; h < 24; h++) {'hour': h, 'transactions': 0, 'totalMinor': 0},
  ];
  final heat = [
    for (var d = 1; d <= 7; d++) {'isoWeekday': d, 'hours': List<int>.filled(24, 0)},
  ];
  if (!empty) {
    byHour[10] = {'hour': 10, 'transactions': 1, 'totalMinor': 3300};
    byHour[15] = {'hour': 15, 'transactions': 2, 'totalMinor': 6600};
    (heat[0]['hours'] as List<int>)[10] = 3300;
    (heat[1]['hours'] as List<int>)[15] = 6600;
  }
  return {...head(), 'byHour': byHour, 'weekdayHourMinor': heat, 'busiestHour': empty ? null : 15};
}

Map<String, dynamic> reportJson(ReportKind k) => switch (k) {
  ReportKind.sales => salesJson(),
  ReportKind.profit => profitJson(),
  ReportKind.products => productsJson(),
  ReportKind.categories => categoriesJson(),
  ReportKind.tax => taxJson(),
  ReportKind.payments => paymentsJson(),
  ReportKind.cashiers => cashiersJson(),
  ReportKind.hourly => hourlyJson(),
};

BizReport report(ReportKind k) => parseBizReport(k, reportJson(k));

Map<String, dynamic> pulseJson({bool empty = false}) => {
  ...head(from: '2026-11-10', to: '2026-11-10', days: 1),
  'asOf': DateTime(2026, 11, 10, 15, 30).toUtc().toIso8601String(),
  'comparedWith': {'day': '2026-11-03', 'upTo': DateTime(2026, 11, 3, 15, 30).toUtc().toIso8601String()},
  'today': {
    'netSalesMinor': empty ? 0 : 2000,
    'transactions': empty ? 0 : 1,
    'averageBasketMinor': empty ? 0 : 2200,
    'grossMarginMinor': 1200,
    'cashMinor': 2200,
    'cardMinor': 0,
    'returnsMinor': 0,
    'expensesMinor': 300,
  },
  'sameDayLastWeek': {'netSalesMinor': 1000, 'transactions': 1, 'averageBasketMinor': 1100, 'grossMarginMinor': 600, 'cashMinor': 1100, 'cardMinor': 0, 'returnsMinor': 0, 'expensesMinor': 100},
  'changePercent': {
    'netSalesMinor': empty ? -100 : 100,
    'transactions': 0,
    'averageBasketMinor': 100,
    'grossMarginMinor': 100,
    'cashMinor': 100,
    'cardMinor': null,
    'returnsMinor': null,
    'expensesMinor': 200,
  },
  'topProducts': empty
      ? []
      : [
          {'variantId': 'v1', 'name': 'Green tea', 'qty': 2, 'netSalesMinor': 2000},
        ],
  'lowStockCount': 3,
  'clockedInNow': 2,
};

BusinessPulse pulse({bool empty = false}) => BusinessPulse.fromJson(pulseJson(empty: empty));

Map<String, dynamic> zoneJson({String tz = 'Asia/Karachi', bool explicit = false, String today = '2026-11-10'}) => {'timeZone': tz, 'explicit': explicit, 'country': 'PK', 'today': today};
StoreTimeZone zone({String tz = 'Asia/Karachi', bool explicit = false, String today = '2026-11-10'}) => StoreTimeZone.fromJson(zoneJson(tz: tz, explicit: explicit, today: today));
