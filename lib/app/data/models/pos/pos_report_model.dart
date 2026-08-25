import 'package:solvexo_pos/app/data/models/pos/pos_employee_model.dart';
import 'package:solvexo_pos/app/data/models/pos/pos_session_model.dart';
import 'package:solvexo_pos/app/data/models/common_models/store_model.dart';

/// Shared { count, total } shape used by every report's payment-method split.
class PosPaymentMethodStat {
  final int count;
  final double total;

  const PosPaymentMethodStat({required this.count, required this.total});

  static const zero = PosPaymentMethodStat(count: 0, total: 0);

  factory PosPaymentMethodStat.fromJson(Map<String, dynamic>? json) =>
      json == null
          ? zero
          : PosPaymentMethodStat(
              count: json['count'] as int? ?? 0,
              total: (json['total'] as num?)?.toDouble() ?? 0,
            );
}

class PosPaymentBreakdown {
  final PosPaymentMethodStat cash;
  final PosPaymentMethodStat card;
  final PosPaymentMethodStat other;

  const PosPaymentBreakdown({
    required this.cash,
    required this.card,
    required this.other,
  });

  double get total => cash.total + card.total + other.total;

  factory PosPaymentBreakdown.fromJson(Map<String, dynamic>? json) =>
      PosPaymentBreakdown(
        cash: PosPaymentMethodStat.fromJson(json?['cash'] as Map<String, dynamic>?),
        card: PosPaymentMethodStat.fromJson(json?['card'] as Map<String, dynamic>?),
        other: PosPaymentMethodStat.fromJson(json?['other'] as Map<String, dynamic>?),
      );
}

class PosTopProduct {
  final String productId;
  final String name;
  final int qty;
  final double revenue;

  const PosTopProduct({
    required this.productId,
    required this.name,
    required this.qty,
    required this.revenue,
  });

  factory PosTopProduct.fromJson(Map<String, dynamic> json) => PosTopProduct(
        productId: json['productId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        qty: json['qty'] as int? ?? 0,
        revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      );
}

class PosHourlyBucket {
  final int hour;
  final String label;
  final double total;

  const PosHourlyBucket({required this.hour, required this.label, required this.total});

