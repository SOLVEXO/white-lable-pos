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

class ConnectorsStatus {
  const ConnectorsStatus({required this.flags, required this.cardGateway, required this.fiscal, this.raast});
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
