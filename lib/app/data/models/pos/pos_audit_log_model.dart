class PosAuditLogModel {
  final String id;
  final String storeId;
  final String? employeeId;
  final String action;
  final String? targetId;
  final String? targetType;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  const PosAuditLogModel({
    required this.id,
    required this.storeId,
    this.employeeId,
    required this.action,
    this.targetId,
    this.targetType,
    this.metadata,
    required this.createdAt,
  });

  /// Turns a backend action key like "sale_refunded_partial" into
  /// "Sale refunded partial" for display.
  String get actionLabel => action
      .split('_')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  factory PosAuditLogModel.fromJson(Map<String, dynamic> json) => PosAuditLogModel(
        id: json['_id'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        employeeId: json['employeeId'] as String?,
        action: json['action'] as String? ?? '',
        targetId: json['targetId'] as String?,
        targetType: json['targetType'] as String?,
        metadata: json['metadata'] as Map<String, dynamic>?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );
}
