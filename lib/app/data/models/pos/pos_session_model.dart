import 'package:solvexo_pos/utils/money_json.dart';
class PosCashAdjustment {
  final String type; // "cash_in" | "cash_out"
  final double amount;
  final String reason;
  final String employeeId;
  final DateTime createdAt;

  const PosCashAdjustment({
    required this.type,
    required this.amount,
    required this.reason,
    required this.employeeId,
    required this.createdAt,
  });

  factory PosCashAdjustment.fromJson(Map<String, dynamic> json, {int? exp}) =>
      PosCashAdjustment(
        type: json['type'] as String? ?? '',
        amount: MoneyJson.read(json, 'amount', exp: exp),
        reason: json['reason'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}

class PosSessionModel {
  final String id;
  final String storeId;
  final String registerId;
  final String employeeId;
  final String shiftId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final double? closingCash;
  final double expectedCash;
  final double cashDifference;
  final double cashSales;
  final double cardSales;
  final double otherSales;
  final double totalSales;
  final int totalTransactions;
  final double totalRefunds;
  final String status; // "open" | "closed"
  final List<PosCashAdjustment> cashAdjustments;
  final String? forceClosedBy;
  final String? forceCloseReason;
  final DateTime? forceCloseAt;
  /// Currency snapshot of every cash figure on this session (JPY 0, USD 2, KWD 3 decimals).
  final String currency;
  final int currencyExponent;

  const PosSessionModel({
    required this.id,
    required this.storeId,
    required this.registerId,
    required this.employeeId,
    required this.shiftId,
    required this.openedAt,
    this.closedAt,
    required this.openingCash,
    this.closingCash,
    required this.expectedCash,
    required this.cashDifference,
    required this.cashSales,
    required this.cardSales,
    required this.otherSales,
    required this.totalSales,
    required this.totalTransactions,
    required this.totalRefunds,
    required this.status,
    required this.cashAdjustments,
    this.forceClosedBy,
    this.forceCloseReason,
    this.forceCloseAt,
    this.currency = 'USD',
    this.currencyExponent = 2,
  });

  bool get isOpen => status == 'open';
  bool get isForceClosed => forceClosedBy != null;

  factory PosSessionModel.fromJson(Map<String, dynamic> json) {
    final exp = (json['currencyExponent'] as num?)?.toInt() ?? 2;
    return PosSessionModel(
        id: json['_id'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        registerId: json['registerId'] as String? ?? '',
        employeeId: json['employeeId'] as String? ?? '',
        shiftId: json['shiftId'] as String? ?? '',
        openedAt: json['openedAt'] != null
            ? DateTime.tryParse(json['openedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        closedAt: json['closedAt'] != null
            ? DateTime.tryParse(json['closedAt'] as String)
            : null,
        openingCash: MoneyJson.read(json, 'openingCash', exp: exp),
        closingCash: MoneyJson.readNullable(json, 'closingCash', exp: exp),
        expectedCash: MoneyJson.read(json, 'expectedCash', exp: exp),
        cashDifference: MoneyJson.read(json, 'cashDifference', exp: exp),
        cashSales: MoneyJson.read(json, 'cashSales', exp: exp),
        cardSales: MoneyJson.read(json, 'cardSales', exp: exp),
        otherSales: MoneyJson.read(json, 'otherSales', exp: exp),
        totalSales: MoneyJson.read(json, 'totalSales', exp: exp),
        totalTransactions: json['totalTransactions'] as int? ?? 0,
        totalRefunds: MoneyJson.read(json, 'totalRefunds', exp: exp),
        status: json['status'] as String? ?? '',
        cashAdjustments: (json['cashAdjustments'] as List<dynamic>?)
                ?.map((e) =>
                    PosCashAdjustment.fromJson(e as Map<String, dynamic>, exp: exp))
                .toList() ??
            [],
        forceClosedBy: json['forceClosedBy'] as String?,
        forceCloseReason: json['forceCloseReason'] as String?,
        forceCloseAt: json['forceCloseAt'] != null
            ? DateTime.tryParse(json['forceCloseAt'] as String)
            : null,
        currency: (json['currency'] as String?)?.toUpperCase() ?? 'USD',
        currencyExponent: exp,
    );
  }
}
