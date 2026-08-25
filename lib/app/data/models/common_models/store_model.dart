import 'package:solvexo_pos/app/data/models/store/store_announcement_bar_model.dart';
import 'package:flutter/material.dart';

// ── Register / Shift sub-models ───────────────────────────────────────────────

class StoreRegister {
  final String id;
  final String name;
  final double defaultFloatCash;
  final String status;

  const StoreRegister({
    required this.id,
    required this.name,
    required this.defaultFloatCash,
    required this.status,
  });

  factory StoreRegister.fromJson(Map<String, dynamic> json) => StoreRegister(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    defaultFloatCash: (json['defaultFloatCash'] as num?)?.toDouble() ?? 0,
    status: json['status'] as String? ?? '',
  );
}

class StoreShift {
  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final List<int> daysOfWeek;
  final String status;

  const StoreShift({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.daysOfWeek,
    required this.status,
  });

  factory StoreShift.fromJson(Map<String, dynamic> json) => StoreShift(
    id: json['_id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    startTime: json['startTime'] as String? ?? '',
    endTime: json['endTime'] as String? ?? '',
    daysOfWeek: List<int>.from(json['daysOfWeek'] ?? []),
    status: json['status'] as String? ?? '',
  );
}

// ── Main model ────────────────────────────────────────────────────────────────

class StoreModel {
  final String id;
  final String sellerId;
  final String name;
  final String slug;
  final String logo;
  final String coverImage;
  final String categoryId;
  final String description;
  final String sellerType;
  final List<String> productTypes;
  final List<String> enabledTools;
  final String plan;
  final int aiCredits;
  /// Marketplace LISTING lifecycle only (`pending|active|rejected|suspended`)
  /// — deliberately independent of [verificationStatus] below (see
  /// `store.schema.ts`). Admin approve/reject happens to move both together
  /// today, but they're separate fields.
  final String status;
  /// Set by AdminMarketplaceService.rejectLead — null unless `status == 'rejected'`.
  final String? rejectionReason;
  final String? baseCurrency;
  /// Where the seller says they operate — drives KYC requirement calculation
  /// server-side. Defaults to Solvexo's home market ('PK').
  final String country;
  /// KYC business type ('individual'|'company'|'partnership') — top-level on
  /// Store, separate from [sellerType] (a marketplace concept like 'creator').
  final String? businessType;
  /// Server-derived from [businessType] ('basic'|'business'|'enhanced') —
  /// never client-supplied.
  final String? verificationLevel;
  /// The KYC review's own state (`not_started|pending|under_review|verified|
  /// rejected`) — independent of [status]. See `store_verification` module.
  final String verificationStatus;
  final bool isDelete;
  final List<StoreRegister> registers;
  final List<StoreShift> shifts;
  final String sellerName;
  final String sellerEmail;
  /// Only present when GET /api/store/getStoreById is called by the owning
  /// seller (see StoreService.getStoreById) — never returned to anonymous or
  /// other-store callers.
  final String? sellerPhone;

  /// Per-store stats. `productCount`/`totalSalesUSD` come from either
  /// GET /api/store/my-stores or (owner-only) GET /api/store/getStoreById;
  /// `orderCount` is owner-only (getStoreById); `averageRating`/`reviewCount`
  /// live directly on the Store document (`RatingService.recalcStoreRating`)
  /// and are always present regardless of auth.
  final int productCount;
  final int orderCount;
  final double totalSalesUSD;
  final double averageRating;
  final int reviewCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Seller-managed storefront merchandising (`src/store/schemas/store.schema.ts`).
  final List<String> pinnedProductIds;
  final StoreAnnouncementBarModel announcementBar;

  const StoreModel({
    required this.id,
    required this.sellerId,
    required this.name,
    required this.slug,
    required this.logo,
    this.coverImage = '',
    required this.categoryId,
    required this.description,
    required this.sellerType,
    required this.productTypes,
    required this.enabledTools,
    required this.plan,
    required this.aiCredits,
    required this.status,
    this.rejectionReason,
    this.baseCurrency,
    this.country = 'PK',
    this.businessType,
    this.verificationLevel,
    this.verificationStatus = 'not_started',
    required this.isDelete,
    required this.registers,
    required this.shifts,
    required this.sellerName,
    required this.sellerEmail,
    this.sellerPhone,
    this.productCount = 0,
    this.orderCount = 0,
    this.totalSalesUSD = 0,
    this.averageRating = 0,
    this.reviewCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.pinnedProductIds = const [],
    this.announcementBar = const StoreAnnouncementBarModel(),
  });

  bool get isActive => status == 'active' && !isDelete;

  String get initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'S';
  }

  /// Human-readable seller type label (e.g. "creator" → "Creator")
  String get sellerTypeLabel => sellerType.isNotEmpty
      ? sellerType[0].toUpperCase() + sellerType.substring(1)
      : '';

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    try {
      return StoreModel(
        id: json['_id'] as String? ?? '',
        sellerId: json['sellerId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        slug: json['slug'] as String? ?? '',
        logo: json['logo'] as String? ?? '',
        coverImage: json['coverImage'] as String? ?? '',
        categoryId: json['categoryId'] as String? ?? '',
        description: json['description'] as String? ?? '',
        sellerType: json['sellerType'] as String? ?? '',
        productTypes: List<String>.from(json['productTypes'] ?? []),
        enabledTools: List<String>.from(json['enabledTools'] ?? []),
        plan: json['plan'] as String? ?? '',
        aiCredits: json['aiCredits'] as int? ?? 0,
        status: json['status'] as String? ?? '',
        rejectionReason: json['rejectionReason'] as String?,
        baseCurrency: json['baseCurrency'] as String?,
        country: json['country'] as String? ?? 'PK',
        businessType: json['businessType'] as String?,
        verificationLevel: json['verificationLevel'] as String?,
        verificationStatus: json['verificationStatus'] as String? ?? 'not_started',
        isDelete: json['isDelete'] as bool? ?? false,
        registers:
            (json['registers'] as List<dynamic>?)
                ?.map((e) => StoreRegister.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        shifts:
            (json['shifts'] as List<dynamic>?)
                ?.map((e) => StoreShift.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        sellerName: json['sellerName'] as String? ?? '',
        sellerEmail: json['sellerEmail'] as String? ?? '',
        sellerPhone: json['sellerPhone'] as String?,
        productCount: json['productCount'] as int? ?? 0,
        orderCount: json['orderCount'] as int? ?? 0,
        totalSalesUSD: (json['totalSalesUSD'] as num?)?.toDouble() ?? 0,
        averageRating: (json['averageRating'] as num?)?.toDouble() ?? 0,
        reviewCount: json['reviewCount'] as int? ?? 0,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        pinnedProductIds: (json['pinnedProductIds'] as List?)?.cast<String>() ?? const [],
        announcementBar: json['announcementBar'] is Map<String, dynamic>
            ? StoreAnnouncementBarModel.fromJson(json['announcementBar'] as Map<String, dynamic>)
            : const StoreAnnouncementBarModel(),
      );
    } catch (e) {
      debugPrint('❌ StoreModel.fromJson error: $e  json: $json');
      rethrow;
    }
  }
}
