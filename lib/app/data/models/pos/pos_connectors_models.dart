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