  factory PosHourlyBucket.fromJson(Map<String, dynamic> json) => PosHourlyBucket(
        hour: json['hour'] as int? ?? 0,
        label: json['label'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

class PosDailyBucket {
  final String date;
  final double total;

  const PosDailyBucket({required this.date, required this.total});

  factory PosDailyBucket.fromJson(Map<String, dynamic> json) => PosDailyBucket(
        date: json['date'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
      );
}

// ── GET /pos/reports/daily ───────────────────────────────────────────────────
class PosDailyReportModel {
  final String date;
  final int totalTransactions;
  final double totalRevenue;
  final double totalDiscount;
  final double totalTax;
  final double netRevenue;
  final double avgTransactionValue;
  final int refundsCount;
  final double refundsTotal;
  final PosPaymentBreakdown byPaymentMethod;
  final List<PosTopProduct> topProducts;
  final List<PosHourlyBucket> hourlyBreakdown;

  const PosDailyReportModel({
    required this.date,
    required this.totalTransactions,
    required this.totalRevenue,
    required this.totalDiscount,
    required this.totalTax,
    required this.netRevenue,
    required this.avgTransactionValue,
    required this.refundsCount,
    required this.refundsTotal,
    required this.byPaymentMethod,
    required this.topProducts,
    required this.hourlyBreakdown,
  });

  /// [data] must already be unwrapped of the `{success, data}` envelope by
  /// the repository — this factory owns nothing beyond the report shape.
  factory PosDailyReportModel.fromJson(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    return PosDailyReportModel(
      date: data['date'] as String? ?? '',
      totalTransactions: summary['totalTransactions'] as int? ?? 0,
      totalRevenue: (summary['totalRevenue'] as num?)?.toDouble() ?? 0,
      totalDiscount: (summary['totalDiscount'] as num?)?.toDouble() ?? 0,
      totalTax: (summary['totalTax'] as num?)?.toDouble() ?? 0,
      netRevenue: (summary['netRevenue'] as num?)?.toDouble() ?? 0,
      avgTransactionValue: (summary['avgTransactionValue'] as num?)?.toDouble() ?? 0,
      refundsCount: summary['refundsCount'] as int? ?? 0,
      refundsTotal: (summary['refundsTotal'] as num?)?.toDouble() ?? 0,
      byPaymentMethod: PosPaymentBreakdown.fromJson(data['byPaymentMethod'] as Map<String, dynamic>?),
      topProducts: (data['topProducts'] as List<dynamic>?)
              ?.map((e) => PosTopProduct.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      hourlyBreakdown: (data['hourlyBreakdown'] as List<dynamic>?)
              ?.map((e) => PosHourlyBucket.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

// ── GET /pos/sessions/:sessionId/report ──────────────────────────────────────
class PosSessionCashFlow {
  final double openingCash;
  final double cashSales;
  final double cashIn;
  final double cashOut;
  final double expectedCash;
  final double? closingCash;
  final double? cashDifference;

  const PosSessionCashFlow({
    required this.openingCash,
    required this.cashSales,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    this.closingCash,
    this.cashDifference,
  });

  bool get hasVariance => (cashDifference ?? 0).abs() > 0.009;
  bool get isShortfall => (cashDifference ?? 0) < 0;

  factory PosSessionCashFlow.fromJson(Map<String, dynamic>? json) =>
      PosSessionCashFlow(
        openingCash: (json?['openingCash'] as num?)?.toDouble() ?? 0,
        cashSales: (json?['cashSales'] as num?)?.toDouble() ?? 0,
        cashIn: (json?['cashIn'] as num?)?.toDouble() ?? 0,
        cashOut: (json?['cashOut'] as num?)?.toDouble() ?? 0,
        expectedCash: (json?['expectedCash'] as num?)?.toDouble() ?? 0,
        closingCash: (json?['closingCash'] as num?)?.toDouble(),
        cashDifference: (json?['cashDifference'] as num?)?.toDouble(),
      );
}

class PosSessionReportModel {
  final PosSessionModel session;
  final int totalTransactions;
  final double totalSales;
  final int completedSales;
  final int heldSales;
  final int refundsCount;
  final double refundsTotal;
  final PosPaymentBreakdown byPaymentMethod;
  final PosSessionCashFlow cashFlow;

  const PosSessionReportModel({
    required this.session,
    required this.totalTransactions,
    required this.totalSales,
    required this.completedSales,
    required this.heldSales,
    required this.refundsCount,
    required this.refundsTotal,
    required this.byPaymentMethod,
    required this.cashFlow,
  });

  // Flat pass-throughs kept for simple call sites (e.g. POS Settings shift stats).
  double get openingCash => cashFlow.openingCash;
  double? get closingCash => cashFlow.closingCash;
  double? get cashDifference => cashFlow.cashDifference;

  factory PosSessionReportModel.fromJson(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    return PosSessionReportModel(
      session: PosSessionModel.fromJson(data['session'] as Map<String, dynamic>? ?? {}),
      totalTransactions: summary['totalTransactions'] as int? ?? 0,
      totalSales: (summary['totalSales'] as num?)?.toDouble() ?? 0,
      completedSales: summary['completedSales'] as int? ?? 0,
      heldSales: summary['heldSales'] as int? ?? 0,
      refundsCount: summary['refundsCount'] as int? ?? 0,
      refundsTotal: (summary['refundsTotal'] as num?)?.toDouble() ?? 0,
      byPaymentMethod: PosPaymentBreakdown.fromJson(summary['byPaymentMethod'] as Map<String, dynamic>?),
      cashFlow: PosSessionCashFlow.fromJson(summary['cashFlow'] as Map<String, dynamic>?),
    );
  }
}

// ── GET /pos/reports/range ───────────────────────────────────────────────────
class PosRangeReportModel {
  final String from;
  final String to;
  final int totalTransactions;
  final double totalRevenue;
  final double totalDiscount;
  final double totalTax;
  final double netRevenue;
  final double avgTransactionValue;
  final int refundsCount;
  final double refundsTotal;
  final PosPaymentBreakdown byPaymentMethod;
  final List<PosTopProduct> topProducts;
  final List<PosDailyBucket> dailyBreakdown;

  const PosRangeReportModel({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalRevenue,
    required this.totalDiscount,
    required this.totalTax,
    required this.netRevenue,
    required this.avgTransactionValue,
    required this.refundsCount,
    required this.refundsTotal,
    required this.byPaymentMethod,
    required this.topProducts,
    required this.dailyBreakdown,
  });

  factory PosRangeReportModel.fromJson(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    return PosRangeReportModel(
      from: data['from'] as String? ?? '',
      to: data['to'] as String? ?? '',
      totalTransactions: summary['totalTransactions'] as int? ?? 0,
      totalRevenue: (summary['totalRevenue'] as num?)?.toDouble() ?? 0,
      totalDiscount: (summary['totalDiscount'] as num?)?.toDouble() ?? 0,
      totalTax: (summary['totalTax'] as num?)?.toDouble() ?? 0,
      netRevenue: (summary['netRevenue'] as num?)?.toDouble() ?? 0,
      avgTransactionValue: (summary['avgTransactionValue'] as num?)?.toDouble() ?? 0,
      refundsCount: summary['refundsCount'] as int? ?? 0,
      refundsTotal: (summary['refundsTotal'] as num?)?.toDouble() ?? 0,
      byPaymentMethod: PosPaymentBreakdown.fromJson(data['byPaymentMethod'] as Map<String, dynamic>?),
      topProducts: (data['topProducts'] as List<dynamic>?)
              ?.map((e) => PosTopProduct.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      dailyBreakdown: (data['dailyBreakdown'] as List<dynamic>?)
              ?.map((e) => PosDailyBucket.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

// ── GET /pos/reports/register/:registerId ────────────────────────────────────
class PosRegisterSessionSummary {
  final String sessionId;
  final String employeeId;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double totalSales;
  final int totalTransactions;
  final String status;

  const PosRegisterSessionSummary({
    required this.sessionId,
    required this.employeeId,
    this.openedAt,
    this.closedAt,
    required this.totalSales,
    required this.totalTransactions,
    required this.status,
  });

  factory PosRegisterSessionSummary.fromJson(Map<String, dynamic> json) =>
      PosRegisterSessionSummary(
        sessionId: json['sessionId'] as String? ?? json['_id'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        openedAt: json['openedAt'] != null ? DateTime.tryParse(json['openedAt'] as String) : null,
        closedAt: json['closedAt'] != null ? DateTime.tryParse(json['closedAt'] as String) : null,
        totalSales: (json['totalSales'] as num?)?.toDouble() ?? 0,
        totalTransactions: json['totalTransactions'] as int? ?? 0,
        status: json['status'] as String? ?? '',
      );
}

class PosRegisterReportModel {
  final StoreRegister register;
  final String? from;
  final String? to;
  final int totalSessions;
  final int totalTransactions;
  final double totalRevenue;
  final double avgPerSession;
  final List<PosRegisterSessionSummary> sessions;

  const PosRegisterReportModel({
    required this.register,
    this.from,
    this.to,
    required this.totalSessions,
    required this.totalTransactions,
    required this.totalRevenue,
    required this.avgPerSession,
    required this.sessions,
  });

  factory PosRegisterReportModel.fromJson(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final period = data['period'] as Map<String, dynamic>?;
    return PosRegisterReportModel(
      register: StoreRegister.fromJson(data['register'] as Map<String, dynamic>? ?? {}),
      from: period?['from'] as String?,
      to: period?['to'] as String?,
      totalSessions: summary['totalSessions'] as int? ?? 0,
      totalTransactions: summary['totalTransactions'] as int? ?? 0,
      totalRevenue: (summary['totalRevenue'] as num?)?.toDouble() ?? 0,
      avgPerSession: (summary['avgPerSession'] as num?)?.toDouble() ?? 0,
      sessions: (data['sessions'] as List<dynamic>?)
              ?.map((e) => PosRegisterSessionSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}

// ── GET /pos/reports/employee/:employeeId ────────────────────────────────────
class PosEmployeeRecentSale {
  final String saleId;
  final String saleNumber;
  final double total;
  final String paymentMethod;
  final DateTime? createdAt;

  const PosEmployeeRecentSale({
    required this.saleId,
    required this.saleNumber,
    required this.total,
    required this.paymentMethod,
    this.createdAt,
  });

  factory PosEmployeeRecentSale.fromJson(Map<String, dynamic> json) =>
      PosEmployeeRecentSale(
        saleId: json['saleId'] as String? ?? '',
        saleNumber: json['saleNumber'] as String? ?? '',
        total: (json['total'] as num?)?.toDouble() ?? 0,
        paymentMethod: json['paymentMethod'] as String? ?? '',
        createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt'] as String) : null,
      );
}

class PosEmployeeReportModel {
  final PosEmployeeModel employee;
  final String? from;
  final String? to;
  final int totalTransactions;
  final double totalRevenue;
  final double avgTransactionValue;
  final int totalSessions;
  final List<PosEmployeeRecentSale> recentSales;

  const PosEmployeeReportModel({
    required this.employee,
    this.from,
    this.to,
    required this.totalTransactions,
    required this.totalRevenue,
    required this.avgTransactionValue,
    required this.totalSessions,
    required this.recentSales,
  });

  factory PosEmployeeReportModel.fromJson(Map<String, dynamic> data) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final period = data['period'] as Map<String, dynamic>?;
    return PosEmployeeReportModel(
      employee: PosEmployeeModel.fromJson(data['employee'] as Map<String, dynamic>? ?? {}),
      from: period?['from'] as String?,
      to: period?['to'] as String?,
      totalTransactions: summary['totalTransactions'] as int? ?? 0,
      totalRevenue: (summary['totalRevenue'] as num?)?.toDouble() ?? 0,
      avgTransactionValue: (summary['avgTransactionValue'] as num?)?.toDouble() ?? 0,
      totalSessions: summary['totalSessions'] as int? ?? 0,
      recentSales: (data['recentSales'] as List<dynamic>?)
              ?.map((e) => PosEmployeeRecentSale.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
