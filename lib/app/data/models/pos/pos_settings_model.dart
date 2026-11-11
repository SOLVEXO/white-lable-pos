import 'package:solvexo_pos/app/data/models/pos/pos_admin_models.dart' show ReceiptOptions;

class PosSettingsModel {
  final String storeId;
  final double taxRate; // 0..1
  final String? receiptHeader;
  final String? receiptFooter;
  final String? businessName;
  final String? businessAddress;
  final String? currencySymbol; // legacy free text — display uses Money (currency code + exponent) instead
  /// The store's ISO-4217 currency and its minor-unit exponent, as told by the backend.
  final String currency;
  final int currencyExponent;
  final String? businessTaxId;
  /// Bumped by the server whenever something that changes pricing (the tax rate) changes; sent with every sale.
  final int settingsVersion;
  /// Owner-set idle minutes before the till locks to the PIN screen.
  final int autoLockMinutes;

  /// G2.6 store tax profile (as registered with the tax authority) — all optional.
  final String? taxNtn;
  final String? taxStrn;
  final String? taxLegalName;
  final String? taxRegisteredAddress;
  final String defaultTaxCategory; // standard | exempt

  /// G2.5 return policy: may a cashier return? limits above which a manager must approve (minor units / days; null = no limit).
  final bool cashierReturnsEnabled;
  final int? returnApprovalAboveMinor;
  final int? returnApprovalAfterDays;

  /// G4.4: what the owner's receipt designer says to print (defaults = everything, as before)
  final ReceiptOptions receiptOptions;

  /// G4.8: the store's security rules this till applies (cached for offline): a manager PIN to reprint; costs hidden from managers
  final bool requirePinForReprint;
  final bool hideCostsFromManagers;

  /// G4.9: the store's public id and the base of the receipt link a till builds OFFLINE (`<base><sale client key>`) — cached with the settings
  final String? storePublicId;
  final String? receiptLinkBase;

  const PosSettingsModel({
    required this.storeId,
    required this.taxRate,
    this.receiptHeader,
    this.receiptFooter,
    this.businessName,
    this.businessAddress,
    this.currencySymbol,
    this.currency = 'USD',
    this.currencyExponent = 2,
    this.businessTaxId,
    this.settingsVersion = 1,
    this.autoLockMinutes = 5,
    this.taxNtn,
    this.taxStrn,
    this.taxLegalName,
    this.taxRegisteredAddress,
    this.defaultTaxCategory = 'standard',
    this.cashierReturnsEnabled = false,
    this.returnApprovalAboveMinor,
    this.returnApprovalAfterDays,
    this.receiptOptions = const ReceiptOptions(),
    this.requirePinForReprint = false,
    this.hideCostsFromManagers = false,
    this.storePublicId,
    this.receiptLinkBase,
  });

  String get taxRatePercentLabel => '${(taxRate * 100).toStringAsFixed(taxRate * 100 % 1 == 0 ? 0 : 1)}%';

  factory PosSettingsModel.fromJson(Map<String, dynamic> json) => PosSettingsModel(
        storeId: json['storeId'] as String? ?? '',
        taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
        receiptHeader: json['receiptHeader'] as String?,
        receiptFooter: json['receiptFooter'] as String?,
        businessName: json['businessName'] as String?,
        businessAddress: json['businessAddress'] as String?,
        currencySymbol: json['currencySymbol'] as String?,
        currency: (json['currency'] as String?)?.toUpperCase() ?? 'USD',
        currencyExponent: (json['currencyExponent'] as num?)?.toInt() ?? 2,
        businessTaxId: json['businessTaxId'] as String?,
        settingsVersion: (json['settingsVersion'] as num?)?.toInt() ?? 1,
        autoLockMinutes: (json['autoLockMinutes'] as num?)?.toInt() ?? 5,
        taxNtn: json['taxNtn'] as String?,
        taxStrn: json['taxStrn'] as String?,
        taxLegalName: json['taxLegalName'] as String?,
        taxRegisteredAddress: json['taxRegisteredAddress'] as String?,
        defaultTaxCategory: json['defaultTaxCategory'] as String? ?? 'standard',
        cashierReturnsEnabled: json['cashierReturnsEnabled'] as bool? ?? false,
        returnApprovalAboveMinor: (json['returnApprovalAboveMinor'] as num?)?.toInt(),
        returnApprovalAfterDays: (json['returnApprovalAfterDays'] as num?)?.toInt(),
        receiptOptions: json['receiptOptions'] is Map ? ReceiptOptions.fromJson((json['receiptOptions'] as Map).cast<String, dynamic>()) : const ReceiptOptions(),
        requirePinForReprint: (json['securityPrefs'] is Map && json['securityPrefs']['requirePinForReprint'] == true) || json['requirePinForReprint'] == true,
        hideCostsFromManagers: (json['securityPrefs'] is Map && json['securityPrefs']['hideCostsFromManagers'] == true) || json['hideCostsFromManagers'] == true,
        storePublicId: json['storePublicId'] as String?,
        receiptLinkBase: json['receiptLinkBase'] as String?,
      );

