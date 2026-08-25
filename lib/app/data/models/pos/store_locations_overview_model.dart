/// Per-branch stats row from GET pos/locations/:storeId/overview.
/// [locationId] is null for the backend's "Unassigned (legacy)" bucket.
class LocationOverviewStat {
  final String? locationId;
  final String name;
  final String? city;
  final String status;
  final double totalSales;
  final int transactionCount;

  const LocationOverviewStat({
    this.locationId,
    required this.name,
    this.city,
    required this.status,
    required this.totalSales,
    required this.transactionCount,
  });

  factory LocationOverviewStat.fromJson(Map<String, dynamic> json) =>
      LocationOverviewStat(
        locationId: json['locationId'] as String?,
        name: json['name'] as String? ?? '',
        city: json['city'] as String?,
        status: json['status'] as String? ?? '',
        totalSales: (json['totalSales'] as num?)?.toDouble() ?? 0,
        transactionCount: (json['transactionCount'] as num?)?.toInt() ?? 0,
      );
}

class StoreLocationsOverviewModel {
  final DateTime? from;
  final DateTime? to;
  final double combinedTotalSales;
  final int combinedTransactionCount;
  final List<LocationOverviewStat> byLocation;

  const StoreLocationsOverviewModel({
    this.from,
    this.to,
    required this.combinedTotalSales,
    required this.combinedTransactionCount,
    required this.byLocation,
  });

  static const empty = StoreLocationsOverviewModel(
    combinedTotalSales: 0,
    combinedTransactionCount: 0,
    byLocation: [],
  );

  factory StoreLocationsOverviewModel.fromJson(Map<String, dynamic> json) =>
      StoreLocationsOverviewModel(
        from: json['from'] != null
            ? DateTime.tryParse(json['from'] as String)
            : null,
        to: json['to'] != null ? DateTime.tryParse(json['to'] as String) : null,
        combinedTotalSales: (json['combinedTotalSales'] as num?)?.toDouble() ?? 0,
        combinedTransactionCount:
            (json['combinedTransactionCount'] as num?)?.toInt() ?? 0,
        byLocation: (json['byLocation'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(LocationOverviewStat.fromJson)
            .toList(),
      );
}
