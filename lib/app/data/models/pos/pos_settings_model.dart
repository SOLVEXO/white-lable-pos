class PosSettingsModel {
  final String storeId;
  final double taxRate; // 0..1
  final String? receiptHeader;
  final String? receiptFooter;
  final String? businessName;
  final String? businessAddress;
  final String? currencySymbol;

  const PosSettingsModel({
    required this.storeId,
    required this.taxRate,
    this.receiptHeader,
    this.receiptFooter,
    this.businessName,
    this.businessAddress,
    this.currencySymbol,
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
      );

  Map<String, dynamic> toUpdateJson({
    double? taxRate,
    String? receiptHeader,
    String? receiptFooter,
    String? businessName,
    String? businessAddress,
    String? currencySymbol,
  }) => {
        if (taxRate != null) 'taxRate': taxRate,
        if (receiptHeader != null) 'receiptHeader': receiptHeader,
        if (receiptFooter != null) 'receiptFooter': receiptFooter,
        if (businessName != null) 'businessName': businessName,
        if (businessAddress != null) 'businessAddress': businessAddress,
        if (currencySymbol != null) 'currencySymbol': currencySymbol,
      };
}