  /// The same settings with the pricing fields the server just told us about (a quote answered with a newer tax rate).
  PosSettingsModel withPricing({required double taxRate, required int settingsVersion}) => PosSettingsModel(
        storeId: storeId, taxRate: taxRate, receiptHeader: receiptHeader, receiptFooter: receiptFooter, businessName: businessName,
        businessAddress: businessAddress, currencySymbol: currencySymbol, currency: currency, currencyExponent: currencyExponent,
        businessTaxId: businessTaxId, settingsVersion: settingsVersion, autoLockMinutes: autoLockMinutes,
        taxNtn: taxNtn, taxStrn: taxStrn, taxLegalName: taxLegalName, taxRegisteredAddress: taxRegisteredAddress, defaultTaxCategory: defaultTaxCategory,
        cashierReturnsEnabled: cashierReturnsEnabled, returnApprovalAboveMinor: returnApprovalAboveMinor, returnApprovalAfterDays: returnApprovalAfterDays,
        receiptOptions: receiptOptions,
        requirePinForReprint: requirePinForReprint,
        hideCostsFromManagers: hideCostsFromManagers,
        storePublicId: storePublicId,
        receiptLinkBase: receiptLinkBase,
      );

  /// For the on-device settings cache (round-trips through [fromJson]).
  Map<String, dynamic> toCacheJson() => {
        'storeId': storeId,
        'taxRate': taxRate,
        'receiptHeader': receiptHeader,
        'receiptFooter': receiptFooter,
        'businessName': businessName,
        'businessAddress': businessAddress,
        'currencySymbol': currencySymbol,
        'currency': currency,
        'currencyExponent': currencyExponent,
        'businessTaxId': businessTaxId,
        'settingsVersion': settingsVersion,
        'autoLockMinutes': autoLockMinutes,
        'taxNtn': taxNtn,
        'taxStrn': taxStrn,
        'taxLegalName': taxLegalName,
        'taxRegisteredAddress': taxRegisteredAddress,
        'defaultTaxCategory': defaultTaxCategory,
        'cashierReturnsEnabled': cashierReturnsEnabled,
        'returnApprovalAboveMinor': returnApprovalAboveMinor,
        'returnApprovalAfterDays': returnApprovalAfterDays,
        'receiptOptions': receiptOptions.toJson(),
        'requirePinForReprint': requirePinForReprint,
        'hideCostsFromManagers': hideCostsFromManagers,
        'storePublicId': storePublicId,
        'receiptLinkBase': receiptLinkBase,
      };

  Map<String, dynamic> toUpdateJson({
    double? taxRate,
    String? receiptHeader,
    String? receiptFooter,
    String? businessName,
    String? businessAddress,
    String? currencySymbol,
    String? businessTaxId,
  }) => {
        if (taxRate != null) 'taxRate': taxRate,
        if (receiptHeader != null) 'receiptHeader': receiptHeader,
        if (receiptFooter != null) 'receiptFooter': receiptFooter,
        if (businessName != null) 'businessName': businessName,
        if (businessAddress != null) 'businessAddress': businessAddress,
        if (currencySymbol != null) 'currencySymbol': currencySymbol,
        if (businessTaxId != null) 'businessTaxId': businessTaxId,
      };
}
