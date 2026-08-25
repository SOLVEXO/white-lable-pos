class StoreLocationModel {
  final String id;
  final String storeId;
  final String sellerId;
  final String name;
  final String? addressLine1;
  final String? city;
  final String? phone;
  final String status;
  final DateTime createdAt;

  const StoreLocationModel({
    required this.id,
    required this.storeId,
    required this.sellerId,
    required this.name,
    this.addressLine1,
    this.city,
    this.phone,
    required this.status,
    required this.createdAt,
  });

  factory StoreLocationModel.fromJson(Map<String, dynamic> json) =>
      StoreLocationModel(
        id: json['_id'] as String? ?? '',
        storeId: json['storeId'] as String? ?? '',
        sellerId: json['sellerId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        addressLine1: json['addressLine1'] as String?,
        city: json['city'] as String?,
        phone: json['phone'] as String?,
        status: json['status'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  bool get isActive => status == 'active';

  /// "addressLine1, city" — skips whichever parts are missing.
  String get addressLabel => [addressLine1, city]
      .where((p) => p != null && p.trim().isNotEmpty)
      .join(', ');
}
