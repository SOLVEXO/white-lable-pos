/// G5.4 / G5.7 — the store's provider-dependent features (each OFF until turned on) and what the server has for each.
class ConnectorProvider {
  const ConnectorProvider({this.provider, this.testMode = false, this.configured = false, this.needs = const []});
  final String? provider;
  final bool testMode;
  final bool configured;
  final List<String> needs;
  factory ConnectorProvider.fromJson(dynamic j) {
    final m = j is Map ? j : const {};
    return ConnectorProvider(
      provider: m['provider'] as String?,
      testMode: m['testMode'] == true,
      configured: m['configured'] == true,
      needs: [for (final n in (m['needs'] as List? ?? const [])) '$n'],
    );
  }
}

class RaastStatus {
  const RaastStatus({required this.kybStatus, required this.enabled, this.reason, this.providerKey, this.testMode = false, this.disabledByStore = false, this.adaptersPending = const []});
  final String kybStatus;
  final bool enabled;
  final String? reason;
  final String? providerKey;
  final bool testMode;
  final bool disabledByStore;
  final List<String> adaptersPending;
  bool get verified => kybStatus == 'verified';
  factory RaastStatus.fromJson(Map j) => RaastStatus(
        kybStatus: (j['kybStatus'] as String?) ?? 'not_started',
        enabled: j['enabled'] == true,
        reason: j['reason'] as String?,
        providerKey: j['providerKey'] as String?,
        testMode: j['testMode'] == true,
        disabledByStore: j['disabledByStore'] == true,
        adaptersPending: [for (final n in (j['adaptersPending'] as List? ?? const [])) '$n'],
      );
}

/// G6.1 — one field the cashier fills for a card paid on a separate bank terminal, as the server defines it (label, required, rule).
class TerminalField {
  const TerminalField({required this.key, required this.label, this.required = false, this.pattern, this.maxLength, this.numeric = false});
  final String key, label;
  final bool required;
  final String? pattern;
  final int? maxLength;
  final bool numeric;
  factory TerminalField.fromJson(Map j) => TerminalField(
        key: '${j['key']}',
        label: '${j['label'] ?? j['key']}',
        required: j['required'] == true,
        pattern: j['pattern'] as String?,
        maxLength: (j['maxLength'] as num?)?.toInt(),
        numeric: j['keyboard'] == 'number',
      );
  /// null = valid; otherwise what to say
  String? validate(String v) {
    final t = v.trim();
    if (t.isEmpty) return required ? 'Enter the $label.' : null;
    if (maxLength != null && t.length > maxLength!) return '$label: at most $maxLength characters.';
    if (pattern != null && !(RegExp(pattern!).hasMatch(t))) return 'Check the $label.';
    return null;
  }
}

/// G6.1 — the wording, fields and rules of provider-dependent features, sent by the server (`connectors.ui`) so a real provider needs no app
/// update. Every value falls back to what the app showed before (an older backend sends no `ui`).
class ConnectorUi {
  const ConnectorUi({
    this.raastCustomerInstructions = 'Customer: open your bank app, choose Raast and scan.',
    this.raastPollAfterMs = 2000,
    this.raastSimulateAvailable,
    this.raastReasonText,
    this.terminalLabel = 'Card on a bank terminal',
    this.terminalFields = defaultTerminalFields,
    this.cardGatewayStatusText,
    this.fiscalTitle = 'Fiscal invoices',
    this.whatsappMode = 'link',
    this.minPhoneDigits = 10,
    this.consentText = 'The customer gave this contact for their receipt',
    this.privacyNote = 'Only the store name, the total and the receipt link are sent.',
  });
  static const defaultTerminalFields = [
    TerminalField(key: 'approvalCode', label: 'Approval code', required: true),
    TerminalField(key: 'last4', label: 'Last 4', pattern: r'^\d{4}$', maxLength: 4, numeric: true),
    TerminalField(key: 'terminalLabel', label: 'Terminal'),
  ];
  final String raastCustomerInstructions;
  final int raastPollAfterMs;
  /// null = the server did not say (older backend): debug builds keep the simulate button, release never shows it
  final bool? raastSimulateAvailable;
  final String? raastReasonText;
  final String terminalLabel;
  final List<TerminalField> terminalFields;
  final String? cardGatewayStatusText;
  final String fiscalTitle;
  /// link (wa.me from the app) | api (the server sends it) | off (no WhatsApp button)
  final String whatsappMode;
  final int minPhoneDigits;
  final String consentText, privacyNote;

  TerminalField? field(String key) => terminalFields.where((f) => f.key == key).firstOrNull;

