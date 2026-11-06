/// The owner's business-verification application as the server shows it: sensitive values are MASKED (the server never sends them back
/// decrypted), documents are listed by name only. Nothing here is ever written to the device.
class KybDocumentInfo {
  final String id;
  final String type;
  final String fileName;
  const KybDocumentInfo({required this.id, required this.type, required this.fileName});
  factory KybDocumentInfo.fromJson(Map<String, dynamic> j) => KybDocumentInfo(id: j['id'] as String? ?? '', type: j['type'] as String? ?? '', fileName: j['fileName'] as String? ?? '');
}

class KybView {
  final String status; // draft | submitted | under_review | verified | rejected …
  final String? businessType;
  final String? legalBusinessName;
  final String? businessAddress;
  final String? contactName;
  final String? contactDesignation;
  final String? contactEmail;
  final String? contactPhone;
  final String? bankName;
  final String? cnicMasked;
  final String? ntnMasked;
  final String? ibanMasked;
  final bool accountTitleSet;
  final List<KybDocumentInfo> documents;
  final List<String> requiredDocuments;
  final List<String> optionalDocuments;
  final List<String> missingDocuments;
  final String? rejectionReason;
  final bool digitalPaymentsEnabled;

  const KybView({
    required this.status,
    this.businessType,
    this.legalBusinessName,
    this.businessAddress,
    this.contactName,
    this.contactDesignation,
    this.contactEmail,
    this.contactPhone,
    this.bankName,
    this.cnicMasked,
    this.ntnMasked,
    this.ibanMasked,
    this.accountTitleSet = false,
    this.documents = const [],
    this.requiredDocuments = const [],
    this.optionalDocuments = const [],
    this.missingDocuments = const [],
    this.rejectionReason,
    this.digitalPaymentsEnabled = false,
  });

  /// The owner may still edit and (re)submit.
  bool get editable => status == 'draft' || status == 'rejected' || status == 'not_started';
  bool get registeredBusiness => businessType == 'company' || businessType == 'partnership';

  factory KybView.fromJson(Map<String, dynamic> j) {
    final contact = (j['contact'] as Map?)?.cast<String, dynamic>() ?? const {};
    final req = (j['requirements'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<String> strs(dynamic v) => (v as List? ?? const []).map((e) => e.toString()).toList();
    return KybView(
      status: j['status'] as String? ?? 'draft',
      businessType: j['businessType'] as String?,
      legalBusinessName: j['legalBusinessName'] as String?,
      businessAddress: j['businessAddress'] as String?,
      contactName: contact['name'] as String?,
      contactDesignation: contact['designation'] as String?,
      contactEmail: contact['email'] as String?,
      contactPhone: contact['phone'] as String?,
      bankName: j['bankName'] as String?,
      cnicMasked: j['cnicMasked'] as String?,
      ntnMasked: j['ntnMasked'] as String?,
      ibanMasked: j['ibanMasked'] as String?,
      accountTitleSet: j['accountTitleSet'] as bool? ?? false,
      documents: (j['documents'] as List? ?? const []).map((e) => KybDocumentInfo.fromJson((e as Map).cast<String, dynamic>())).toList(),
      requiredDocuments: strs(req['requiredDocuments']),
      optionalDocuments: strs(req['optionalDocuments']),
      missingDocuments: strs(req['missingDocuments']),
      rejectionReason: j['rejectionReason'] as String?,
      digitalPaymentsEnabled: j['digitalPaymentsEnabled'] as bool? ?? false,
    );
  }
}

const kKybBusinessTypes = <(String, String)>[('sole_proprietor', 'Sole proprietor'), ('partnership', 'Partnership'), ('company', 'Company')];
const kKybDocumentLabels = <String, String>{
  'owner_cnic': 'Owner CNIC (front and back)',
  'business_registration': 'Business registration',
  'tax_registration': 'Tax registration (NTN)',
  'bank_proof': 'Bank proof (cheque or statement)',
  'address_proof': 'Address proof',
};
