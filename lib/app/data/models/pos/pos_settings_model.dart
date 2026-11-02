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
      );

  /// The same settings with the pricing fields the server just told us about (a quote answered with a newer tax rate).
  PosSettingsModel withPricing({required double taxRate, required int settingsVersion}) => PosSettingsModel(
        storeId: storeId, taxRate: taxRate, receiptHeader: receiptHeader, receiptFooter: receiptFooter, businessName: businessName,
        businessAddress: businessAddress, currencySymbol: currencySymbol, currency: currency, currencyExponent: currencyExponent,
        businessTaxId: businessTaxId, settingsVersion: settingsVersion,
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
