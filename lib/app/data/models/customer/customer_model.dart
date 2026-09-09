/// A real customer of the store — either from the paginated past-buyers
/// list (`GET /api/store/:storeId/customers`, which includes order stats)
/// or a lighter row from the global user search
/// (`GET /api/draft-orders/:storeId/customers/search`, name/email/phone
/// only). The stats fields are simply absent (null) for search results
/// rather than using two separate model classes.
class CustomerModel {
  final String id;
  final String name;
  final String? email;
  final String? phone;
  final int? orderCount;
  final double? totalSpent;
  final String? segment; // 'new' | 'returning' | 'vip' | 'at_risk'

  const CustomerModel({
    required this.id,
    required this.name,
    this.email,
    this.phone,
    this.orderCount,
    this.totalSpent,
    this.segment,
  });

  /// From the store's past-buyers list — full stats.
  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
        id: json['_id'] as String? ?? json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        orderCount: json['orderCount'] as int?,
        totalSpent: (json['totalSpent'] as num?)?.toDouble(),
        segment: json['segment'] as String?,
      );

  /// From the global customer-search endpoint — name/email/phone only.
  factory CustomerModel.fromSearchJson(Map<String, dynamic> json) => CustomerModel(
        id: json['id'] as String? ?? json['_id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
      );
}
