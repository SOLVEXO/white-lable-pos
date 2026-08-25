/// A seller's storefront announcement bar — `solvexo-api`'s
/// `StoreAnnouncementBar` schema (embedded on `Store`,
/// `src/store/schemas/store.schema.ts`).
class StoreAnnouncementBarModel {
  final String? message;
  final String type; // info | sale | coupon | warning | shipping | holiday
  final String? ctaLabel;
  final String? ctaLink;
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;

  const StoreAnnouncementBarModel({
    this.message,
    this.type = 'info',
    this.ctaLabel,
    this.ctaLink,
    this.isActive = false,
    this.startAt,
    this.endAt,
  });

  /// Whether this bar should actually be shown right now — active flag AND
  /// (if set) within its scheduling window.
  bool get isCurrentlyVisible {
    if (!isActive || (message?.trim().isEmpty ?? true)) return false;
    final now = DateTime.now();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }

  factory StoreAnnouncementBarModel.fromJson(Map<String, dynamic> json) => StoreAnnouncementBarModel(
        message: json['message'] as String?,
        type: json['type'] as String? ?? 'info',
        ctaLabel: json['ctaLabel'] as String?,
        ctaLink: json['ctaLink'] as String?,
        isActive: json['isActive'] as bool? ?? false,
        startAt: json['startAt'] != null ? DateTime.tryParse(json['startAt'].toString()) : null,
        endAt: json['endAt'] != null ? DateTime.tryParse(json['endAt'].toString()) : null,
      );

  Map<String, dynamic> toJson() => {
        'message': message,
        'type': type,
        'ctaLabel': ctaLabel,
        'ctaLink': ctaLink,
        'isActive': isActive,
        if (startAt != null) 'startAt': startAt!.toIso8601String(),
        if (endAt != null) 'endAt': endAt!.toIso8601String(),
      };
}

const Map<String, String> kAnnouncementTypeLabels = {
  'info': 'Info',
  'sale': 'Sale',
  'coupon': 'Coupon',
  'warning': 'Warning',
  'shipping': 'Shipping',
  'holiday': 'Holiday',
};