  factory ConnectorUi.fromJson(dynamic j) {
    if (j is! Map) return const ConnectorUi();
    const d = ConnectorUi();
    final r = j['raast'] is Map ? j['raast'] as Map : const {};
    final t = j['cardExternalTerminal'] is Map ? j['cardExternalTerminal'] as Map : const {};
    final g = j['cardGateway'] is Map ? j['cardGateway'] as Map : const {};
    final f = j['fiscal'] is Map ? j['fiscal'] as Map : const {};
    final rc = j['receipts'] is Map ? j['receipts'] as Map : const {};
    final fields = [for (final x in (t['fields'] as List? ?? const [])) if (x is Map && x['key'] != null) TerminalField.fromJson(x)];
    String str(Map m, String k, String fb) => m[k] is String && (m[k] as String).isNotEmpty ? m[k] as String : fb;
    return ConnectorUi(
      raastCustomerInstructions: str(r, 'customerInstructions', d.raastCustomerInstructions),
      raastPollAfterMs: ((r['pollAfterMs'] as num?)?.toInt() ?? d.raastPollAfterMs).clamp(500, 30000),
      raastSimulateAvailable: r['simulateAvailable'] is bool ? r['simulateAvailable'] as bool : null,
      raastReasonText: r['reasonText'] as String?,
      terminalLabel: str(t, 'label', d.terminalLabel),
      terminalFields: fields.isEmpty ? defaultTerminalFields : fields,
      cardGatewayStatusText: g['statusText'] as String?,
      fiscalTitle: str(f, 'title', d.fiscalTitle),
      whatsappMode: (rc['whatsapp'] is Map ? (rc['whatsapp'] as Map)['mode'] as String? : null) ?? d.whatsappMode,
      minPhoneDigits: (rc['minPhoneDigits'] as num?)?.toInt() ?? d.minPhoneDigits,
      consentText: str(rc, 'consentText', d.consentText),
      privacyNote: str(rc, 'privacyNote', d.privacyNote),
    );
  }
}

/// The last `connectors.ui` the till saw (any screen that loads connectors updates it); defaults until then and on an older backend.
class ConnectorUiStore {
  static ConnectorUi current = const ConnectorUi();
}

class ConnectorsStatus {
  const ConnectorsStatus({required this.flags, required this.cardGateway, required this.fiscal, this.raast, this.ui = const ConnectorUi()});
  final ConnectorUi ui;
  final Map<String, bool> flags;
  final ConnectorProvider cardGateway;
  final ConnectorProvider fiscal;
  final RaastStatus? raast;
  bool flag(String k) => flags[k] == true;
  bool get cardExternalTerminal => flag('cardExternalTerminal');
  bool get fiscalOn => flag('fiscal');
  factory ConnectorsStatus.fromJson(Map j) => ConnectorsStatus(
        flags: {for (final e in ((j['flags'] as Map?) ?? const {}).entries) '${e.key}': e.value == true},
        cardGateway: ConnectorProvider.fromJson(j['cardGateway']),
        fiscal: ConnectorProvider.fromJson(j['fiscal']),
        raast: j['raast'] is Map ? RaastStatus.fromJson(j['raast'] as Map) : null,
        ui: ConnectorUiStore.current = ConnectorUi.fromJson(j['ui']),
      );
}

/// G5.7 — a store API key as the owner sees it (the secret is shown only once, at creation).
class StoreApiKey {
  const StoreApiKey({required this.id, required this.name, required this.prefix, required this.scopes, required this.status, this.createdAt, this.expiresAt, this.lastUsedAt});
  final String id, name, prefix, status; // active | expired | revoked
  final List<String> scopes;
  final DateTime? createdAt, expiresAt, lastUsedAt;
  bool get active => status == 'active';
  static DateTime? _d(dynamic v) => v == null ? null : DateTime.tryParse('$v');
  factory StoreApiKey.fromJson(Map j) => StoreApiKey(
        id: '${j['id'] ?? ''}',
        name: '${j['name'] ?? ''}',
        prefix: '${j['prefix'] ?? ''}',
        scopes: [for (final s in (j['scopes'] as List? ?? const [])) '$s'],
        status: '${j['status'] ?? 'active'}',
        createdAt: _d(j['createdAt']),
        expiresAt: _d(j['expiresAt']),
        lastUsedAt: _d(j['lastUsedAt']),
      );

  static String scopeLabel(String s) => switch (s) {
        'sales:read' => 'Read sales',
        'inventory:read' => 'Read stock',
        'accounting:read' => 'Accounting export',
        _ => s,
      };
}

class StoreApiKeys {
  const StoreApiKeys({this.keys = const [], this.scopes = const [], this.maxActive = 10, this.ratePerMinute = 60});
  final List<StoreApiKey> keys;
  final List<String> scopes;
  final int maxActive, ratePerMinute;
  factory StoreApiKeys.fromJson(Map j) => StoreApiKeys(
        keys: [for (final k in (j['keys'] as List? ?? const [])) if (k is Map) StoreApiKey.fromJson(k)],
        scopes: [for (final s in (j['scopes'] as List? ?? const [])) '$s'],
        maxActive: (j['maxActive'] as num?)?.toInt() ?? 10,
        ratePerMinute: (j['ratePerMinute'] as num?)?.toInt() ?? 60,
      );
}

/// G6.1 — a fiscal document the owner should look at (latest attempt failed / refused / retries stopped). [retryable] = the owner may send it again.
class FiscalIssue {
  const FiscalIssue({required this.documentType, required this.documentId, required this.documentNumber, required this.status, this.saleId, this.message, this.attempts = 0, this.lastAttemptAt, this.retryable = false});
  final String documentType, documentId, documentNumber, status;
  final String? saleId, message;
  final int attempts;
  final DateTime? lastAttemptAt;
  final bool retryable;
  factory FiscalIssue.fromJson(Map j) => FiscalIssue(
        documentType: '${j['documentType'] ?? ''}',
        documentId: '${j['documentId'] ?? ''}',
        documentNumber: '${j['documentNumber'] ?? ''}',
        status: '${j['status'] ?? ''}',
        saleId: j['saleId'] as String?,
        message: j['message'] as String?,
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastAttemptAt: j['lastAttemptAt'] == null ? null : DateTime.tryParse('${j['lastAttemptAt']}'),
        retryable: j['retryable'] == true,
      );
}
