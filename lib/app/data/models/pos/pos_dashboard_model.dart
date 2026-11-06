/// The Home business pulse, exactly as the server answers `GET pos/dashboard/:storeId` (role-based there: a cashier gets only their own shift).
class PosDashboard {
  final String role; // cashier | manager | owner
  final bool isShiftScope;
  final String currency;
  final int exponent;
  final double revenue;
  final double netRevenue;
  final int orders;
  final double average;
  final double refunds;
  final int refundsCount;
  final List<({String name, int qty, double revenue})> topProducts;
  final List<({String method, int count, double total})> paymentMix;
  final List<({String name, int stock})> lowStock;
  final int lowStockCount;
  final List<({String? employeeName, DateTime? openedAt, double totalSales, int transactions})> shifts;
  final int salesNeedingReview;
  final int digitalAttention;
  final bool showsAttention;

  const PosDashboard({
    required this.role,
    required this.isShiftScope,
    required this.currency,
    required this.exponent,
    required this.revenue,
    required this.netRevenue,
    required this.orders,
    required this.average,
    required this.refunds,
    required this.refundsCount,
    this.topProducts = const [],
    this.paymentMix = const [],
    this.lowStock = const [],
    this.lowStockCount = 0,
    this.shifts = const [],
    this.salesNeedingReview = 0,
    this.digitalAttention = 0,
    this.showsAttention = false,
  });

  int get attentionTotal => salesNeedingReview + digitalAttention;

  factory PosDashboard.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => (v as num?)?.toDouble() ?? 0;
    final s = (j['summary'] as Map?)?.cast<String, dynamic>() ?? const {};
    final pay = (j['byPaymentMethod'] as Map?)?.cast<String, dynamic>() ?? const {};
    final low = (j['lowStock'] as Map?)?.cast<String, dynamic>();
    final att = (j['needsAttention'] as Map?)?.cast<String, dynamic>();
    return PosDashboard(
      role: j['role'] as String? ?? 'owner',
      isShiftScope: j['scope'] == 'shift',
      currency: (j['currency'] as String?)?.toUpperCase() ?? 'USD',
      exponent: (j['currencyExponent'] as num?)?.toInt() ?? 2,
      revenue: d(s['totalRevenue']),
      netRevenue: d(s['netRevenue']),
      orders: (s['totalTransactions'] as num?)?.toInt() ?? 0,
      average: d(s['avgTransactionValue']),
      refunds: d(s['refundsTotal']),
      refundsCount: (s['refundsCount'] as num?)?.toInt() ?? 0,
      topProducts: [for (final p in (j['topProducts'] as List? ?? const [])) (name: (p as Map)['name'] as String? ?? '', qty: (p['qty'] as num?)?.toInt() ?? 0, revenue: d(p['revenue']))],
      paymentMix: [
        for (final e in pay.entries)
          if (((e.value as Map)['count'] as num? ?? 0) > 0) (method: e.key, count: ((e.value as Map)['count'] as num).toInt(), total: d((e.value as Map)['total'])),
      ],
      lowStock: [for (final p in (low?['items'] as List? ?? const [])) (name: (p as Map)['name'] as String? ?? '', stock: (p['stock'] as num?)?.toInt() ?? 0)],
      lowStockCount: (low?['count'] as num?)?.toInt() ?? ((low?['items'] as List?)?.length ?? 0),
      shifts: [
        for (final x in (j['shifts'] as List? ?? const []))
          (employeeName: (x as Map)['employeeName'] as String?, openedAt: x['openedAt'] != null ? DateTime.tryParse(x['openedAt'].toString()) : null, totalSales: d(x['totalSales']), transactions: (x['totalTransactions'] as num?)?.toInt() ?? 0),
      ],
      salesNeedingReview: (att?['salesNeedingReview'] as num?)?.toInt() ?? 0,
      digitalAttention: (att?['digitalPayments'] as num?)?.toInt() ?? 0,
      showsAttention: att != null,
    );
  }
}
