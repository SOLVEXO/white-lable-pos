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

  factory PosCashAdjustment.fromJson(Map<String, dynamic> json) =>
      PosCashAdjustment(
        type: json['type'] as String? ?? '',
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
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
  });

  bool get isOpen => status == 'open';
  bool get isForceClosed => forceClosedBy != null;

  factory PosSessionModel.fromJson(Map<String, dynamic> json) =>
      PosSessionModel(
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
        openingCash: (json['openingCash'] as num?)?.toDouble() ?? 0,
        closingCash: (json['closingCash'] as num?)?.toDouble(),
        expectedCash: (json['expectedCash'] as num?)?.toDouble() ?? 0,
        cashDifference: (json['cashDifference'] as num?)?.toDouble() ?? 0,
        cashSales: (json['cashSales'] as num?)?.toDouble() ?? 0,
        cardSales: (json['cardSales'] as num?)?.toDouble() ?? 0,
        otherSales: (json['otherSales'] as num?)?.toDouble() ?? 0,
        totalSales: (json['totalSales'] as num?)?.toDouble() ?? 0,
        totalTransactions: json['totalTransactions'] as int? ?? 0,
        totalRefunds: (json['totalRefunds'] as num?)?.toDouble() ?? 0,
        status: json['status'] as String? ?? '',
        cashAdjustments: (json['cashAdjustments'] as List<dynamic>?)
                ?.map((e) =>
                    PosCashAdjustment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        forceClosedBy: json['forceClosedBy'] as String?,
        forceCloseReason: json['forceCloseReason'] as String?,
        forceCloseAt: json['forceCloseAt'] != null
            ? DateTime.tryParse(json['forceCloseAt'] as String)
            : null,
      );
}
