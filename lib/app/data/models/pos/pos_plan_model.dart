/// An admin-authored POS plan (fixed-term, one-time purchase — see backend
/// spec). `price`/`currency`/`durationInDays` are entirely admin-set; the
/// client never hardcodes plan tiers or duration units.
class PosPlanModel {
  final String id;
  final String name;
  final num price;
  final String currency;
  final int durationInDays;
  final String? description;

  const PosPlanModel({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.durationInDays,
    this.description,
  });

  factory PosPlanModel.fromJson(Map<String, dynamic> json) => PosPlanModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        price: json['price'] as num? ?? 0,
        currency: json['currency'] as String? ?? 'USD',
        durationInDays: json['durationInDays'] as int? ?? 0,
        description: json['description'] as String?,
      );
}
