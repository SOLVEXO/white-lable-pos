class PosEmployeeModel {
  final String id;
  final String storeId;
  final String sellerId;
  final String name;
  final String email;
  final String role;
  final List<String> shiftIds;
  final String status;
  final DateTime createdAt;

  const PosEmployeeModel({
    required this.id,
    required this.storeId,
    required this.sellerId,
    required this.name,
    required this.email,
    required this.role,
    required this.shiftIds,
    required this.status,
    required this.createdAt,
  });

  factory PosEmployeeModel.fromJson(Map<String, dynamic> json) =>
      PosEmployeeModel(
        id: json['_id'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        sellerId: json['sellerId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        role: json['role'] as String? ?? '',
        shiftIds: List<String>.from(json['shiftIds'] ?? []),
        status: json['status'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : 'E';
  }
}
